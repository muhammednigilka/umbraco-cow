# Moo Family CMS — Implementation Guide

> **Audience:** Claude Code (or any developer/AI assistant) picking this up in VS Code to build and deploy.
> Self-contained. Do not assume external context. Follow phases in order.

**Last updated:** 2026-05-16
**Status:** Ready for Phase 1
**Target public site:** https://master.d3boy6qi81n9oz.amplifyapp.com/ (React SPA on AWS Amplify — stays where it is)

---

## 0. Quick Reference

### What we're building
A self-hosted **Umbraco 17** CMS on AWS that feeds content (pages, images, YouTube embeds, Play Store links) to an existing React site via Umbraco's built-in **Content Delivery API**. Editors manage content in the Umbraco backoffice; the React site fetches JSON over HTTPS.

### Final topology (locked)
```
your-domain.com           → AWS Amplify          (React site, UNCHANGED)
cms.your-domain.com       → AWS App Runner       (Umbraco backoffice + Delivery API)
media.your-domain.com     → existing CloudFront + S3  (Umbraco media uploads)

Backing services:
  - Amazon RDS for SQL Server Express (private subnets)
  - AWS Secrets Manager (DB conn, API keys)
  - Amazon ECR (container registry)
  - Amazon CloudWatch (logs + alarms)
  - Amazon Route 53 (DNS)
  - AWS Certificate Manager (ACM, us-east-1)
```

### Stack (decisions locked — do not re-litigate)
| Layer | Choice |
|---|---|
| CMS | Umbraco 17 LTS (MIT licensed) |
| Runtime | .NET 10 |
| Database | SQL Server Express (RDS) — chosen because Umbraco officially supports SQL Server; SQLite for local dev only |
| Media storage | Existing S3 bucket via `Umbraco.Storage.S3` package |
| Compute | AWS App Runner running Docker container |
| Public hosting | AWS Amplify (unchanged) |
| CI/CD | GitHub Actions → ECR → App Runner auto-deploy |
| Region | us-east-1 |
| Local dev | Docker Compose, SQLite |
| IDE | Visual Studio Code |

### Glossary
- **Backoffice** — Umbraco's admin UI at `/umbraco`.
- **Delivery API** — Umbraco's built-in headless JSON API at `/umbraco/delivery/api/v2/...`.
- **Document Type** — Umbraco's term for a content schema (e.g. "StandardPage").
- **Element Type** — like a Document Type but used inside a Block List (i.e. each "block" is an Element Type).
- **Block List Editor** — drag-and-drop list of blocks on a page.
- **uSync** — Umbraco package that source-controls content types in Git.

---

## 1. Project Context (For Anyone Picking This Up)

**Why Umbraco:** chosen after evaluating LeadCMS, Strapi, and a custom-built Blazor CMS. Umbraco won because it's mature (20+ years, ~700k production sites), MIT-licensed, has a polished editor UI out of the box, ships with a built-in headless API, and has an official AWS S3 storage provider.

**Why this architecture:**
- **App Runner over ECS Fargate** — managed, no cluster ops, deploys from ECR on push.
- **SQL Server Express over PostgreSQL** — Umbraco officially supports SQL Server; PostgreSQL support is community-only and brand new (Umbraco 17.3, April 2026).
- **Re-use existing S3+CloudFront for media** — minimizes new infrastructure. The bucket was originally provisioned for static React hosting but is being repurposed for Umbraco media instead.
- **React site stays on Amplify** — zero risk to the live site during CMS build-out. Retiring Amplify is a separate later project, not part of this scope.

**Out of scope for this build:**
- Retiring Amplify (defer)
- Multilingual content (no immediate need)
- Page revision history (Umbraco has built-in versioning, not extending it)
- Custom Umbraco backoffice extensions

---

## 2. Phase Roadmap

| Phase | Goal | Time | Depends on |
|---|---|---|---|
| 1 | Local Umbraco project running with SQLite | 1–2 hr | — |
| 2 | Content model (Document Types + Block element types) defined | 2–4 hr | Phase 1 |
| 3 | Delivery API returning expected JSON | 1 hr | Phase 2 |
| 4 | AWS infrastructure provisioned (VPC, RDS, ECR, IAM, Secrets) | 3–5 hr | — |
| 5 | Dockerfile + image pushed to ECR | 1–2 hr | Phase 1, 4 |
| 6 | App Runner service live at `cms.your-domain.com` | 1–2 hr | Phase 4, 5 |
| 7 | CI/CD pipeline (GitHub Actions) | 1 hr | Phase 6 |
| 8 | Content migration: copy existing pages into Umbraco | 1 day | Phase 6 |
| 9 | React integration (`<BlockRenderer />`, feature-flagged) | 1–2 days | Phase 8 |
| 10 | Hardening (alarms, WAF, uSync committed) | half day | Phase 9 |

Work Phases 1–3 fully locally before touching AWS. Don't pay for cloud while modeling content.

---

## 3. Prerequisites

### Required locally
- .NET 10 SDK (for Umbraco 17)
- Docker Desktop
- Git
- VS Code with **C# Dev Kit** extension
- AWS CLI v2 (for Phase 4+)

### Required accounts / access
- AWS account with admin access (initial setup) and billing alerts enabled
- GitHub account + repo for the CMS project
- A domain name with Route 53 hosted zone (or willingness to delegate one)

### Information to gather before Phase 4
- [ ] Production domain name (e.g. `moofamily.com`)
- [ ] AWS account ID
- [ ] AWS region (default `us-east-1`)
- [ ] Existing S3 bucket name (for media)
- [ ] Existing CloudFront distribution ID (for media)
- [ ] GitHub repo URL

Fill these into `.env.example` (see Appendix A) before starting Phase 4.

---

## 4. Phase 1 — Local Umbraco Project

**Goal:** Umbraco 17 backoffice running at `localhost:5000` with SQLite, ready for content modeling.

### Steps

