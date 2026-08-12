using Umbraco.Cms.Core.DeliveryApi;

namespace MooFamily.Cms.Web.DeliveryApi;

/// <summary>
/// Enables <c>?filter=alias:value</c> for the properties in <see cref="QueryablePropertyRegistry"/>.
///
/// Supported syntax:
/// <list type="bullet">
///   <item><c>newsCategory:Events</c> — equals</item>
///   <item><c>newsCategory:!Events</c> — not equals</item>
///   <item><c>newsTags:Education,Music</c> — matches any of (OR)</item>
/// </list>
///
/// Values containing a comma cannot be expressed; none of the current vocabularies use one.
/// Discovered automatically via <c>IDiscoverable</c>.
/// </summary>
public sealed class PropertyFilterHandler : IFilterHandler
{
    public bool CanHandle(string query) => Parse(query) is not null;

    public FilterOption BuildFilterOption(string filter)
    {
        (QueryableProperty Property, FilterOperation Operator, string[] Values)? parsed = Parse(filter);

        if (parsed is null)
        {
            // CanHandle gates this, so reaching here means the query changed underneath us.
            throw new ArgumentException($"Cannot build a filter option from \"{filter}\".", nameof(filter));
        }

        return new FilterOption
        {
            FieldName = parsed.Value.Property.Alias,
            Values = parsed.Value.Values,
            Operator = parsed.Value.Operator,
        };
    }

    private static (QueryableProperty Property, FilterOperation Operator, string[] Values)? Parse(string query)
    {
        if (string.IsNullOrWhiteSpace(query))
        {
            return null;
        }

        var separator = query.IndexOf(':');
        if (separator <= 0 || separator == query.Length - 1)
        {
            return null;
        }

        QueryableProperty? property = QueryablePropertyRegistry.Filterable(query[..separator]);
        if (property is null)
        {
            return null;
        }

        var raw = query[(separator + 1)..];
        var negated = raw.StartsWith('!');
        if (negated)
        {
            raw = raw[1..];
        }

        var values = raw
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(v => property.StoredAs == StoredAs.Boolean ? Normalise(v) : v)
            .ToArray();

        return values.Length == 0
            ? null
            : (property, negated ? FilterOperation.IsNot : FilterOperation.Is, values);
    }

    /// <summary>Accept 1/0 and yes/no as well as true/false for boolean fields.</summary>
    private static string Normalise(string value) => value.ToLowerInvariant() switch
    {
        "1" or "true" or "yes" => "true",
        "0" or "false" or "no" => "false",
        _ => value,
    };
}
