using System.Text.Json;
using Umbraco.Cms.Core.DeliveryApi;
using Umbraco.Cms.Core.Models;

namespace MooFamily.Cms.Web.DeliveryApi;

/// <summary>
/// Adds the properties in <see cref="QueryablePropertyRegistry"/> to the Delivery API's Examine
/// index so they can be filtered and sorted on.
///
/// Discovered automatically — <see cref="IContentIndexHandler"/> is <c>IDiscoverable</c>, so
/// AddDeliveryApi() picks this up by type scan. Requires an index rebuild to take effect on
/// content that is already indexed.
/// </summary>
public sealed class ContentPropertyIndexHandler : IContentIndexHandler
{
    public IEnumerable<IndexField> GetFields() =>
        QueryablePropertyRegistry.All.Select(property => new IndexField
        {
            FieldName = property.Alias,
            FieldType = property.FieldType,
            VariesByCulture = false,
        });

    public IEnumerable<IndexFieldValue> GetFieldValues(IContent content, string? culture)
    {
        foreach (QueryableProperty property in QueryablePropertyRegistry.All)
        {
            // Not every property is on every content type — games have no newsCategory.
            if (content.HasProperty(property.Alias) is false)
            {
                continue;
            }

            object[] values = property.StoredAs switch
            {
                StoredAs.Date => ReadDate(content, property.Alias, culture),
                StoredAs.Boolean => ReadBoolean(content, property.Alias, culture),
                StoredAs.JsonStringArray => ReadStringArray(content, property.Alias, culture),
                _ => [],
            };

            if (values.Length == 0)
            {
                continue;
            }

            yield return new IndexFieldValue
            {
                FieldName = property.Alias,
                Values = values,
            };
        }
    }

    private static object[] ReadDate(IContent content, string alias, string? culture)
    {
        DateTime? value = Read<DateTime?>(content, alias, culture);

        return value.HasValue ? [value.Value] : [];
    }

    /// <summary>
    /// Umbraco.TrueFalse persists "1"/"0", but the documented query is
    /// <c>?filter=gameIsFeatured:true</c>, so index the word rather than the digit.
    /// </summary>
    private static object[] ReadBoolean(IContent content, string alias, string? culture)
    {
        var raw = Read<string>(content, alias, culture)?.Trim();

        var isTrue = raw is "1" or "true" or "True";

        return [isTrue ? "true" : "false"];
    }

    private static object[] ReadStringArray(IContent content, string alias, string? culture)
    {
        var raw = Read<string>(content, alias, culture);
        if (string.IsNullOrWhiteSpace(raw))
        {
            return [];
        }

        raw = raw.Trim();

        // Dropdowns store a JSON array even when single-select: ["Stories & Learning"].
        if (raw.StartsWith('[') is false)
        {
            return [raw];
        }

        try
        {
            var parsed = JsonSerializer.Deserialize<string[]>(raw);

            return parsed is null
                ? []
                : parsed.Where(v => string.IsNullOrWhiteSpace(v) is false).Cast<object>().ToArray();
        }
        catch (JsonException)
        {
            return [raw];
        }
    }

    /// <summary>Prefers the published value, falling back to the draft.</summary>
    private static T? Read<T>(IContent content, string alias, string? culture)
    {
        var published = content.GetValue<T>(alias, culture, segment: null, published: true);

        return published is null || (published is string s && string.IsNullOrWhiteSpace(s))
            ? content.GetValue<T>(alias, culture)
            : published;
    }
}