```bash
# 1. Install the Umbraco templates (one-time per machine)
dotnet new install Umbraco.Templates

# 2. Create the project
mkdir MooFamily.Cms && cd MooFamily.Cms
dotnet new sln -n MooFamily.Cms
mkdir -p src
dotnet new umbraco -n MooFamily.Cms.Web --use-delivery-api -o src/MooFamily.Cms.Web
dotnet sln add src/MooFamily.Cms.Web/MooFamily.Cms.Web.csproj

# 3. Add required NuGet packages
cd src/MooFamily.Cms.Web
dotnet add package Umbraco.StorageProviders.AWSS3
dotnet add package Serilog.Sinks.AwsCloudWatch
dotnet add package Microsoft.Data.Sqlite
cd ../..

# 4. Initialize git
git init
# create .gitignore (see Appendix C)

# 5. Run it
cd src/MooFamily.Cms.Web
dotnet run
```

Open `http://localhost:5000`, complete the unattended install prompts (creates an admin user), and confirm you can log into the backoffice at `http://localhost:5000/umbraco`.

### Files to create

Create these files exactly as specified. Code blocks are complete.

**`src/MooFamily.Cms.Web/Composers/DisableHttpsValidatorComposer.cs`** — required for running behind App Runner's SSL-terminating proxy:

```csharp
using Umbraco.Cms.Core.Composing;
using Umbraco.Cms.Core.DependencyInjection;
using Umbraco.Cms.Infrastructure.Runtime.RuntimeModeValidators;

namespace MooFamily.Cms.Web.Composers;

public class DisableHttpsValidatorComposer : IComposer
{
    public void Compose(IUmbracoBuilder builder) =>
        builder.RuntimeModeValidators().Remove<UseHttpsValidator>();
}
```

**`src/MooFamily.Cms.Web/Composers/CorsComposer.cs`** — allows the React site to call the Delivery API:

```csharp
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
```

**`src/MooFamily.Cms.Web/Program.cs`** — replace generated file. Key additions: `AddDeliveryApi()`, S3 storage, CORS, CloudWatch logging:

```csharp
using MooFamily.Cms.Web.Composers;
using Umbraco.StorageProviders.AWSS3.DependencyInjection;

WebApplicationBuilder builder = WebApplication.CreateBuilder(args);

builder.CreateUmbracoBuilder()
    .AddBackOffice()
    .AddWebsite()
    .AddDeliveryApi()
    .AddAWSS3MediaFileSystem()
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
        u.UseInstallerEndpoints();
        u.UseBackOfficeEndpoints();
        u.UseWebsiteEndpoints();
    });

// Apply CORS specifically to Delivery API endpoints
app.MapWhen(ctx => ctx.Request.Path.StartsWithSegments("/umbraco/delivery/api"),
    apiApp => apiApp.UseCors(CorsComposer.PolicyName));

await app.RunAsync();
```

**`src/MooFamily.Cms.Web/appsettings.json`** — base config. Replace the generated file:

```json
{
  "$schema": "appsettings-schema.json",
  "Serilog": {
    "MinimumLevel": {
      "Default": "Information",
      "Override": {
        "Microsoft": "Warning",
        "Microsoft.Hosting.Lifetime": "Information"
      }
    }
  },
  "Umbraco": {
    "CMS": {
      "Global": {
        "Id": "",
        "SanitizeTinyMce": true
      },
      "Content": {
        "AllowEditInvariantFromNonDefault": true
      },
      "DeliveryApi": {
        "Enabled": true,
        "PublicAccess": false,
        "ApiKey": "",
        "AllowedContentTypeAliases": ["home", "standardPage", "settings"],
        "Media": {
          "Enabled": true,
          "PublicAccess": true
        }
      },
      "Hosting": {
        "Debug": false
      },
      "RuntimeMinification": {
        "UseInMemoryCache": true,
        "CacheBuster": "AppDomain"
      },
      "Storage": {
        "AWSS3": {
          "Media": {
            "BucketName": "",
            "Region": "us-east-1",
            "BucketHostName": ""
          }
        }
      },
      "Unattended": {
        "InstallUnattended": false
      }
    }
  },
  "ConnectionStrings": {
    "umbracoDbDSN": "Data Source=|DataDirectory|/Umbraco.sqlite.db;Cache=Shared;Foreign Keys=True;Pooling=True",
    "umbracoDbDSN_ProviderName": "Microsoft.Data.Sqlite"
  },
  "Cors": {
    "AllowedOrigins": "http://localhost:3000,http://localhost:5173"
  }
}
```

**`src/MooFamily.Cms.Web/appsettings.Production.json`** — overrides for AWS:

```json
{
  "Umbraco": {
    "CMS": {
      "Hosting": {
        "Debug": false
      }
    }
  }
}
```

### Validation
- [ ] `dotnet run` succeeds with no errors.
- [ ] `http://localhost:5000/umbraco` loads the install screen.
- [ ] Install completes, you can log in.
- [ ] Visiting `http://localhost:5000/umbraco/swagger` shows the Delivery API endpoints (in Development mode).

### Common issues
- **"SDK 10.0 not found"** — install .NET 10 SDK from https://dotnet.microsoft.com/download. Older Umbraco templates won't install correctly with mismatched SDKs.
- **Backoffice 404** — make sure `AddBackOffice()` is in `Program.cs` before `Build()`.
- **CORS errors in tests** — Delivery API CORS only applies to `/umbraco/delivery/api/*` paths, not `/umbraco`. That's intentional.

---

## 5. Phase 2 — Content Model

**Goal:** Define Document Types and Block element types in the Umbraco backoffice. These are the schemas your editors will use.

### Document Types (in `Settings → Document Types`)

#### 1. Home (single-instance, allowed at root)
- **Alias:** `home`
- **Allowed at root:** Yes
- **Allow as child:** No
- **Properties:**
  | Name | Alias | Editor | Notes |
  |---|---|---|---|
  | Title | `title` | Textstring | Required |
  | Meta Description | `metaDescription` | Textarea | SEO |
  | Hero Image | `heroImage` | Media Picker (single, images only) | Optional |
  | Blocks | `blocks` | Block List | Allowed blocks: all six element types from below |

#### 2. Standard Page (children of Home)
- **Alias:** `standardPage`
- **Allowed at root:** No
- **Allow as child of:** Home
- **Properties:**
  | Name | Alias | Editor | Notes |
  |---|---|---|---|
  | Title | `title` | Textstring | Required |
  | URL Segment | (auto) | — | From Title |
  | Meta Description | `metaDescription` | Textarea | SEO |
  | Blocks | `blocks` | Block List | Allowed blocks: all six element types |

