using Microsoft.Extensions.DependencyInjection;
using OpenIddict.Server.AspNetCore;
using Umbraco.Cms.Core.Composing;
using Umbraco.Cms.Core.DependencyInjection;

namespace MooFamily.Cms.Web.Composers;

public class AllowHttpForOpenIddictComposer : IComposer
{
    public void Compose(IUmbracoBuilder builder)
    {
        builder.Services.PostConfigure<OpenIddictServerAspNetCoreOptions>(options =>
        {
            options.DisableTransportSecurityRequirement = true;
        });
    }
}
