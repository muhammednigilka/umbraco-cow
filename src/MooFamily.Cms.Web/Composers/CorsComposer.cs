using Microsoft.Extensions.DependencyInjection;
using Umbraco.Cms.Core.Composing;
using Umbraco.Cms.Core.DependencyInjection;

namespace MooFamily.Cms.Web.Composers;

public class CorsComposer : IComposer
{
    public const string PolicyName = "DeliveryApiCors";

    public void Compose(IUmbracoBuilder builder)
    {
        builder.Services.AddCors(options =>
        {
            options.AddPolicy(PolicyName, policy =>
            {
                var origins = builder.Config["Cors:AllowedOrigins"]?.Split(',')
                              ?? new[] { "http://localhost:3000" };
                policy.WithOrigins(origins)
                      .AllowAnyHeader()
                      .WithMethods("GET", "OPTIONS")
                      .WithExposedHeaders("Total-Count");
            });
        });
    }
}
