# AWS Deployment Plan — Moo Family CMS

> **Audience:** A developer (or AI assistant) deploying the locally-running Umbraco 17 CMS to AWS with all content already created (44 nodes + 19 content types) intact.
> Self-contained. Builds on [IMPLEMENTATION.md](IMPLEMENTATION.md) but supersedes it where we discovered differences during Phase 1–3.

**Last updated:** 2026-05-18
**Status:** Ready to execute. Phases 1–3 complete locally; this plan covers Phases 4–10.
**Estimated total time:** 2–3 working days end-to-end.

---

## 0. What we're deploying

A self-hosted **Umbraco 17.4 CMS** that already has:

- ✅ 19 content types (3 page docs, 5 entity docs, 5 folder docs, 16 element types) — defined via uSync XML
- ✅ 44 published content nodes (Home, Settings, About, Moo Family, 5 folders, 9 games, 9 stories, 6 news, 6 characters, 5 team members) — defined via uSync XML
- ✅ Delivery API verified end-to-end locally
- ⚠️ All Media Picker fields are currently **empty** (no images uploaded locally) — will be filled post-deployment via backoffice

**Why this matters:** because content+model live as XML in `src/MooFamily.Cms.Web/uSync/v17/`, the container ships them on disk. On first boot in AWS, uSync auto-imports → production has identical content to local **with one click**.

---

## 1. Architecture (final state after this plan)

```
your-domain.com           → AWS Amplify       (React site, UNCHANGED through Phase 9)
cms.your-domain.com       → AWS App Runner    (Umbraco 17 container)
media.your-domain.com     → CloudFront + S3   (uploaded images)

Backing services:
  Amazon RDS SQL Server Express  (private subnets, port 1433)
  AWS Secrets Manager            (DB connection, API key, admin password)
  Amazon ECR                     (Docker image registry)
  Amazon CloudWatch              (logs + alarms)
  Amazon Route 53                (DNS for cms. and media. subdomains)
  AWS Certificate Manager        (TLS, us-east-1 for CloudFront)
  GitHub Actions                 (CI/CD via OIDC, push to ECR triggers App Runner)
```

Editor flow:
1. Editor logs into `https://cms.your-domain.com/umbraco`
2. Backoffice → uploads image → goes to S3 via `Our.Umbraco.StorageProviders.AWSS3`
3. Backoffice → edits content → writes to RDS SQL Server
4. React app on Amplify → `GET https://cms.your-domain.com/umbraco/delivery/api/v2/...` → reads from RDS, image URLs point to `https://media.your-domain.com/...`

---

## 2. Prerequisites — gather before starting

Fill these in your local environment before running Phase 4 commands. None of them are baked into source yet; they're env vars or CLI args.

| Variable | Description | Where to find |
|---|---|---|
| `AWS_ACCOUNT_ID` | 12-digit account ID | `aws sts get-caller-identity` |
| `AWS_REGION` | Default `us-east-1` | Pick — match your existing resources |
| `DOMAIN` | Your production domain (e.g. `moofamily.com`) | Already-owned or Route 53 hosted |
| `EXISTING_MEDIA_BUCKET` | Reusing the bucket from IMPLEMENTATION.md | `aws s3 ls` |
| `EXISTING_MEDIA_CF_DIST` | CloudFront dist ID for media | `aws cloudfront list-distributions` |
| `GITHUB_REPO` | `org/repo` of this CMS code | GitHub URL |
| Admin email | For backoffice login in prod | Your call |

### Local tooling
- ✅ .NET 10 SDK (already installed)
- ✅ Docker Desktop (already installed)
- ✅ Git (already installed)
- ⏳ **AWS CLI v2** — install if not present: https://aws.amazon.com/cli/
- ⏳ **GitHub repo** — push this Umbraco project to a GitHub repo first

### AWS account setup
- Admin access to the AWS account
- Billing alerts enabled (recommended at $50, $100, $200 thresholds)
- Region default set: `aws configure set region us-east-1`

---

## 3. Pre-flight code changes (do these BEFORE Phase 4)

These are deltas from the locally-running code that production needs. Each must be committed to git before building the Docker image.

### 3.1 Re-add AWS S3 storage with correct version pinning

In Phase 1 we removed `Our.Umbraco.StorageProviders.AWSS3` because v1.3.0 collided with AWSSDK.Core 4.x. For production we need media on S3.

**Option A (recommended — pin AWSSDK.Core to 3.x):**
```powershell
dotnet add src/MooFamily.Cms.Web/MooFamily.Cms.Web.csproj package AWSSDK.Core --version 3.7.305
dotnet add src/MooFamily.Cms.Web/MooFamily.Cms.Web.csproj package AWSSDK.S3 --version 3.7.x
dotnet add src/MooFamily.Cms.Web/MooFamily.Cms.Web.csproj package Our.Umbraco.StorageProviders.AWSS3
```