#### 3. Settings (single-instance, allowed at root, hidden from menu)
- **Alias:** `settings`
- **Allowed at root:** Yes
- **Properties:**
  | Name | Alias | Editor | Notes |
  |---|---|---|---|
  | Site Name | `siteName` | Textstring | |
  | Footer Text | `footerText` | Rich Text Editor | |
  | Footer Links | `footerLinks` | Block List | Allowed blocks: `playStoreLinkBlock`, `ctaBlock` |
  | Social Links | `socialLinks` | Block List | Allowed blocks: `ctaBlock` |

### Block Element Types (in `Settings → Document Types`, mark each as "Element Type")

Element Types are used inside Block Lists. Mark the checkbox **"Element Type"** on each.

#### 1. Heading Block
- **Alias:** `headingBlock`
- **Properties:**
  | Name | Alias | Editor |
  |---|---|---|
  | Text | `text` | Textstring |
  | Level | `level` | Dropdown (single): h1, h2, h3, h4 (default h2) |

#### 2. Rich Text Block
- **Alias:** `richTextBlock`
- **Properties:**
  | Name | Alias | Editor |
  |---|---|---|
  | Content | `content` | Rich Text Editor (Tiptap) |

#### 3. Image Block
- **Alias:** `imageBlock`
- **Properties:**
  | Name | Alias | Editor |
  |---|---|---|
  | Image | `image` | Media Picker (single, images only) |
  | Alt Text | `altText` | Textstring |
  | Caption | `caption` | Textstring (optional) |
  | Alignment | `alignment` | Dropdown: left, center, right (default center) |

#### 4. YouTube Block
- **Alias:** `youtubeBlock`
- **Properties:**
  | Name | Alias | Editor |
  |---|---|---|
  | Video URL or ID | `videoUrl` | Textstring (the React side parses video ID out of full URLs) |
  | Caption | `caption` | Textstring (optional) |

#### 5. Play Store Block
- **Alias:** `playStoreBlock`
- **Properties:**
  | Name | Alias | Editor |
  |---|---|---|
  | Play Store URL | `playStoreUrl` | Textstring |
  | Label | `label` | Textstring (e.g. "Get the app") |
  | Show QR Code | `showQrCode` | True/False (default false) |

#### 6. CTA Block
- **Alias:** `ctaBlock`
- **Properties:**
  | Name | Alias | Editor |
  |---|---|---|
  | Label | `label` | Textstring |
  | URL | `url` | Textstring |
  | Style | `style` | Dropdown: primary, secondary, link (default primary) |
  | Open in New Tab | `openInNewTab` | True/False (default false) |

### Configure Block Lists on Home and Standard Page
On the `blocks` property (Block List editor) on both Home and Standard Page, add **all six element types** as allowed blocks. Set sensible labels for each so editors see useful names in the "+ Add content" picker.

### Validation
- [ ] All 3 Document Types and 6 Element Types exist with the exact aliases above.
- [ ] Create one Home node and one Standard Page node as children.
- [ ] On Standard Page, add one of each block type, fill them in, save & publish.
- [ ] On Settings node, configure footer text and one Play Store link.

### Commit content model with uSync (highly recommended)
After defining the model, install uSync to source-control it:

```bash
cd src/MooFamily.Cms.Web
dotnet add package uSync
```

Then in the backoffice: `Settings → uSync → Export` to write your content types to `/uSync/v9/`. Commit those files to Git. From now on, content type changes are diff-able and reproducible.

---

## 6. Phase 3 — Verify Delivery API

**Goal:** Confirm the API returns the JSON shape the React site needs.

### Enable Swagger in Development
With `ASPNETCORE_ENVIRONMENT=Development`, Swagger is auto-enabled at `/umbraco/swagger`.

### Manual tests

```bash
# All published content (sanity check)
curl http://localhost:5000/umbraco/delivery/api/v2/content | jq

# A specific page by URL path
curl "http://localhost:5000/umbraco/delivery/api/v2/content/item/about?expand=properties[\$all]" | jq

# Filter by content type
curl "http://localhost:5000/umbraco/delivery/api/v2/content?filter=contentType:standardPage&expand=properties[\$all]" | jq
```

### Expected response shape for a Standard Page

```json
{
  "contentType": "standardPage",
  "name": "About Us",
  "createDate": "2026-05-16T10:00:00",
  "updateDate": "2026-05-16T10:30:00",
  "route": {
    "path": "/about/",
    "startItem": { "id": "...", "path": "home" }
  },
  "id": "guid-here",
  "properties": {
    "title": "About Us",
    "metaDescription": "Learn about Moo Family",
    "blocks": {
      "items": [
        {
          "content": {
            "contentType": "headingBlock",
            "id": "...",
            "properties": { "text": "Welcome to the farm", "level": "h1" }
          }
        },
        {
          "content": {
            "contentType": "imageBlock",
            "id": "...",
            "properties": {
              "image": [{ "url": "https://media.your-domain.com/...", "width": 1600, "height": 900 }],
              "altText": "Holstein cow grazing",
              "alignment": "center"
            }
          }
        },
        {
          "content": {
            "contentType": "youtubeBlock",
            "id": "...",
            "properties": { "videoUrl": "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "caption": "Farm tour" }
          }
        }
      ]
    }
  }
}
```

### API key (when ready for production)
Set in `appsettings.json` → `Umbraco:CMS:DeliveryApi:ApiKey` (production reads from Secrets Manager). Clients send it via the `Api-Key` header.

### Validation
- [ ] All three curl tests above return non-empty JSON.
- [ ] A page with all 6 block types serializes correctly with `?expand=properties[$all]`.
- [ ] Media URLs in the response point to your CloudFront media domain (after Phase 4 wiring).

---

## 7. Phase 4 — AWS Infrastructure

**Goal:** Stand up VPC, RDS SQL Server, ECR, IAM, Secrets Manager, and ACM cert.

Run as AWS CLI commands so they're reproducible and copy-pasteable. After this phase you'll have the infrastructure ready to receive the container image.

### Environment variables (set these once per shell session)

```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export PROJECT=moofamily
export DOMAIN=your-domain.com               # ← REPLACE
export EXISTING_MEDIA_BUCKET=your-bucket    # ← REPLACE
export EXISTING_MEDIA_CF_DIST=E1234ABC      # ← REPLACE
```

### Step 1 — VPC and subnets

