using System.Text.Json;
using System.Text.RegularExpressions;
using Umbraco.Cms.Core.Events;
using Umbraco.Cms.Core.Models;
using Umbraco.Cms.Core.Notifications;
using Umbraco.Cms.Core.Services;
using uSync.BackOffice.Services;

namespace MooFamily.Cms.Web.Notifications;

/// <summary>
/// Blocks the removal of a dropdown item that is still assigned to content.
///
/// Editors add news categories, news tags and game platforms by editing the DataType in
/// Settings > Data Types. Nothing in Umbraco stops them removing an item that articles or
/// games still point at, which would silently orphan those values — and for a mandatory
/// property like <c>newsCategory</c> that makes the affected nodes unsavable.
///
/// Rather than diffing old items against new, this asserts an invariant:
/// <em>every value currently stored on content must still be present in the new item list.</em>
/// The Management API mutates the persisted <see cref="IDataType"/> in place, so there is no
/// reliable "previous value" to diff against by the time this notification fires. The invariant
/// is also strictly stronger — it catches a rename (remove + add), which should be blocked too.
///
/// Registered by <see cref="Composers.ContentGovernanceComposer"/>. Must be a synchronous
/// <see cref="INotificationHandler{T}"/>: DataTypeService publishes this through the scope's
/// synchronous PublishCancelable, so an async handler would never fire.
/// </summary>
public sealed partial class GovernedDropdownItemGuard : INotificationHandler<DataTypeSavingNotification>
{
    private sealed record GovernedField(Guid DataTypeKey, string ContentTypeAlias, string PropertyAlias, string Noun, bool InsideBlockList = false);

    private static readonly GovernedField[] Governed =
    [
        new(Guid.Parse("d2b00007-0000-0000-0000-000000000007"), "newsArticle", "newsCategory", "category"),
        new(Guid.Parse("d2b0000e-0000-0000-0000-00000000000e"), "newsArticle", "newsTags", "tag"),
        // platformName lives inside the gamePlatformLinks Block List JSON rather than as a
        // top-level property, so usage is detected by scanning that JSON. See ReadBlockListUsage.
        new(Guid.Parse("d2b0000d-0000-0000-0000-00000000000d"), "game", "gamePlatformLinks", "platform", InsideBlockList: true),
    ];

    private const int PageSize = 500;
    private const int MaxNamesInMessage = 5;

    private readonly IContentService _contentService;
    private readonly IContentTypeService _contentTypeService;
    private readonly ISyncEventService _syncEventService;
    private readonly ILogger<GovernedDropdownItemGuard> _logger;

    public GovernedDropdownItemGuard(
        IContentService contentService,
        IContentTypeService contentTypeService,
        ISyncEventService syncEventService,
        ILogger<GovernedDropdownItemGuard> logger)
    {
        _contentService = contentService;
        _contentTypeService = contentTypeService;
        _syncEventService = syncEventService;
        _logger = logger;
    }

    public void Handle(DataTypeSavingNotification notification)
    {
        // uSync's boot-time schema import saves DataTypes too. Let it through, otherwise a
        // deliberate repo-side removal would fail the import and the app would boot on stale schema.
        if (_syncEventService.IsPaused)
        {
            return;
        }

        foreach (IDataType dataType in notification.SavedEntities)
        {
            // A brand new DataType cannot have content pointing at it yet.
            if (dataType.HasIdentity is false)
            {
                continue;
            }

            GovernedField? governed = Governed.FirstOrDefault(g => g.DataTypeKey == dataType.Key);
            if (governed is null)
            {
                continue;
            }

            IReadOnlyCollection<string> newItems = ReadItems(dataType);
            if (newItems.Count == 0)
            {
                // Either the editor cleared every item, or we could not parse the config.
                // Falling through would flag every stored value, so only block when we are
                // confident: an empty list is only safe if nothing uses this DataType.
                _logger.LogDebug("No parsable items on data type {DataType}; checking usage anyway.", dataType.Name);
            }

            Dictionary<string, List<string>> inUse = FindUsage(governed);

            var missing = inUse
                .Where(kvp => newItems.Contains(kvp.Key, StringComparer.Ordinal) is false)
                .ToArray();

            if (missing.Length == 0)
            {
                continue;
            }

            var detail = string.Join("; ", missing.Select(m => $"\"{m.Key}\" — {Describe(m.Value)}"));

            _logger.LogWarning(
                "Blocked save of data type {DataType}: {Count} {Noun} value(s) still in use — {Detail}",
                dataType.Name, missing.Length, governed.Noun, detail);

            notification.CancelOperation(new EventMessage(
                $"{char.ToUpperInvariant(governed.Noun[0])}{governed.Noun[1..]} still in use",
                $"Cannot save: {detail}. Re-assign that content first, or add the value back. "
                + $"To rename a {governed.Noun}: add the new name, move the content over, then remove the old one.",
                EventMessageType.Error));

            return;
        }
    }

