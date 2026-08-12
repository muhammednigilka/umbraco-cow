using MooFamily.Cms.Web.Notifications;
using Umbraco.Cms.Core.Composing;
using Umbraco.Cms.Core.DependencyInjection;
using Umbraco.Cms.Core.Notifications;

namespace MooFamily.Cms.Web.Composers;

/// <summary>
/// Wires up content governance rules.
///
/// The Delivery API index/filter/sort handlers in <c>MooFamily.Cms.Web.DeliveryApi</c> are not
/// registered here — they implement <c>IDiscoverable</c>, so AddDeliveryApi() finds them by
/// type scan. Registering them explicitly as well would add them to the collections twice.
/// </summary>
public class ContentGovernanceComposer : IComposer
{
    public void Compose(IUmbracoBuilder builder) =>
        builder.AddNotificationHandler<DataTypeSavingNotification, GovernedDropdownItemGuard>();
}