```bash
# Create VPC
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$PROJECT-vpc}]" \
  --query Vpc.VpcId --output text)

aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames

# Internet gateway
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$PROJECT-igw}]" \
  --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID

# Subnets (2 public, 2 private across 2 AZs)
PUB_A=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 \
  --availability-zone ${AWS_REGION}a \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$PROJECT-public-a}]" \
  --query Subnet.SubnetId --output text)
PUB_B=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 \
  --availability-zone ${AWS_REGION}b \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$PROJECT-public-b}]" \
  --query Subnet.SubnetId --output text)
PRIV_A=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.11.0/24 \
  --availability-zone ${AWS_REGION}a \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$PROJECT-private-a}]" \
  --query Subnet.SubnetId --output text)
PRIV_B=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.12.0/24 \
  --availability-zone ${AWS_REGION}b \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$PROJECT-private-b}]" \
  --query Subnet.SubnetId --output text)

# Public route table
PUB_RT=$(aws ec2 create-route-table --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$PROJECT-public-rt}]" \
  --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id $PUB_RT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
aws ec2 associate-route-table --route-table-id $PUB_RT --subnet-id $PUB_A
aws ec2 associate-route-table --route-table-id $PUB_RT --subnet-id $PUB_B

echo "VPC=$VPC_ID PUB_A=$PUB_A PUB_B=$PUB_B PRIV_A=$PRIV_A PRIV_B=$PRIV_B"
```

Save the output IDs — you'll need them.

### Step 2 — Security groups

```bash
# App Runner SG (will be attached to the VPC Connector later)
SG_APP=$(aws ec2 create-security-group --vpc-id $VPC_ID \
  --group-name $PROJECT-apprunner --description "App Runner VPC connector" \
  --query GroupId --output text)
aws ec2 authorize-security-group-egress --group-id $SG_APP \
  --protocol tcp --port 1433 --cidr 10.0.0.0/16

# RDS SG
SG_RDS=$(aws ec2 create-security-group --vpc-id $VPC_ID \
  --group-name $PROJECT-rds --description "RDS SQL Server" \
  --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id $SG_RDS \
  --protocol tcp --port 1433 --source-group $SG_APP

echo "SG_APP=$SG_APP SG_RDS=$SG_RDS"
```

### Step 3 — RDS SQL Server Express

```bash
# DB subnet group across private subnets
aws rds create-db-subnet-group \
  --db-subnet-group-name $PROJECT-db-subnet \
  --db-subnet-group-description "Private subnets for $PROJECT RDS" \
  --subnet-ids $PRIV_A $PRIV_B

# Generate and store the master password
DB_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
aws secretsmanager create-secret \
  --name $PROJECT/db/master-password \
  --secret-string "$DB_PASSWORD"

# Launch RDS
aws rds create-db-instance \
  --db-instance-identifier $PROJECT-umbraco \
  --db-instance-class db.t3.small \
  --engine sqlserver-ex \
  --engine-version 16.00 \
  --allocated-storage 20 \
  --storage-type gp3 \
  --storage-encrypted \
  --master-username admin \
  --master-user-password "$DB_PASSWORD" \
  --vpc-security-group-ids $SG_RDS \
  --db-subnet-group-name $PROJECT-db-subnet \
  --no-publicly-accessible \
  --backup-retention-period 7 \
  --license-model license-included
```

Wait ~15 min for RDS to become available, then capture the endpoint:

```bash
aws rds wait db-instance-available --db-instance-identifier $PROJECT-umbraco
RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier $PROJECT-umbraco \
  --query "DBInstances[0].Endpoint.Address" --output text)

# Build and store the connection string
CONN="Server=$RDS_ENDPOINT,1433;Database=umbraco;User Id=admin;Password=$DB_PASSWORD;TrustServerCertificate=True;Encrypt=True;"
aws secretsmanager create-secret \
  --name $PROJECT/umbraco/connection-string \
  --secret-string "$CONN"
```

### Step 4 — Create the Umbraco database
The Umbraco unattended installer will create tables, but the database itself must exist. Connect via a bastion or temporarily allow your IP to RDS, then:

```sql
CREATE DATABASE umbraco COLLATE SQL_Latin1_General_CP1_CI_AS;
```

Collation must be case-insensitive — Umbraco requires it.

### Step 5 — ECR repository

```bash
aws ecr create-repository --repository-name $PROJECT/umbraco \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=AES256
```

### Step 6 — IAM role for Umbraco to read/write the existing S3 bucket

```bash
# Trust policy for App Runner tasks
cat > /tmp/apprunner-trust.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "tasks.apprunner.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role --role-name $PROJECT-apprunner-task \
  --assume-role-policy-document file:///tmp/apprunner-trust.json

# Permissions: read existing S3 bucket, read secrets, write logs
cat > /tmp/apprunner-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::$EXISTING_MEDIA_BUCKET",
        "arn:aws:s3:::$EXISTING_MEDIA_BUCKET/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": "arn:aws:secretsmanager:$AWS_REGION:$AWS_ACCOUNT_ID:secret:$PROJECT/*"
    },
    {
      "Effect": "Allow",
      "Action": ["logs:CreateLogStream", "logs:PutLogEvents", "logs:CreateLogGroup"],
      "Resource": "*"
    }
  ]
}
EOF

aws iam put-role-policy --role-name $PROJECT-apprunner-task \
  --policy-name $PROJECT-apprunner-policy \
  --policy-document file:///tmp/apprunner-policy.json
```

### Step 7 — ACM certificate (in us-east-1, required for CloudFront)

```bash
CERT_ARN=$(aws acm request-certificate --region us-east-1 \
  --domain-name "*.$DOMAIN" \
  --subject-alternative-names "$DOMAIN" \
  --validation-method DNS \
  --query CertificateArn --output text)

# Get the DNS validation records
aws acm describe-certificate --certificate-arn $CERT_ARN --region us-east-1 \
  --query "Certificate.DomainValidationOptions[*].ResourceRecord"
```

Add the returned CNAME records to your Route 53 hosted zone (or wherever DNS is hosted). Wait for validation to complete (`aws acm wait certificate-validated --certificate-arn $CERT_ARN`).

### Step 8 — Delivery API key (generate and store)