    /// <summary>Maps each stored value to the names of the content items using it.</summary>
    private Dictionary<string, List<string>> FindUsage(GovernedField governed)
    {
        var usage = new Dictionary<string, List<string>>(StringComparer.Ordinal);

        IContentType? contentType = _contentTypeService.Get(governed.ContentTypeAlias);
        if (contentType is null)
        {
            return usage;
        }

        long page = 0;
        long total;
        do
        {
            IEnumerable<IContent> batch = _contentService
                .GetPagedOfType(contentType.Id, page, PageSize, out total, filter: null);

            foreach (IContent content in batch)
            {
                if (content.Trashed)
                {
                    continue;
                }

                // Check the draft and the published value — an unpublished edit still counts as in use.
                foreach (var raw in new[]
                         {
                             content.GetValue<string>(governed.PropertyAlias),
                             content.GetValue<string>(governed.PropertyAlias, culture: null, segment: null, published: true),
                         })
                {
                    if (string.IsNullOrWhiteSpace(raw))
                    {
                        continue;
                    }

                    IEnumerable<string> values = governed.InsideBlockList
                        ? ReadBlockListUsage(raw)
                        : ReadStoredValues(raw);

                    foreach (var value in values)
                    {
                        if (usage.TryGetValue(value, out List<string>? names) is false)
                        {
                            usage[value] = names = [];
                        }

                        if (names.Contains(content.Name ?? string.Empty) is false)
                        {
                            names.Add(content.Name ?? $"#{content.Id}");
                        }
                    }
                }
            }

            page++;
        }
        while (page * PageSize < total);

        return usage;
    }

    /// <summary>
    /// Reads the item list off a saved DataType. The shape of <c>ConfigurationData["items"]</c>
    /// varies with the caller — the Management API hands over deserialised CLR collections,
    /// uSync hands over <see cref="JsonElement"/> — so this stays deliberately permissive.
    /// </summary>
    private static IReadOnlyCollection<string> ReadItems(IDataType dataType)
    {
        if (dataType.ConfigurationData.TryGetValue("items", out var raw) is false || raw is null)
        {
            return [];
        }

        return raw switch
        {
            IEnumerable<string> strings => strings.ToArray(),
            JsonElement { ValueKind: JsonValueKind.Array } element => element
                .EnumerateArray()
                .Select(FromJsonElement)
                .OfType<string>()
                .ToArray(),
            IEnumerable<object?> objects => objects
                .Select(FromObject)
                .OfType<string>()
                .ToArray(),
            _ => [],
        };
    }

    private static string? FromJsonElement(JsonElement element) => element.ValueKind switch
    {
        JsonValueKind.String => element.GetString(),
        // Older configurations stored { "value": "...", "sortOrder": n }.
        JsonValueKind.Object when element.TryGetProperty("value", out JsonElement value) => value.GetString(),
        _ => null,
    };

    private static string? FromObject(object? value) => value switch
    {
        null => null,
        string s => s,
        JsonElement element => FromJsonElement(element),
        _ => value.ToString(),
    };

    /// <summary>
    /// Dropdown values are stored as a JSON array — <c>["Events"]</c> even for single-select —
    /// but tolerate a bare string in case anything wrote one.
    /// </summary>
    private static IEnumerable<string> ReadStoredValues(string raw)
    {
        raw = raw.Trim();

        if (raw.StartsWith('[') is false)
        {
            return string.IsNullOrWhiteSpace(raw) ? [] : [raw];
        }

        try
        {
            return JsonSerializer.Deserialize<string[]>(raw) ?? [];
        }
        catch (JsonException)
        {
            return [raw];
        }
    }

    /// <summary>
    /// Pulls every <c>platformName</c> value out of a Block List payload. This is a text scan
    /// rather than a full Block List deserialisation — adequate at this content volume, and it
    /// cannot produce a false negative, only a false positive on a value that appears verbatim
    /// in another platformName-shaped field.
    /// </summary>
    private static IEnumerable<string> ReadBlockListUsage(string raw)
    {
        foreach (Match match in PlatformNameValue().Matches(raw))
        {
            var escaped = match.Groups["value"].Value;

            // The inner value is a JSON string containing JSON: "[\"Steam\"]".
            string? inner;
            try
            {
                inner = JsonSerializer.Deserialize<string>($"\"{escaped}\"");
            }
            catch (JsonException)
            {
                continue;
            }

            if (string.IsNullOrWhiteSpace(inner))
            {
                continue;
            }

            foreach (var value in ReadStoredValues(inner))
            {
                yield return value;
            }
        }
    }

    private static string Describe(List<string> names)
    {
        var shown = string.Join(", ", names.Take(MaxNamesInMessage));
        var extra = names.Count - MaxNamesInMessage;

        return extra > 0
            ? $"used by {shown} and {extra} more"
            : $"used by {shown}";
    }

    [GeneratedRegex("""
        "alias"\s*:\s*"platformName"\s*,\s*"value"\s*:\s*"(?<value>(?:\\.|[^"\\])*)"
        """, RegexOptions.IgnorePatternWhitespace | RegexOptions.Compiled)]
    private static partial Regex PlatformNameValue();
}
