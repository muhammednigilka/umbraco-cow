using Umbraco.Cms.Core.Composing;
using Umbraco.Cms.Core.DependencyInjection;
using Umbraco.Cms.Infrastructure.Runtime.RuntimeModeValidators;

namespace MooFamily.Cms.Web.Composers;

public class DisableHttpsValidatorComposer : IComposer
{
    public void Compose(IUmbracoBuilder builder) =>
        builder.RuntimeModeValidators().Remove<UseHttpsValidator>();
}