**Option B (use a newer fork that supports AWSSDK 4.x):** search NuGet for a maintained fork.

Then re-add the gated call in [Program.cs](src/MooFamily.Cms.Web/Program.cs):
```csharp
using Our.Umbraco.StorageProviders.AWSS3.DependencyInjection;

// after CreateUmbracoBuilder():
var s3Bucket = builder.Configuration["Umbraco:Storage:AWSS3:Media:BucketName"];
if (!string.IsNullOrWhiteSpace(s3Bucket))
{
    umbracoBuilder.AddAWSS3MediaFileSystem();
}
```

And restore the `Umbraco:Storage:AWSS3` section in [appsettings.json](src/MooFamily.Cms.Web/appsettings.json):
```json
"Storage": {
  "AWSS3": {
    "Media": {
      "BucketName": "",
      "Region": "us-east-1",
      "BucketHostName": ""
    }
  }
}
```
Values stay empty in appsettings.json; production fills them via env vars (Phase 6).

### 3.2 Enable unattended install for first-boot DB seeding

In [appsettings.json](src/MooFamily.Cms.Web/appsettings.json), keep `InstallUnattended: false` (Phase 6 sets it to `true` via env var only in App Runner).

### 3.3 Tighten production CORS

The `appsettings.Production.json` should override CORS to lock down origins:
```json
{
  "Cors": {
    "AllowedOrigins": "https://master.d3boy6qi81n9oz.amplifyapp.com,https://your-domain.com"
  }
}
```

### 3.4 Make sure `PublicAccess: false` in base appsettings

The dev override (in `appsettings.Development.json`) sets it to `true`. Production should be `false` so the API key is enforced.

Verify [appsettings.json](src/MooFamily.Cms.Web/appsettings.json) has:
```json
"DeliveryApi": {
  "Enabled": true,
  "PublicAccess": false,
  "ApiKey": "",
  ...
}
```

### 3.5 Commit and push to GitHub

```powershell
git add -A
git commit -m "feat: production-ready config for AWS deployment"
git remote add origin https://github.com/YOUR_ORG/YOUR_REPO.git
git push -u origin main
```

---

## 4. Phase 4 — AWS Infrastructure

**Goal:** stand up VPC, RDS SQL Server, ECR, IAM, Secrets Manager, ACM cert.
**Time:** 3–5 hours (most spent waiting for RDS to provision).