```bash
DELIVERY_API_KEY=$(openssl rand -hex 32)
aws secretsmanager create-secret \
  --name $PROJECT/umbraco/delivery-api-key \
  --secret-string "$DELIVERY_API_KEY"

ADMIN_SEED_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 20)P!
aws secretsmanager create-secret \
  --name $PROJECT/umbraco/admin-seed-password \
  --secret-string "$ADMIN_SEED_PASSWORD"
```

### Step 9 — Configure the existing media bucket for Umbraco use
The bucket must be accessible to Umbraco (via IAM role) and to CloudFront (via OAC).

- Verify the bucket policy allows the App Runner IAM role to write.
- Verify CloudFront has an Origin Access Control (OAC) attached, and the bucket policy allows that OAC.
- Add a custom domain alias `media.$DOMAIN` to the CloudFront distribution, with the ACM cert from Step 7.
- Create a Route 53 alias record `media.$DOMAIN → <CloudFront distribution domain>`.

### Validation
- [ ] All commands above complete without errors.
- [ ] `aws rds describe-db-instances --db-instance-identifier $PROJECT-umbraco` shows `available`.
- [ ] `aws acm describe-certificate --certificate-arn $CERT_ARN` shows `ISSUED`.
- [ ] Secrets exist: connection-string, delivery-api-key, admin-seed-password.
- [ ] `media.$DOMAIN` resolves and serves a test object placed in the bucket.

---

## 8. Phase 5 — Containerization

**Goal:** Build a production Docker image and push it to ECR.

### Files to create

**`deploy/Dockerfile`** (at repo root):

```dockerfile
# Build stage
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY src/MooFamily.Cms.Web/MooFamily.Cms.Web.csproj ./MooFamily.Cms.Web/
RUN dotnet restore ./MooFamily.Cms.Web/MooFamily.Cms.Web.csproj

COPY src/MooFamily.Cms.Web/ ./MooFamily.Cms.Web/
RUN dotnet publish ./MooFamily.Cms.Web/MooFamily.Cms.Web.csproj \
    -c Release -o /app /p:UseAppHost=false

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app

# Non-root user
RUN useradd -m -u 1000 app && chown -R app:app /app
USER app

COPY --from=build --chown=app:app /app .

ENV ASPNETCORE_URLS=http://+:5000
ENV ASPNETCORE_ENVIRONMENT=Production
EXPOSE 5000

# Health check uses Umbraco's built-in
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -fsS http://localhost:5000/umbraco/api/health || exit 1

ENTRYPOINT ["dotnet", "MooFamily.Cms.Web.dll"]
```

**`.dockerignore`** (at repo root):

```
**/bin
**/obj
**/.vs
**/node_modules
.git
.github
docs
*.md
docker-compose*.yml
.env*
```

**`docker-compose.yml`** (at repo root) — for local dev only:

```yaml
services:
  umbraco:
    build:
      context: .
      dockerfile: deploy/Dockerfile
    ports:
      - "5000:5000"
    environment:
      ASPNETCORE_ENVIRONMENT: Development
      ConnectionStrings__umbracoDbDSN: "Data Source=/app/umbraco/Data/Umbraco.sqlite.db;Cache=Shared;Foreign Keys=True;Pooling=True"
      ConnectionStrings__umbracoDbDSN_ProviderName: "Microsoft.Data.Sqlite"
      Umbraco__CMS__Unattended__InstallUnattended: "true"
      Umbraco__CMS__Unattended__UnattendedUserName: "Admin"
      Umbraco__CMS__Unattended__UnattendedUserEmail: "admin@local.test"
      Umbraco__CMS__Unattended__UnattendedUserPassword: "LocalDev_Password123!"
    volumes:
      - umbdata:/app/umbraco/Data

volumes:
  umbdata:
```

### Build and push

```bash
# Authenticate Docker to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build (use amd64 explicitly if on Apple Silicon)
docker buildx build --platform linux/amd64 \
  -f deploy/Dockerfile \
  -t $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$PROJECT/umbraco:latest \
  -t $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$PROJECT/umbraco:v0.1.0 \
  --push .
```

### Validation
- [ ] `docker compose up --build` runs Umbraco at `localhost:5000`.
- [ ] Image visible: `aws ecr list-images --repository-name $PROJECT/umbraco`.

---

## 9. Phase 6 — Deploy to App Runner

**Goal:** Umbraco live at `cms.your-domain.com`.

### Step 1 — Create the VPC connector

```bash
VPC_CONNECTOR_ARN=$(aws apprunner create-vpc-connector \
  --vpc-connector-name $PROJECT-vpc-connector \
  --subnets $PRIV_A $PRIV_B \
  --security-groups $SG_APP \
  --query VpcConnector.VpcConnectorArn --output text)
```

### Step 2 — Create the App Runner service

Save this config to `/tmp/apprunner-config.json` — replace placeholders:

```json
{
  "ServiceName": "moofamily-umbraco",
  "SourceConfiguration": {
    "AutoDeploymentsEnabled": true,
    "ImageRepository": {
      "ImageIdentifier": "<AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/moofamily/umbraco:latest",
      "ImageRepositoryType": "ECR",
      "ImageConfiguration": {
        "Port": "5000",
        "RuntimeEnvironmentVariables": {
          "ASPNETCORE_ENVIRONMENT": "Production",
          "ConnectionStrings__umbracoDbDSN_ProviderName": "Microsoft.Data.SqlClient",
          "Umbraco__CMS__Unattended__InstallUnattended": "true",
          "Umbraco__CMS__Unattended__UnattendedUserName": "Admin",
          "Umbraco__CMS__Unattended__UnattendedUserEmail": "admin@your-domain.com",
          "Umbraco__CMS__Storage__AWSS3__Media__BucketName": "<EXISTING_MEDIA_BUCKET>",
          "Umbraco__CMS__Storage__AWSS3__Media__Region": "us-east-1",
          "Umbraco__CMS__Storage__AWSS3__Media__BucketHostName": "media.your-domain.com",
          "Cors__AllowedOrigins": "https://master.d3boy6qi81n9oz.amplifyapp.com,https://your-domain.com",
          "Umbraco__CMS__DeliveryApi__PublicAccess": "false"
        },
        "RuntimeEnvironmentSecrets": {
          "ConnectionStrings__umbracoDbDSN": "arn:aws:secretsmanager:us-east-1:<AWS_ACCOUNT_ID>:secret:moofamily/umbraco/connection-string",
          "Umbraco__CMS__DeliveryApi__ApiKey": "arn:aws:secretsmanager:us-east-1:<AWS_ACCOUNT_ID>:secret:moofamily/umbraco/delivery-api-key",
          "Umbraco__CMS__Unattended__UnattendedUserPassword": "arn:aws:secretsmanager:us-east-1:<AWS_ACCOUNT_ID>:secret:moofamily/umbraco/admin-seed-password"
        }
      }
    },
    "AuthenticationConfiguration": {
      "AccessRoleArn": "arn:aws:iam::<AWS_ACCOUNT_ID>:role/service-role/AppRunnerECRAccessRole"
    }
  },
  "InstanceConfiguration": {
    "Cpu": "1024",
    "Memory": "2048",
    "InstanceRoleArn": "arn:aws:iam::<AWS_ACCOUNT_ID>:role/moofamily-apprunner-task"
  },
  "HealthCheckConfiguration": {
    "Protocol": "HTTP",
    "Path": "/umbraco/api/health",
    "Interval": 20,
    "Timeout": 10,
    "HealthyThreshold": 1,
    "UnhealthyThreshold": 5
  },
  "NetworkConfiguration": {
    "EgressConfiguration": {
      "EgressType": "VPC",
      "VpcConnectorArn": "<VPC_CONNECTOR_ARN>"
    }
  }
}
```

