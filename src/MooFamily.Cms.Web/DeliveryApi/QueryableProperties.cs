using Umbraco.Cms.Core.DeliveryApi;

namespace MooFamily.Cms.Web.DeliveryApi;

/// <summary>How a property's raw database value should be turned into index values.</summary>
internal enum StoredAs
{
    /// <summary>A JSON array of strings, e.g. <c>["Stories &amp; Learning"]</c> — how every
    /// <c>Umbraco.DropDown.Flexible</c> property is stored, single- or multi-select.</summary>
    JsonStringArray,

    /// <summary>A date/time value.</summary>
    Date,

    /// <summary>An <c>Umbraco.TrueFalse</c> value, stored as <c>"1"</c> / <c>"0"</c> but
    /// indexed and queried as <c>true</c> / <c>false</c> so the documented
    /// <c>?filter=gameIsFeatured:true</c> works.</summary>
    Boolean,
}

internal sealed record QueryableProperty(
    string Alias,
    FieldType FieldType,
    StoredAs StoredAs,
    bool Filterable,
    bool Sortable);

/// <summary>
/// The single source of truth for which custom properties the Delivery API can query.
///
/// Out of the box the Delivery API only filters on <c>contentType</c>, <c>name</c>,
/// <c>createDate</c> and <c>updateDate</c>, and only sorts on those plus <c>level</c> and
/// <c>sortOrder</c>. Anything else returns HTTP 400. Exposing a property here indexes it
/// (<see cref="ContentPropertyIndexHandler"/>) and enables
/// <c>?filter=alias:value</c> / <c>&amp;sort=alias:asc</c>
/// (<see cref="PropertyFilterHandler"/>, <see cref="PropertySortHandler"/>).
///
/// Adding a property here requires an Examine index rebuild before it returns results.
/// </summary>
internal static class QueryablePropertyRegistry
{
    public static readonly IReadOnlyList<QueryableProperty> All =
    [
        // News listing: category filter chips and the sidebar category counts.
        new("newsCategory", FieldType.StringRaw, StoredAs.JsonStringArray, Filterable: true, Sortable: false),

        // News listing: card badges and the sidebar hashtag cloud.
        new("newsTags", FieldType.StringRaw, StoredAs.JsonStringArray, Filterable: true, Sortable: false),

        // News listing and "Latest Articles": newest first.
        new("newsPublishedDate", FieldType.Date, StoredAs.Date, Filterable: false, Sortable: true),

        // Games listing: platform facets. Note this is the flat taxonomy field, not the
        // gamePlatformLinks Block List — a Block List cannot be indexed as a facet.
        new("gamePlatforms", FieldType.StringRaw, StoredAs.JsonStringArray, Filterable: true, Sortable: false),
        new("gameStatus", FieldType.StringRaw, StoredAs.JsonStringArray, Filterable: true, Sortable: false),
        new("gameGenre", FieldType.StringRaw, StoredAs.JsonStringArray, Filterable: true, Sortable: false),

        // Home page "Trending games".
        new("gameIsFeatured", FieldType.StringRaw, StoredAs.Boolean, Filterable: true, Sortable: false),

        // Stories and Shorts carousels, Characters grid, Educational Games grid — all driven by
        // entityCarouselSection / entityGridSection's "<entityType>Category" convention.
        new("storyCategory", FieldType.StringRaw, StoredAs.JsonStringArray, Filterable: true, Sortable: false),
        new("storyTags", FieldType.StringRaw, StoredAs.JsonStringArray, Filterable: true, Sortable: false),
        new("shortCategory", FieldType.StringRaw, StoredAs.JsonStringArray, Filterable: true, Sortable: false),
        new("characterCategory", FieldType.StringRaw, StoredAs.JsonStringArray, Filterable: true, Sortable: false),
        new("eduGameCategory", FieldType.StringRaw, StoredAs.JsonStringArray, Filterable: true, Sortable: false),
    ];

    public static QueryableProperty? Filterable(string alias) =>
        All.FirstOrDefault(p => p.Filterable && p.Alias.Equals(alias, StringComparison.OrdinalIgnoreCase));

    public static QueryableProperty? Sortable(string alias) =>
        All.FirstOrDefault(p => p.Sortable && p.Alias.Equals(alias, StringComparison.OrdinalIgnoreCase));
}