Use the AWS CLI commands from [IMPLEMENTATION.md §7](IMPLEMENTATION.md#7-phase-4--aws-infrastructure). They're correct as-written. Below are the **deltas / additions** specific to deploying with our content.

### 4.1 Environment variables (set once per shell)

```powershell
$env:AWS_REGION="us-east-1"
$env:AWS_ACCOUNT_ID=(aws sts get-caller-identity --query Account --output text)
$env:PROJECT="moofamily"
$env:DOMAIN="your-domain.com"                  # ← REPLACE
$env:EXISTING_MEDIA_BUCKET="your-bucket"       # ← REPLACE
$env:EXISTING_MEDIA_CF_DIST="E1234ABC"         # ← REPLACE
```

### 4.2 VPC + subnets + security groups

Run [IMPLEMENTATION.md §7 Steps 1–2](IMPLEMENTATION.md#step-1--vpc-and-subnets) verbatim. Save the output IDs:
```
VPC_ID, IGW_ID, PUB_A, PUB_B, PRIV_A, PRIV_B, SG_APP, SG_RDS
```

### 4.3 RDS SQL Server Express

Use [IMPLEMENTATION.md §7 Step 3](IMPLEMENTATION.md#step-3--rds-sql-server-express). Wait ~15 min.

**After it's available, create the `umbraco` database with case-insensitive collation:**

Spin up a temporary EC2 in the public subnet, install `sqlcmd`, connect to RDS, run:
```sql
CREATE DATABASE umbraco COLLATE SQL_Latin1_General_CP1_CI_AS;
```

> **Why case-insensitive?** Umbraco's schema migrations fail on case-sensitive collations. This is non-negotiable.

Then capture the connection string into Secrets Manager:
```powershell
$RDS_ENDPOINT=(aws rds describe-db-instances --db-instance-identifier "$($env:PROJECT)-umbraco" --query "DBInstances[0].Endpoint.Address" --output text)
$DB_PASSWORD=(aws secretsmanager get-secret-value --secret-id "$($env:PROJECT)/db/master-password" --query SecretString --output text)
$CONN="Server=$RDS_ENDPOINT,1433;Database=umbraco;User Id=admin;Password=$DB_PASSWORD;TrustServerCertificate=True;Encrypt=True;"
aws secretsmanager create-secret --name "$($env:PROJECT)/umbraco/connection-string" --secret-string "$CONN"
```

### 4.4 ECR repository

```powershell
aws ecr create-repository --repository-name "$($env:PROJECT)/umbraco" --image-scanning-configuration scanOnPush=true --encryption-configuration encryptionType=AES256
```

### 4.5 IAM role for App Runner tasks

Use [IMPLEMENTATION.md §7 Step 6](IMPLEMENTATION.md#step-6--iam-role-for-umbraco-to-readwrite-the-existing-s3-bucket) verbatim. Verifies App Runner can read secrets and write S3.

### 4.6 ACM certificate (in us-east-1)

Use [IMPLEMENTATION.md §7 Step 7](IMPLEMENTATION.md#step-7--acm-certificate-in-us-east-1-required-for-cloudfront). Validate via DNS, wait for `ISSUED`.

### 4.7 Delivery API key + admin seed password

```powershell
$DELIVERY_API_KEY = -join ((1..32) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
aws secretsmanager create-secret --name "$($env:PROJECT)/umbraco/delivery-api-key" --secret-string $DELIVERY_API_KEY

# Generate a secure admin password (uppercase, lowercase, digit, special required for Umbraco)
$ADMIN_SEED_PASSWORD = (-join ((33..126) | Get-Random -Count 20 | ForEach-Object { [char]$_ })) + "A1!"
aws secretsmanager create-secret --name "$($env:PROJECT)/umbraco/admin-seed-password" --secret-string $ADMIN_SEED_PASSWORD
```

> **Note:** Save the `$ADMIN_SEED_PASSWORD` value locally so you can log in on first boot. Or read it back from Secrets Manager later.

### 4.8 Configure existing S3 + CloudFront for media

Follow [IMPLEMENTATION.md §7 Step 9](IMPLEMENTATION.md#step-9--configure-the-existing-media-bucket-for-umbraco-use):
- Verify the bucket policy allows the App Runner IAM role to write
- Add `media.$DOMAIN` as a CloudFront alias with the ACM cert
- Create Route 53 alias `media.$DOMAIN → CloudFront distribution`

### 4.9 Validation

```powershell
aws rds describe-db-instances --db-instance-identifier "$($env:PROJECT)-umbraco" --query "DBInstances[0].DBInstanceStatus"   # → "available"
aws acm describe-certificate --certificate-arn $CERT_ARN --query "Certificate.Status"                                          # → "ISSUED"
aws secretsmanager list-secrets --query "SecretList[?starts_with(Name, '$($env:PROJECT)/')].Name"                              # → 3 secrets
nslookup media.$($env:DOMAIN)                                                                                                   # → CloudFront IPs
```

---

## 5. Phase 5 — Containerization

**Goal:** Docker image built, pushed to ECR, with our 44 content nodes baked in.
**Time:** 1–2 hours.

### 5.1 Create the Dockerfile

Create [deploy/Dockerfile](deploy/Dockerfile) per [IMPLEMENTATION.md §8](IMPLEMENTATION.md#8-phase-5--containerization) — the file is correct as-is.

**Key point:** the Dockerfile copies `src/MooFamily.Cms.Web/` into the image, which includes the `uSync/v17/` folder with all our content type and content XML. That's how the content travels to production.

### 5.2 Create `.dockerignore` and `docker-compose.yml`

Both files are in [IMPLEMENTATION.md §8](IMPLEMENTATION.md#8-phase-5--containerization). Use verbatim.

### 5.3 Test locally first

```powershell
docker compose up --build
```
Visit `http://localhost:5000`. Confirm:
- ✅ Umbraco boots
- ✅ uSync auto-import runs and creates all 19 content types and 44 nodes (check Content section after login)
- ✅ Delivery API returns 44 items at `http://localhost:5000/umbraco/delivery/api/v2/content?take=100`

**If this step fails, fix it before pushing to ECR.** It's much cheaper to debug locally.

### 5.4 Build and push to ECR

```powershell
aws ecr get-login-password --region $env:AWS_REGION | docker login --username AWS --password-stdin "$($env:AWS_ACCOUNT_ID).dkr.ecr.$($env:AWS_REGION).amazonaws.com"

docker buildx build --platform linux/amd64 `
  -f deploy/Dockerfile `
  -t "$($env:AWS_ACCOUNT_ID).dkr.ecr.$($env:AWS_REGION).amazonaws.com/$($env:PROJECT)/umbraco:latest" `
  -t "$($env:AWS_ACCOUNT_ID).dkr.ecr.$($env:AWS_REGION).amazonaws.com/$($env:PROJECT)/umbraco:v0.1.0" `
  --push .
```

### 5.5 Validation

```powershell
aws ecr list-images --repository-name "$($env:PROJECT)/umbraco" --query "imageIds[*].imageTag"
# → ["latest", "v0.1.0"]
```

---

## 6. Phase 6 — Deploy to App Runner

**Goal:** Umbraco live at `cms.your-domain.com` with all 44 nodes loaded.
**Time:** 1–2 hours (mostly waiting for first deployment + DB schema creation).

### 6.1 VPC connector

Per [IMPLEMENTATION.md §9 Step 1](IMPLEMENTATION.md#step-1--create-the-vpc-connector).

### 6.2 App Runner service

Use the JSON config from [IMPLEMENTATION.md §9 Step 2](IMPLEMENTATION.md#step-2--create-the-app-runner-service), with these **specific additions for our deployment**:

```jsonc
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

          // First-boot user creation
          "Umbraco__CMS__Unattended__InstallUnattended": "true",
          "Umbraco__CMS__Unattended__UnattendedUserName": "Admin",
          "Umbraco__CMS__Unattended__UnattendedUserEmail": "admin@your-domain.com",

          // S3 media storage (NEW — was empty locally)
          "Umbraco__CMS__Storage__AWSS3__Media__BucketName": "<EXISTING_MEDIA_BUCKET>",
          "Umbraco__CMS__Storage__AWSS3__Media__Region": "us-east-1",
          "Umbraco__CMS__Storage__AWSS3__Media__BucketHostName": "media.your-domain.com",

          // CORS for the live React app
          "Cors__AllowedOrigins": "https://master.d3boy6qi81n9oz.amplifyapp.com,https://your-domain.com",

          // Delivery API behaviour
          "Umbraco__CMS__DeliveryApi__PublicAccess": "false",

          // Delivery API content type allowlist (all our types)
          "Umbraco__CMS__DeliveryApi__AllowedContentTypeAliases__0": "home",
          "Umbraco__CMS__DeliveryApi__AllowedContentTypeAliases__1": "standardPage",
          "Umbraco__CMS__DeliveryApi__AllowedContentTypeAliases__2": "settings",
          "Umbraco__CMS__DeliveryApi__AllowedContentTypeAliases__3": "game",
          "Umbraco__CMS__DeliveryApi__AllowedContentTypeAliases__4": "story",
          "Umbraco__CMS__DeliveryApi__AllowedContentTypeAliases__5": "newsArticle",
          "Umbraco__CMS__DeliveryApi__AllowedContentTypeAliases__6": "character",
          "Umbraco__CMS__DeliveryApi__AllowedContentTypeAliases__7": "teamMember",
          "Umbraco__CMS__DeliveryApi__AllowedContentTypeAliases__8": "gamesFolder",
          "Umbraco__CMS__DeliveryApi__AllowedContentTypeAliases__9": "storiesFolder",
          "Umbraco__CMS__DeliveryApi__AllowedContentTypeAliases__10": "newsFolder",
          "Umbraco__CMS__DeliveryApi__AllowedContentTypeAliases__11": "charactersFolder",
          "Umbraco__CMS__DeliveryApi__AllowedContentTypeAliases__12": "teamFolder",

          // Site URL (silences the warning we saw locally)
          "Umbraco__CMS__WebRouting__UmbracoApplicationUrl": "https://cms.your-domain.com"
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

> **Three additions you won't find in IMPLEMENTATION.md:**
> 1. `AllowedContentTypeAliases__0..12` exposes our entity types (game, story, etc.) — without these, the Delivery API silently filters them out.
> 2. `WebRouting__UmbracoApplicationUrl` silences the every-minute KeepAlive warning.
> 3. `Storage__AWSS3__BucketName` is **non-empty** — that's the trigger our gated code in [Program.cs](src/MooFamily.Cms.Web/Program.cs) uses to register S3 media.

Save to `/tmp/apprunner-config.json` and:
```powershell
aws apprunner create-service --cli-input-json file:///tmp/apprunner-config.json
```

### 6.3 Watch the first boot

```powershell
$SERVICE_ARN=(aws apprunner list-services --query "ServiceSummaryList[?ServiceName=='moofamily-umbraco'].ServiceArn" --output text)
aws apprunner describe-service --service-arn $SERVICE_ARN --query "Service.Status"
```

CloudWatch logs (in CloudWatch console under `/aws/apprunner/moofamily-umbraco/...`) should show:
1. Container starts, .NET 10 runtime loads
2. `[STARTUP]` debug lines (from our Program.cs)
3. Umbraco connects to SQL Server, runs schema migrations (takes 60-90s)
4. Unattended installer creates admin user from secrets
5. **uSync auto-imports** all 19 content types + 44 content nodes (look for `uSync Import: ... processed N items, M changes`)
6. `Now listening on: http://+:5000`
7. App Runner health check passes

If anything fails, common causes:
- DB connection: check security group rules (App Runner connector SG → RDS SG on 1433)
- Collation: re-create DB with `COLLATE SQL_Latin1_General_CP1_CI_AS`
- uSync: check `/app/uSync/v17/` exists in container (`docker exec` on a copy)

### 6.4 Custom domain

```powershell
aws apprunner associate-custom-domain --service-arn $SERVICE_ARN --domain-name "cms.$($env:DOMAIN)"
aws apprunner describe-custom-domains --service-arn $SERVICE_ARN
```

Add the returned CNAME records to Route 53. Validation takes 5–15 minutes.

### 6.5 Validation

After custom domain validates:

```powershell
# 1. Backoffice login page
curl -i "https://cms.$($env:DOMAIN)/umbraco"
# Expect: 200, HTML with Umbraco login

# 2. Health check
curl -i "https://cms.$($env:DOMAIN)/umbraco/api/health"
# Expect: 200

# 3. Delivery API with API key (should return all 44 items)
$KEY = (aws secretsmanager get-secret-value --secret-id "$($env:PROJECT)/umbraco/delivery-api-key" --query SecretString --output text)
curl -i -H "Api-Key: $KEY" "https://cms.$($env:DOMAIN)/umbraco/delivery/api/v2/content?take=100" | ConvertFrom-Json | Select-Object total

# Expect: total = 44
```

**Log into the backoffice:**
- URL: `https://cms.$DOMAIN/umbraco`
- Email: `admin@your-domain.com`
- Password: from `moofamily/umbraco/admin-seed-password` in Secrets Manager

Verify:
- ✅ **Settings → Document Types** shows all 19 types
- ✅ **Content** section shows full tree (Home, Settings, About, Moo Family, Games/, Stories/, News/, Characters/, Team/)
- ✅ Each entity node has its data filled (game titles, story descriptions, etc.)
- ❌ Media Picker fields are still empty — that's expected, we fix in Phase 8.

---

## 7. Phase 7 — CI/CD with GitHub Actions

**Goal:** push to `main` → image built → pushed to ECR → App Runner auto-deploys.
**Time:** 1 hour.

Use [IMPLEMENTATION.md §10](IMPLEMENTATION.md#10-phase-7--cicd-with-github-actions) verbatim:
1. Create the IAM OIDC provider + `github-actions-cms-deploy` role
2. Save `.github/workflows/cms-deploy.yml`
3. Set `AWS_ACCOUNT_ID` repo secret in GitHub
4. Push a trivial commit; verify the workflow runs green and App Runner re-deploys

### Validation
- ✅ A new commit triggers GHA → green build → new image tagged with commit SHA
- ✅ App Runner status returns to `RUNNING` after auto-deploy
- ✅ The Delivery API still returns 44 items after redeploy

---

## 8. Phase 8 — Content migration (THE KEY PHASE)

> **Reframing:** because uSync ships content with the container, the "content migration" is already done by the time Phase 6 completes. This phase is about **filling in the gaps** — primarily images.

**Time:** 1 day for image migration; less if you skip image migration.

### 8.1 What's already migrated (via uSync auto-import)

After Phase 6, production has identical content to local:

| Item | Count | State |
|---|---|---|
| Content types (doc + element) | 19 | ✅ Identical |
| Page nodes (Home, About, Moo Family, Settings) | 4 | ✅ Identical text content |
| Folder nodes | 5 | ✅ Identical |
| Game entities | 9 | ✅ All fields populated except `gameCoverImage` |
| Story entities | 9 | ✅ All fields populated except `storyThumbnail` |
| News articles | 6 | ✅ All fields populated except `newsHeroImage` |
| Characters | 6 | ✅ All fields populated except `characterImage` |
| Team members | 5 | ✅ All fields populated except `memberPhoto` |

### 8.2 Image migration strategy

You have three options for getting images into production. Pick one.

#### Option A — Manual upload via backoffice (simplest)

1. Log into `https://cms.$DOMAIN/umbraco`
2. **Media** section → upload images one by one
3. For each entity (Game, Story, etc.) → edit → Media Picker → select the uploaded image → Publish

Time: ~2 hours for ~40 images. Editors can also do this as part of normal content management.

#### Option B — S3 bulk pre-seed + backoffice picking

1. Bulk-upload images directly to S3:
   ```powershell
   aws s3 sync ./local-images/ "s3://$($env:EXISTING_MEDIA_BUCKET)/media/"
   ```
2. Umbraco needs to "know" about them — the backoffice has a "Sync media" option that scans S3 and creates Media nodes.
3. Then pick them per entity.

Time: 30 min upload + 1 hour picking.

#### Option C — uSync media items (advanced, more upfront work)

Write uSync XML for Media items (under `uSync/v17/Media/`) and have them auto-import alongside content. Requires:
- Image files already in S3
- Knowing each image's S3 key
- Writing the XML for each media node with correct property references

Time: 4 hours upfront, then 0 for redeploys.

**Recommended: Option A for now.** Switch to Option C if you find yourself re-doing media migration multiple times.

### 8.3 Image migration plan (Option A)

For each visual asset on the live Amplify site:

1. Download the image from the React app's `public/` or `src/assets/` folder (or screenshot if not accessible).
2. In Umbraco backoffice → **Media** → upload.
3. Match to its content node:
   - Game cover images → 9 game entities
   - Story thumbnails → 9 stories
   - News hero images → 6 articles
   - Character images → 6 characters
   - Team photos → 5 members
   - Home hero, About hero, etc. → page-level Media Picker properties
4. Save & Publish each.

> **Tip:** to do this efficiently, sit with a content editor for an afternoon and divide the work. Or have one person upload all media first, another do the picking.

### 8.4 Block-list content (Home, About blocks)

We deliberately left `home.blocks` and `standardPage.blocks` empty because Block List JSON is fragile to author manually. Now's the time to fill them:

1. Open Home → **Blocks** property → click **+ Add content**.
2. Add a **Hero Banner** with `bannerTitle = "Where Games Become a Universe"`.
3. Add **4 Stat Blocks** for the numbers (100+, 20+, 10+, 95%).
4. Continue building out the page to match the live site.
5. Same for About — add Hero Banner, Heading, Rich Text, 4 Timeline Items (2022, 2023, 2024, 2026), Mission/Vision, Newsletter Signup.

This is where editors take over.

### 8.5 Validation

```powershell
$KEY = (aws secretsmanager get-secret-value --secret-id "$($env:PROJECT)/umbraco/delivery-api-key" --query SecretString --output text)

# Single game should now have non-null cover image
curl -H "Api-Key: $KEY" "https://cms.$($env:DOMAIN)/umbraco/delivery/api/v2/content/item/games/cow-run?expand=properties[`$all]"
# Look for: "gameCoverImage": [ { "url": "/media/.../cowrun.png", ... } ]

# Confirm image URL works
curl -I "https://media.$($env:DOMAIN)/media/.../cowrun.png"
# Expect: 200
```

---

## 9. Phase 9 — React integration

**Goal:** the React site on Amplify fetches from `cms.$DOMAIN` instead of hard-coded data, per-page feature-flagged.
**Time:** 1–2 days.

This is fully covered in [HEADLESS_INTEGRATION.md](HEADLESS_INTEGRATION.md). Summary:

### 9.1 Add env vars in Amplify

For the `master` branch in Amplify console:
```
VITE_UMBRACO_API_BASE_URL=https://cms.your-domain.com
VITE_UMBRACO_API_KEY=<from-aws-secrets-manager>
VITE_USE_CMS_FOR_HOME=false              # flip to true when ready per page
VITE_USE_CMS_FOR_GAMES=false
VITE_USE_CMS_FOR_NEWS=false
VITE_USE_CMS_FOR_STORIES=false
VITE_USE_CMS_FOR_ABOUT=false
VITE_USE_CMS_FOR_MOOFAMILY=false
```

### 9.2 Drop in the client + types

Copy [HEADLESS_INTEGRATION.md §5.3](HEADLESS_INTEGRATION.md#53-the-client-library) — `umbracoClient.ts` — and §5.4 — `umbracoTypes.ts` — into your React app's `src/lib/`.

### 9.3 Migrate page by page

Suggested order (low risk → high impact):
1. **News page** — list + detail, low risk because it's basically a new section.
2. **Team section on About page** — pure data display.
3. **Stories page** — tabbed lists, no hand-written interactions.
4. **Games page** — list with filters.
5. **About page** body — content-heavy, hits the BlockRenderer.
6. **Home page** — the big one. Heroes, carousels, multiple data sources.
7. **Moo Family page** — last because it has the most varied sections.

For each, follow the pattern in [HEADLESS_INTEGRATION.md §6](HEADLESS_INTEGRATION.md#6-page-by-page-integration): feature-flag the page, build the CMS-backed version, test side-by-side, flip the flag.

### 9.4 Validation per page

- ✅ Page on Amplify renders content from CMS
- ✅ Edit content in backoffice → reload page → changes appear
- ✅ Network tab shows `Api-Key` header on Delivery API requests
- ✅ No CORS errors in browser console

---

## 10. Phase 10 — Hardening

**Goal:** production safety nets.
**Time:** half day.

Use [IMPLEMENTATION.md §13](IMPLEMENTATION.md#13-phase-10--hardening) — all four items still apply:

1. **CloudWatch alarms** on 5xx rate, RDS CPU, App Runner restart count
2. **AWS WAF** with `AWSManagedRulesCommonRuleSet` + `AWSManagedRulesAmazonIpReputationList`
3. **uSync directory** committed to git (already done)
4. **Rate limiting** on Delivery API in Program.cs

Add one specific to our setup:

### 10.1 Backup RDS daily

Already configured (`--backup-retention-period 7` in Phase 4). Verify in console under RDS → Maintenance & backups.

### 10.2 Image asset reliability

Add a CloudWatch alarm on S3 4xx errors and CloudFront 5xx errors. If editors upload a 50MB image, S3 will reject; you want to know.

---

## 11. End-to-end validation checklist

Run this after each major phase. Strikes through what's expected to be incomplete at each stage.

```markdown
After Phase 4 (Infrastructure):
- [ ] RDS available, secret exists
- [ ] ECR repo exists
- [ ] ACM cert ISSUED
- [ ] media.$DOMAIN resolves
- [ ] All 3 secrets present in Secrets Manager

After Phase 5 (Containerization):
- [ ] docker compose up works locally with 44 items in API
- [ ] Image pushed to ECR with `latest` and `v0.1.0` tags

After Phase 6 (App Runner):
- [ ] Service status RUNNING
- [ ] cms.$DOMAIN/umbraco serves login page
- [ ] Login works with seeded credentials
- [ ] All 19 content types visible in backoffice
- [ ] All 44 nodes visible in content tree
- [ ] Delivery API returns 44 items with valid API key
- [ ] Delivery API returns 401 without API key

After Phase 7 (CI/CD):
- [ ] Trivial commit triggers workflow, builds, deploys
- [ ] New image visible in ECR
- [ ] App Runner auto-redeploys to RUNNING

After Phase 8 (Content):
- [ ] At least 5 games have cover images
- [ ] At least 3 news articles have hero images
- [ ] Home page has populated blocks list
- [ ] All Media Picker URLs resolve to https://media.$DOMAIN

After Phase 9 (React):
- [ ] At least 1 page on Amplify is CMS-backed
- [ ] Editing content in backoffice updates the live page within seconds (cache TTL)
- [ ] No CORS errors

After Phase 10 (Hardening):
- [ ] CloudWatch alarms fire on synthetic 5xx
- [ ] WAF blocks a curl with suspicious User-Agent
- [ ] uSync export reproduces the model on a fresh DB
```

---

## 12. Rollback plan

### 12.1 If Phase 6 deployment fails
App Runner keeps previous task definitions:
```powershell
aws apprunner list-operations --service-arn $SERVICE_ARN
# Pause; or rollback to previous image via ECR re-tag
aws ecr put-image --repository-name "$($env:PROJECT)/umbraco" --image-tag latest --image-manifest (aws ecr batch-get-image --repository-name "$($env:PROJECT)/umbraco" --image-ids imageTag=<PREVIOUS_SHA> --query 'images[0].imageManifest' --output text)
```
App Runner auto-redeploys.

### 12.2 If RDS gets corrupted
Restore from automated snapshot:
```powershell
aws rds describe-db-snapshots --db-instance-identifier "$($env:PROJECT)-umbraco" --query "DBSnapshots[*].[DBSnapshotIdentifier,SnapshotCreateTime]"
aws rds restore-db-instance-from-db-snapshot --db-instance-identifier "$($env:PROJECT)-umbraco-restored" --db-snapshot-identifier <snapshot-id>
```
Update Secrets Manager `connection-string` to point at the restored endpoint.

### 12.3 If content gets accidentally deleted
- Umbraco has built-in recycle bin (right-click → restore).
- uSync re-imports recreate the schema; content needs DB restore.

### 12.4 If a bad deploy ships broken Delivery API
- Quickly: roll back the image (above).
- Slower: revert the bad commit on `main`, push, GitHub Actions deploys the rollback.

### 12.5 To completely abandon the deployment
```powershell
aws apprunner delete-service --service-arn $SERVICE_ARN
aws rds delete-db-instance --db-instance-identifier "$($env:PROJECT)-umbraco" --skip-final-snapshot
aws ec2 delete-vpc --vpc-id $VPC_ID    # detach IGW + delete subnets/SGs first
aws ecr delete-repository --repository-name "$($env:PROJECT)/umbraco" --force
aws secretsmanager delete-secret --secret-id "$($env:PROJECT)/umbraco/connection-string" --force-delete-without-recovery
# ... repeat for other secrets
```

---

## 13. Cost estimate (us-east-1, USD/month)

| Service | Sizing | Estimated cost |
|---|---|---|
| App Runner | 1 vCPU, 2 GB, ~always-on | $25–40 |
| RDS SQL Server Express | db.t3.small, 20 GB gp3 | $25 |
| RDS storage + IOPS | 20 GB gp3 + light IOPS | $3 |
| ECR | < 1 GB images, ~10 PuLls/day | < $1 |
| S3 (media) | Existing bucket, ~1 GB media | < $1 |
| CloudFront (media) | Light traffic (mostly cached) | $1–5 |
| Secrets Manager | 3 secrets | $1.20 |
| CloudWatch logs | ~5 GB/mo | $2.50 |
| Route 53 | 1 hosted zone | $0.50 |
| **Total estimate** | | **$60–80/month** |

Light traffic. Scales up with editor activity and React app traffic; mostly App Runner concurrency.

---

## 14. Appendix A — Environment variable reference

All env vars passed to the App Runner service. Most are set in Phase 6 step 6.2; secrets resolve from Secrets Manager.

```
# Core runtime
ASPNETCORE_ENVIRONMENT=Production
ConnectionStrings__umbracoDbDSN=<secret>
ConnectionStrings__umbracoDbDSN_ProviderName=Microsoft.Data.SqlClient

# Unattended install (only used on first boot)
Umbraco__CMS__Unattended__InstallUnattended=true
Umbraco__CMS__Unattended__UnattendedUserName=Admin
Umbraco__CMS__Unattended__UnattendedUserEmail=admin@your-domain.com
Umbraco__CMS__Unattended__UnattendedUserPassword=<secret>

# Delivery API
Umbraco__CMS__DeliveryApi__PublicAccess=false
Umbraco__CMS__DeliveryApi__ApiKey=<secret>
Umbraco__CMS__DeliveryApi__AllowedContentTypeAliases__0..12=<13 type aliases>

# Storage
Umbraco__CMS__Storage__AWSS3__Media__BucketName=<bucket-name>
Umbraco__CMS__Storage__AWSS3__Media__Region=us-east-1
Umbraco__CMS__Storage__AWSS3__Media__BucketHostName=media.your-domain.com

# Networking
Umbraco__CMS__WebRouting__UmbracoApplicationUrl=https://cms.your-domain.com
Cors__AllowedOrigins=https://master.d3boy6qi81n9oz.amplifyapp.com,https://your-domain.com
```

---

## 15. Appendix B — Secrets Manager reference

| Secret name | Contents | Used by |
|---|---|---|
| `moofamily/db/master-password` | RDS admin password | Used once to build connection string |
| `moofamily/umbraco/connection-string` | Full SQL Server connection string | App Runner env var |
| `moofamily/umbraco/delivery-api-key` | 64-char hex key for Delivery API auth | App Runner env var, React env var |
| `moofamily/umbraco/admin-seed-password` | Initial admin login | App Runner env var (first boot only) |

---

## 16. Appendix C — Known gotchas (from Phases 1–3)

Lessons that apply to AWS deployment:

1. **Solution file is `.slnx` not `.sln`** in .NET 10 SDK — already accounted for.
2. **AWS S3 storage package version conflict** — see §3.1, must pin AWSSDK.Core to 3.7.x.
3. **`Microsoft.Data.Sqlite` doesn't handle `|DataDirectory|`** — irrelevant for production (we use SQL Server) but the Program.cs hack stays for SQLite-based local dev.
4. **`level` and `text` are reserved Umbraco property aliases** — we use `headingLevel`, `headingText`. Element types are imported as-is, no rename needed in prod.
5. **OpenIddict requires HTTP transport disabled** — `AllowHttpForOpenIddictComposer.cs` is in source; works for App Runner's SSL-terminating proxy.
6. **`AllowedContentTypeAliases` must list every content type** you want exposed via Delivery API. Easy to forget when adding new types later.
7. **Rich text values come as `{markup: "<html>", blocks: null}`** — React side uses `dangerouslySetInnerHTML={{__html: markup}}`.
8. **Media Picker values are arrays even for single-image fields** — use `[0]?.url`.
9. **Delivery API URL slugs are lowercased kebab-case**, not the node name.
10. **First boot in App Runner takes 60–90 seconds** for cold start (DB migrations + uSync auto-import). App Runner's `HealthCheck StartPeriod` of 60s might not be enough — set to 120s if you see flapping during first deploy.

---

## 17. Open questions to resolve before starting

Address these before Phase 4:

1. **Domain name** — what's the production domain? (Without this, every step that uses `$DOMAIN` is blocked.)
2. **AWS account** — do you have admin access? Region preference?
3. **Existing S3 bucket** — what's its name and CloudFront distribution ID? The plan assumes we're re-using.
4. **Image source** — where are the production images? On Amplify currently? In a Figma export? On disk somewhere?
5. **Editor credentials** — who needs backoffice access? (Add their email + role later, but plan for it.)
6. **Go-live target date** — drives whether we do Option A (manual image upload) or Option C (uSync media) for migration.

---

**End of document.** When you're ready to start, set the env vars in §2 and begin Phase 4. Verify each phase's checklist before moving on.