Create the AppRunnerECRAccessRole if it doesn't exist (AWS console makes this easy), then:

```bash
aws apprunner create-service --cli-input-json file:///tmp/apprunner-config.json
```

### Step 3 — Custom domain

```bash
SERVICE_ARN=$(aws apprunner list-services \
  --query "ServiceSummaryList[?ServiceName=='moofamily-umbraco'].ServiceArn" --output text)

aws apprunner associate-custom-domain \
  --service-arn $SERVICE_ARN \
  --domain-name cms.$DOMAIN

# Get the CNAME records to add
aws apprunner describe-custom-domains --service-arn $SERVICE_ARN
```

Add the returned CNAME records to Route 53. The custom domain takes 5–15 min to validate.

### Validation
- [ ] App Runner service status: `RUNNING`.
- [ ] `curl https://cms.$DOMAIN/umbraco` returns the backoffice login page.
- [ ] You can log in with the seeded admin password (from Secrets Manager).
- [ ] `curl https://cms.$DOMAIN/umbraco/delivery/api/v2/content -H "Api-Key: $DELIVERY_API_KEY"` returns JSON.
- [ ] Upload an image in the backoffice — confirm it lands in S3 and the URL on the response points to `media.$DOMAIN`.

### Common issues
- **502 from App Runner** — usually a startup failure. Check CloudWatch logs for the service. Most common cause: DB connection failure (firewall, wrong password) or DB collation not case-insensitive.
- **HTTPS health check failures** — confirm `DisableHttpsValidatorComposer` is in the build.
- **Slow first request** — Umbraco cold start can take 30–60 s. App Runner health check `StartPeriod` covers this.

---

## 10. Phase 7 — CI/CD with GitHub Actions

**Goal:** Push to `main` → image built → pushed to ECR → App Runner auto-deploys.

### Step 1 — Create IAM OIDC provider and role

```bash
# OIDC provider (one-time per AWS account)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# Trust policy: restrict to your repo
cat > /tmp/gha-trust.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::$AWS_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:YOUR_GITHUB_ORG/YOUR_REPO:*"
      }
    }
  }]
}
EOF

aws iam create-role --role-name github-actions-cms-deploy \
  --assume-role-policy-document file:///tmp/gha-trust.json

# Permissions: push to ECR only
cat > /tmp/gha-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["ecr:GetAuthorizationToken"],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage"
      ],
      "Resource": "arn:aws:ecr:$AWS_REGION:$AWS_ACCOUNT_ID:repository/$PROJECT/umbraco"
    }
  ]
}
EOF

aws iam put-role-policy --role-name github-actions-cms-deploy \
  --policy-name github-actions-cms-deploy-policy \
  --policy-document file:///tmp/gha-policy.json
```

### Step 2 — Workflow file

**`.github/workflows/cms-deploy.yml`**:

```yaml
name: CMS Deploy

on:
  push:
    branches: [main]
    paths:
      - "src/**"
      - "deploy/**"
      - ".github/workflows/cms-deploy.yml"
  workflow_dispatch:

permissions:
  id-token: write
  contents: read

env:
  AWS_REGION: us-east-1
  ECR_REPOSITORY: moofamily/umbraco

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '10.0.x'

      - name: Restore
        run: dotnet restore src/MooFamily.Cms.Web/MooFamily.Cms.Web.csproj

      - name: Build
        run: dotnet build src/MooFamily.Cms.Web/MooFamily.Cms.Web.csproj --no-restore -c Release

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/github-actions-cms-deploy
          aws-region: ${{ env.AWS_REGION }}

      - uses: aws-actions/amazon-ecr-login@v2
        id: ecr

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build and push image
        uses: docker/build-push-action@v5
        with:
          context: .
          file: deploy/Dockerfile
          platforms: linux/amd64
          push: true
          tags: |
            ${{ steps.ecr.outputs.registry }}/${{ env.ECR_REPOSITORY }}:${{ github.sha }}
            ${{ steps.ecr.outputs.registry }}/${{ env.ECR_REPOSITORY }}:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

### Step 3 — Set repo secret
In GitHub repo settings → Secrets and variables → Actions:
- `AWS_ACCOUNT_ID` = your 12-digit AWS account ID

### Validation
- [ ] Push a trivial commit to main; workflow runs green.
- [ ] New image appears in ECR with the commit SHA as a tag.
- [ ] App Runner kicks off a deployment automatically; status returns to `RUNNING`.

---

## 11. Phase 8 — Content Migration

**Goal:** All existing site pages exist in Umbraco as content.

For each page on the current Amplify site:

1. In the backoffice, create a Standard Page node under Home with the matching slug.
2. Copy text content into blocks (Heading, Rich Text).
3. Upload images via the Media Library (they land in S3 automatically).
4. Add Image blocks pointing at the uploaded media.
5. For each YouTube embed, add a YouTube block with the URL.
6. For each Play Store link, add a Play Store block.
7. Save & Publish.
8. Verify with: `curl https://cms.$DOMAIN/umbraco/delivery/api/v2/content/item/<slug> -H "Api-Key: ..."`

