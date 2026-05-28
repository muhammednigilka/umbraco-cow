using Microsoft.Data.Sqlite;
using MooFamily.Cms.Web.Composers;

var existingConn = Environment.GetEnvironmentVariable("ConnectionStrings__umbracoDbDSN");
var isProduction = string.Equals(
    Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT"),
    "Production",
    StringComparison.OrdinalIgnoreCase);
var useSqliteBootstrap = !isProduction && string.IsNullOrWhiteSpace(existingConn);

if (useSqliteBootstrap)
{
    var contentRoot = Directory.GetCurrentDirectory();
    if (!File.Exists(Path.Combine(contentRoot, "MooFamily.Cms.Web.csproj")))
    {
        contentRoot = AppContext.BaseDirectory;
        while (contentRoot is not null && !File.Exists(Path.Combine(contentRoot, "MooFamily.Cms.Web.csproj")))
        {
            contentRoot = Directory.GetParent(contentRoot)?.FullName;
        }
        contentRoot ??= Directory.GetCurrentDirectory();
    }

    var dataDir = Path.Combine(contentRoot, "umbraco", "Data");
    Directory.CreateDirectory(dataDir);
    AppDomain.CurrentDomain.SetData("DataDirectory", dataDir);

    var dbPath = Path.Combine(dataDir, "Umbraco.sqlite.db").Replace('\\', '/');
    var sqliteConn = $"Data Source={dbPath};Cache=Shared;Mode=ReadWriteCreate;Foreign Keys=True;Pooling=True";

    Console.WriteLine($"[STARTUP] ContentRoot:  {contentRoot}");
    Console.WriteLine($"[STARTUP] DataDir:      {dataDir}  (exists={Directory.Exists(dataDir)})");
    Console.WriteLine($"[STARTUP] DbPath:       {dbPath}");
    Console.WriteLine($"[STARTUP] DbFileExists: {File.Exists(dbPath)} (before pre-create)");

    try
    {
        using var probe = new SqliteConnection(sqliteConn);
        probe.Open();
        probe.Close();
        Console.WriteLine($"[STARTUP] Pre-create OK. DbFileExists: {File.Exists(dbPath)}");
    }
    catch (Exception ex)
    {
        Console.WriteLine($"[STARTUP] PRE-CREATE FAILED: {ex.GetType().Name}: {ex.Message}");
        throw;
    }

    Environment.SetEnvironmentVariable("ConnectionStrings__umbracoDbDSN", sqliteConn);
    Environment.SetEnvironmentVariable("ConnectionStrings__umbracoDbDSN_ProviderName", "Microsoft.Data.Sqlite");
}
else
{
    Console.WriteLine("[STARTUP] Using DB connection from environment / configuration (Production mode).");
}

WebApplicationBuilder builder = WebApplication.CreateBuilder(args);

if (useSqliteBootstrap)
{
    var sqliteConn = Environment.GetEnvironmentVariable("ConnectionStrings__umbracoDbDSN")!;
    builder.Configuration["ConnectionStrings:umbracoDbDSN"] = sqliteConn;
    builder.Configuration["ConnectionStrings:umbracoDbDSN_ProviderName"] = "Microsoft.Data.Sqlite";
}

Console.WriteLine($"[STARTUP] Config-resolved umbracoDbDSN provider: {builder.Configuration["ConnectionStrings:umbracoDbDSN_ProviderName"]}");

builder.CreateUmbracoBuilder()
    .AddBackOffice()
    .AddWebsite()
    .AddDeliveryApi()
    .AddComposers()
    .Build();

WebApplication app = builder.Build();

await app.BootUmbracoAsync();

app.UseCors(CorsComposer.PolicyName);

app.UseUmbraco()
    .WithMiddleware(u =>
    {
        u.UseBackOffice();
        u.UseWebsite();
    })
    .WithEndpoints(u =>
    {
        u.UseBackOfficeEndpoints();
        u.UseWebsiteEndpoints();
    });

app.MapWhen(ctx => ctx.Request.Path.StartsWithSegments("/umbraco/delivery/api"),
    apiApp => apiApp.UseCors(CorsComposer.PolicyName));

await app.RunAsync();
