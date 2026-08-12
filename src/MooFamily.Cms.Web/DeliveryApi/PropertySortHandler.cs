using Umbraco.Cms.Core;
using Umbraco.Cms.Core.DeliveryApi;

namespace MooFamily.Cms.Web.DeliveryApi;

/// <summary>
/// Enables <c>&amp;sort=alias:asc|desc</c> for the properties in
/// <see cref="QueryablePropertyRegistry"/> — currently <c>newsPublishedDate</c>, which the news
/// listing and the "Latest Articles" sidebar both order by.
///
/// Matches the direction keywords Umbraco's built-in sort handlers accept
/// (<c>asc</c>/<c>ascending</c>, <c>desc</c>/<c>descending</c>).
/// Discovered automatically via <c>IDiscoverable</c>.
/// </summary>
public sealed class PropertySortHandler : ISortHandler
{
    public bool CanHandle(string query) => Parse(query) is not null;

    public SortOption BuildSortOption(string sort)
    {
        (QueryableProperty Property, Direction Direction)? parsed = Parse(sort);

        if (parsed is null)
        {
            throw new ArgumentException($"Cannot build a sort option from \"{sort}\".", nameof(sort));
        }

        return new SortOption
        {
            FieldName = parsed.Value.Property.Alias,
            Direction = parsed.Value.Direction,
        };
    }

    private static (QueryableProperty Property, Direction Direction)? Parse(string query)
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

        QueryableProperty? property = QueryablePropertyRegistry.Sortable(query[..separator]);
        if (property is null)
        {
            return null;
        }

        Direction? direction = query[(separator + 1)..].Trim().ToLowerInvariant() switch
        {
            "asc" or "ascending" => Direction.Ascending,
            "desc" or "descending" => Direction.Descending,
            _ => null,
        };

        return direction is null ? null : (property, direction.Value);
    }
}
