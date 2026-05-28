# syntax=docker/dockerfile:1.7
# Build stage
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY src/MooFamily.Cms.Web/MooFamily.Cms.Web.csproj src/MooFamily.Cms.Web/
COPY src/MooFamily.Cms.Web/Directory.Packages.props src/MooFamily.Cms.Web/
RUN dotnet restore src/MooFamily.Cms.Web/MooFamily.Cms.Web.csproj

COPY src/MooFamily.Cms.Web/ src/MooFamily.Cms.Web/

RUN dotnet publish src/MooFamily.Cms.Web/MooFamily.Cms.Web.csproj \
    -c Release \
    -o /app/publish \
    --no-restore \
    /p:UseAppHost=false

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

ENV ASPNETCORE_ENVIRONMENT=Production \
    ASPNETCORE_URLS=http://+:5000 \
    DOTNET_RUNNING_IN_CONTAINER=true \
    DOTNET_USE_POLLING_FILE_WATCHER=true

COPY --from=build /app/publish/ ./

# uSync ships content with the container. The published output should already include
# the uSync v17 XML under uSync/v17/, but copy explicitly in case publish skipped it.
COPY src/MooFamily.Cms.Web/uSync/ ./uSync/

EXPOSE 5000

ENTRYPOINT ["dotnet", "MooFamily.Cms.Web.dll"]