### Validation
- [ ] Every page on the current site has a corresponding Umbraco node.
- [ ] All images present in the Media Library and reachable at `media.$DOMAIN`.
- [ ] Delivery API returns the expected JSON for each.

---

## 12. Phase 9 — React Integration

**Goal:** React site fetches content from Umbraco instead of using hard-coded data.

This is done **per page, behind a feature flag** so each page can be cut over independently.

### React-side files

**`src/lib/umbracoClient.ts`**:

```typescript
const API_BASE = import.meta.env.VITE_UMBRACO_API_BASE_URL;
const API_KEY = import.meta.env.VITE_UMBRACO_API_KEY;

if (!API_BASE) throw new Error("VITE_UMBRACO_API_BASE_URL is not set");

const headers: HeadersInit = {
  "Accept": "application/json",
  ...(API_KEY ? { "Api-Key": API_KEY } : {}),
};

export interface BlockItem {
  content: {
    contentType: string;
    id: string;
    properties: Record<string, unknown>;
  };
}

export interface UmbracoPage {
  contentType: string;
  name: string;
  id: string;
  route: { path: string };
  properties: {
    title: string;
    metaDescription?: string;
    blocks?: { items: BlockItem[] };
    [key: string]: unknown;
  };
}

export async function getPage(path: string): Promise<UmbracoPage> {
  const url = `${API_BASE}/umbraco/delivery/api/v2/content/item${path}?expand=properties[$all]`;
  const res = await fetch(url, { headers });
  if (!res.ok) throw new Error(`Umbraco fetch failed: ${res.status} ${url}`);
  return res.json();
}

export async function getSettings(): Promise<UmbracoPage> {
  return getPage("/settings");
}
```

**`src/components/BlockRenderer.tsx`**:

```tsx
import { BlockItem } from "../lib/umbracoClient";
import { HeadingBlock } from "./blocks/HeadingBlock";
import { RichTextBlock } from "./blocks/RichTextBlock";
import { ImageBlock } from "./blocks/ImageBlock";
import { YouTubeBlock } from "./blocks/YouTubeBlock";
import { PlayStoreBlock } from "./blocks/PlayStoreBlock";
import { CtaBlock } from "./blocks/CtaBlock";

export function BlockRenderer({ blocks }: { blocks: BlockItem[] }) {
  return (
    <>
      {blocks.map((b) => {
        const { contentType, id, properties } = b.content;
        switch (contentType) {
          case "headingBlock":   return <HeadingBlock key={id} {...(properties as any)} />;
          case "richTextBlock":  return <RichTextBlock key={id} {...(properties as any)} />;
          case "imageBlock":     return <ImageBlock key={id} {...(properties as any)} />;
          case "youtubeBlock":   return <YouTubeBlock key={id} {...(properties as any)} />;
          case "playStoreBlock": return <PlayStoreBlock key={id} {...(properties as any)} />;
          case "ctaBlock":       return <CtaBlock key={id} {...(properties as any)} />;
          default:
            console.warn(`Unknown block type: ${contentType}`);
            return null;
        }
      })}
    </>
  );
}
```

Each block component (`HeadingBlock`, `ImageBlock`, etc.) is a thin wrapper that takes the properties from the Delivery API and renders the existing visual component. Example:

**`src/components/blocks/YouTubeBlock.tsx`**:

```tsx
function extractVideoId(input: string): string | null {
  if (/^[a-zA-Z0-9_-]{11}$/.test(input)) return input;
  const m = input.match(/(?:youtube\.com\/watch\?v=|youtu\.be\/)([a-zA-Z0-9_-]{11})/);
  return m ? m[1] : null;
}

export function YouTubeBlock({ videoUrl, caption }: { videoUrl: string; caption?: string }) {
  const id = extractVideoId(videoUrl);
  if (!id) return null;
  return (
    <figure className="my-8">
      <div className="aspect-video">
        <iframe
          src={`https://www.youtube.com/embed/${id}`}
          title={caption ?? "YouTube video"}
          allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
          allowFullScreen
          className="w-full h-full"
        />
      </div>
      {caption && <figcaption className="mt-2 text-sm text-gray-600">{caption}</figcaption>}
    </figure>
  );
}
```

### Page-level fetching (feature-flagged)

```tsx
// src/pages/AboutPage.tsx
import { useEffect, useState } from "react";
import { getPage, UmbracoPage } from "../lib/umbracoClient";
import { BlockRenderer } from "../components/BlockRenderer";
import { AboutPageLegacy } from "./AboutPageLegacy";

const USE_CMS = import.meta.env.VITE_USE_CMS_FOR_ABOUT === "true";

export function AboutPage() {
  if (!USE_CMS) return <AboutPageLegacy />;

  const [page, setPage] = useState<UmbracoPage | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    getPage("/about").then(setPage).catch((e) => setError(String(e)));
  }, []);

  if (error) return <AboutPageLegacy />; // fail open to old version
  if (!page) return <div>Loading…</div>;

  const blocks = page.properties.blocks?.items ?? [];
  return (
    <>
      <h1>{page.properties.title}</h1>
      <BlockRenderer blocks={blocks} />
    </>
  );
}
```

### Amplify env vars
In the Amplify console, add for the `master` branch:
- `VITE_UMBRACO_API_BASE_URL` = `https://cms.your-domain.com`
- `VITE_UMBRACO_API_KEY` = (the value stored in Secrets Manager)
- `VITE_USE_CMS_FOR_ABOUT` = `true` (per-page flags as you roll out)

### Validation per page
- [ ] Visit the page on Amplify; content rendered matches Umbraco.
- [ ] Edit content in backoffice; refresh page; changes appear.
- [ ] Network tab shows `Api-Key` header on Delivery API calls.
- [ ] No CORS errors in browser console.

Once a page is verified, leave the flag on. Roll out one at a time.

---

## 13. Phase 10 — Hardening

**Goal:** Production-grade safety nets.

### CloudWatch alarms
```bash
# 5xx rate
aws cloudwatch put-metric-alarm \
  --alarm-name $PROJECT-apprunner-5xx \
  --metric-name 5xxStatusResponses \
  --namespace AWS/AppRunner \
  --statistic Sum \
  --period 300 --evaluation-periods 1 --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=ServiceName,Value=moofamily-umbraco

# RDS CPU
aws cloudwatch put-metric-alarm \
  --alarm-name $PROJECT-rds-cpu \
  --metric-name CPUUtilization \
  --namespace AWS/RDS \
  --statistic Average \
  --period 600 --evaluation-periods 2 --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=$PROJECT-umbraco
```

Attach an SNS topic to these for email/Slack notifications.

### WAF on the App Runner endpoint
Optional but recommended. Use AWS WAF with the managed `AWSManagedRulesCommonRuleSet` and `AWSManagedRulesAmazonIpReputationList`.

### uSync committed to Git
By now you should have `uSync/` directory under source control. Add to CI:

```yaml
# In cms-deploy.yml, before the build step:
- name: Verify uSync content types are committed
  run: |
    if [ -z "$(ls -A uSync/v9 2>/dev/null)" ]; then
      echo "Warning: uSync directory is empty. Export your content types from the backoffice."
      exit 1
    fi
```

### Rate limit the Delivery API
In `Program.cs`:

```csharp
builder.Services.AddRateLimiter(options =>
{
    options.AddFixedWindowLimiter("delivery-api", o =>
    {
        o.PermitLimit = 100;
        o.Window = TimeSpan.FromMinutes(1);
    });
});
// ... and apply to the delivery api endpoints
```

### Validation
- [ ] Alarms fire on synthetic load.
- [ ] uSync export reproduces the content model on a fresh install.
- [ ] Rate limit returns 429 above threshold.

---

## 14. Operational Runbook

### Where to look when things break

| Symptom | Where to check |
|---|---|
| Site returns 502 / 503 | CloudWatch logs for App Runner service `moofamily-umbraco` |
| Backoffice slow | RDS CloudWatch metrics (CPU, connections, free storage) |
| Images broken | S3 bucket → object exists? CloudFront cache → invalidate? |
| New deploy didn't take effect | ECR → was the `latest` tag updated? App Runner → did rollout succeed? |
| CORS errors from React | Verify `Cors__AllowedOrigins` env var on App Runner includes the Amplify URL |
| Editor publish doesn't appear on site | Delivery API caches? Force-refresh; check CloudFront cache headers |

### Rolling back a bad deploy
ECR keeps the previous N images. To roll back:

```bash
# Re-tag a previous image as latest
aws ecr batch-get-image --repository-name $PROJECT/umbraco --image-ids imageTag=<PREVIOUS_SHA> \
  --query 'images[0].imageManifest' --output text > /tmp/manifest.json
aws ecr put-image --repository-name $PROJECT/umbraco \
  --image-tag latest --image-manifest file:///tmp/manifest.json
# App Runner auto-redeploys on the latest tag change
```

### Restoring DB from snapshot
RDS keeps 7 days of automated snapshots. Restore via:

```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier moofamily-umbraco-restored \
  --db-snapshot-identifier <snapshot-id>
```

Update Secrets Manager connection string to point at the restored instance.

---

## 15. Appendix A — `.env.example`

Save at repo root. Real `.env` is gitignored.

```bash
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=
PROJECT=moofamily
DOMAIN=your-domain.com
EXISTING_MEDIA_BUCKET=
EXISTING_MEDIA_CF_DIST=
GITHUB_REPO=YOUR_ORG/YOUR_REPO
```

## 16. Appendix B — IAM permissions cheat sheet

| Role | Used by | Allowed actions |
|---|---|---|
| `moofamily-apprunner-task` | App Runner running Umbraco | S3 (existing bucket, RW), Secrets Manager (project secrets, read), CloudWatch Logs (write) |
| `github-actions-cms-deploy` | GitHub Actions OIDC | ECR (push to project repo only) |
| `AppRunnerECRAccessRole` | App Runner to pull images | ECR (pull, read) |

## 17. Appendix C — `.gitignore`

```gitignore
# .NET
**/bin/
**/obj/
*.user

# Umbraco
src/MooFamily.Cms.Web/umbraco/Data/
src/MooFamily.Cms.Web/umbraco/Logs/
src/MooFamily.Cms.Web/umbraco/mediafiles/
src/MooFamily.Cms.Web/umbraco/models/
src/MooFamily.Cms.Web/wwwroot/media/
src/MooFamily.Cms.Web/appsettings.Local.json

# Tooling
.vs/
.idea/
.vscode/launch.json

# Secrets
.env
.env.local
**/secrets.json

# Docker
.dockerignore.local
```

## 18. Appendix D — Useful curl recipes

```bash
# Get all pages
curl "https://cms.$DOMAIN/umbraco/delivery/api/v2/content?filter=contentType:standardPage&take=100" \
  -H "Api-Key: $DELIVERY_API_KEY" | jq

# Get a single page with all properties
curl "https://cms.$DOMAIN/umbraco/delivery/api/v2/content/item/about?expand=properties[\$all]" \
  -H "Api-Key: $DELIVERY_API_KEY" | jq

# Get settings
curl "https://cms.$DOMAIN/umbraco/delivery/api/v2/content/item/settings?expand=properties[\$all]" \
  -H "Api-Key: $DELIVERY_API_KEY" | jq

# Health check
curl -i "https://cms.$DOMAIN/umbraco/api/health"
```

## 19. Appendix E — Definition of Done (per phase)

Reproduce in PR descriptions when closing out each phase:

```markdown
- [ ] All "Validation" checkboxes for this phase are ticked
- [ ] Code committed; CI green
- [ ] Documentation updated where assumptions changed
- [ ] Secrets in Secrets Manager, not committed
- [ ] No `TODO` markers left related to this phase
```

---

## 20. Quick-Start Prompt for Claude Code

When starting a new VS Code session, paste this to Claude Code:

> I'm building a self-hosted Umbraco 17 CMS that feeds an existing React site via the Umbraco Content Delivery API. The full spec is in `docs/IMPLEMENTATION.md`. Read that file end-to-end first. The stack and architecture decisions are locked — do not propose changes to them. We're currently on Phase **<N>**. Help me complete it by following the Steps, creating the Files listed, and ticking off the Validation checklist before moving on.

---

**End of document.** When you're ready to start, run the first command in section 4.
