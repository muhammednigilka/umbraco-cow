# Saturday Go-Live — 4-Day Execution Timeline

**Goal:** Moo Family CMS live at `https://cms.cowparadisegames.com` with React app on Amplify pulling content from it.
**Deadline:** Saturday 2026-05-23
**Start:** Tuesday 2026-05-19
**Working window:** 4 days

> Companion to [AWS_DEPLOYMENT_PLAN.md](AWS_DEPLOYMENT_PLAN.md). The plan describes *what*; this document describes *when*.

---

## Locked-in values

| Variable | Value |
|---|---|
| `DOMAIN` | `cowparadisegames.com` |
| `PROJECT` | `moofamily` |
| `AWS_REGION` | `us-east-1` |
| `EXISTING_MEDIA_BUCKET` | _**(pending — user to provide)**_ |
| `EXISTING_MEDIA_CF_DIST` | _**(pending — derived from bucket)**_ |
| DNS host | External (not Route 53) — manual CNAME records |
| Execution model | User runs AWS CLI commands themselves; AI guides |
| AWS CLI | Not installed/configured on the dev machine yet |
| Image source | Already in the S3 bucket (uses Option C — uSync media XML) |

---

## Day-by-day schedule

### 🟢 Today — Tuesday 2026-05-19 — Pre-flight + Phase 4 (infra)

**Time budget:** 6 hours. **Pre-flight must finish today** or the rest slips.

| Block | Task | Owner | Time |
|---|---|---|---|
| 1 | **Install AWS CLI v2** + `aws configure` (set access key, secret, region `us-east-1`) | You | 20 min |
| 2 | **List your S3 bucket** so we can lock the name: `aws s3 ls` → tell me the bucket name. | You | 5 min |
| 3 | **Pre-flight code changes** (re-add S3 package, restore Storage config, tighten CORS) | AI writes; you review | 30 min |
| 4 | **Push code to GitHub** (`git remote add origin ...`, `git push -u origin main`) | You | 15 min |
| 5 | **Phase 4.1–4.2:** VPC + subnets + security groups | You run CLI; AI guides | 30 min |
| 6 | **Phase 4.3:** Launch RDS SQL Server Express (then wait ~15 min for it to provision while doing other work) | You run CLI | 5 min CLI + 15 min wait |
| 7 | **Phase 4.4:** Create ECR repository | You run CLI | 5 min |
| 8 | **Phase 4.5:** IAM role for App Runner tasks | You run CLI | 15 min |
| 9 | **Phase 4.6:** ACM certificate for `*.cowparadisegames.com` + manually add validation CNAMEs in your DNS provider | You | 30 min (+wait for issue) |
| 10 | **Phase 4.7:** Generate + store Delivery API key and admin seed password in Secrets Manager | You run CLI | 10 min |
| 11 | **Phase 4.4 (back to RDS):** Connect via temp EC2 bastion, create `umbraco` database with case-insensitive collation. Store full conn string in Secrets Manager. | You | 30 min |
| 12 | **Phase 4.8:** Verify existing S3 bucket policy allows App Runner role; add `media.cowparadisegames.com` as CloudFront alias; add CNAME in your DNS for `media.cowparadisegames.com → <cf-distribution>.cloudfront.net` | You | 30 min |

**End-of-day checkpoint:**
```
✅ AWS CLI configured
✅ Code pushed to GitHub
✅ VPC up, 2 subnets each public/private
✅ RDS available, umbraco DB created with case-insensitive collation
✅ ECR repo exists
✅ ACM cert ISSUED (or pending validation; if pending overnight, it'll be ready Wed morning)
✅ 3 secrets in Secrets Manager
✅ S3 bucket policy + CloudFront alias set up for media subdomain
```

If anything is red at end of day, **call it out tomorrow morning before doing anything else**.

---

### 🟡 Wednesday 2026-05-20 — Phases 5 + 6 (image build + deploy)

**Time budget:** 6 hours.

| Block | Task | Owner | Time |
|---|---|---|---|
| 1 | **Verify ACM cert is ISSUED** (`aws acm describe-certificate ...`). If not, troubleshoot the DNS CNAME first. | You | 5 min |
| 2 | **Create [deploy/Dockerfile](deploy/Dockerfile)**, `.dockerignore`, `docker-compose.yml` per IMPLEMENTATION.md §8 | AI writes; you review | 30 min |
| 3 | **Test the container locally:** `docker compose up --build` → confirm Umbraco boots with all 44 nodes via Delivery API at `localhost:5000` | You | 30 min |
| 4 | **Build and push image to ECR** with `docker buildx build --push` (linux/amd64 tag) | You run | 15–30 min depending on network |
| 5 | **Phase 6.1:** Create App Runner VPC connector | You run CLI | 5 min |
| 6 | **Phase 6.2:** Create App Runner service via JSON config (with all 13 content type aliases) | You run CLI | 10 min |
| 7 | **Watch CloudWatch logs** during first boot — verify uSync auto-imports 44 nodes | You | 20 min |
| 8 | **Phase 6.4:** Associate custom domain `cms.cowparadisegames.com`; add CNAME records returned by App Runner to your DNS provider | You | 30 min (+wait 5–15 min) |
| 9 | **Phase 6.5: Validate**: curl `https://cms.cowparadisegames.com/umbraco/api/health` (200), then `/umbraco/delivery/api/v2/content?take=100` with API-Key header (44 items) | You | 15 min |
| 10 | **Log into the backoffice** at `https://cms.cowparadisegames.com/umbraco` with seeded admin email + password from Secrets Manager. Verify all 19 content types + 44 nodes. | You | 15 min |

**End-of-day checkpoint:**
```
✅ Docker image in ECR with v0.1.0 + latest tags
✅ App Runner status RUNNING
✅ cms.cowparadisegames.com → App Runner (DNS validated)
✅ Delivery API returns 44 items with API key
✅ Backoffice login works
✅ All content visible in backoffice tree
⚠️ Images still null — fixed Thursday
```

---

### 🟠 Thursday 2026-05-21 — Phase 7 + Phase 8 (CI/CD + images)

**Time budget:** 6 hours.

| Block | Task | Owner | Time |
|---|---|---|---|
| 1 | **Phase 7.1:** Create IAM OIDC provider + `github-actions-cms-deploy` role with ECR push permissions | You run CLI | 20 min |
| 2 | **Phase 7.2:** Commit `.github/workflows/cms-deploy.yml` to the repo | AI writes; you push | 15 min |
| 3 | **Phase 7.3:** Set `AWS_ACCOUNT_ID` GitHub repo secret | You | 5 min |
| 4 | **Test CI/CD:** push a trivial commit; verify GHA builds + pushes; App Runner auto-redeploys; Delivery API still returns 44 items | You | 20 min |
| 5 | **Phase 8 (image migration) — START.** Inventory: list every image in your S3 bucket → map each one to a content node (Game / Story / News / Character / TeamMember). | You + AI | 1 hour |
| 6 | **AI generates uSync media XML** for each image (Media items with the S3 keys pre-set) + updates content XML to reference them | AI writes | 1 hour |
| 7 | **Commit + push** → GHA deploys → uSync auto-import wires images to content on next boot | You | 15 min |
| 8 | **Validate:** call Delivery API for a few nodes (`/games/cow-run`, `/characters/little-jack`) — verify `gameCoverImage` and `characterImage` now return `[{url: "/media/.../*.png"}]` | AI runs curl; you verify | 30 min |
| 9 | **Render-check from a browser:** load a media URL like `https://media.cowparadisegames.com/cowrun.png` directly — confirm 200 | You | 10 min |
| 10 | **Buffer:** unblock anything that broke (CORS, CloudFront cache, S3 permissions) | You + AI | 1 hour |

**End-of-day checkpoint:**
```
✅ Push to main → auto-deploys to App Runner
✅ All entity types have non-null images in Delivery API responses
✅ Image URLs resolve via CloudFront
✅ React app can fetch full content + images
```

---

### 🔴 Friday 2026-05-22 — Phase 9 (React integration)

**Time budget:** 6 hours. **This is the day we connect your live React app.**

| Block | Task | Owner | Time |
|---|---|---|---|
| 1 | **In Amplify console:** add env vars for the master branch (`VITE_UMBRACO_API_BASE_URL`, `VITE_UMBRACO_API_KEY`, `VITE_USE_CMS_FOR_*=false` for each page) | You | 15 min |
| 2 | **In React project:** drop `umbracoClient.ts` + `umbracoTypes.ts` from [HEADLESS_INTEGRATION.md §5](HEADLESS_INTEGRATION.md) into `src/lib/` | You | 15 min |
| 3 | **Migrate News page first** (lowest risk): build CMS-backed version + flip flag → deploy → verify on Amplify | You | 1.5 hours |
| 4 | **Migrate Games page** (data-heavy) | You | 1 hour |
| 5 | **Migrate Stories page** (with category tabs) | You | 1 hour |
| 6 | **Migrate Team grid on About page** | You | 30 min |
| 7 | **Validate cache invalidation:** edit a node in backoffice → reload Amplify page → confirm change appears within seconds | You | 15 min |
| 8 | **Buffer:** CORS issues, missing properties, UI gotchas | 1 hour |

> **Skipped today on purpose:** Home page, full About body, Moo Family page. These need Block List content (which we left empty) and are the riskiest to migrate. Defer to next week unless time permits Saturday morning.

**End-of-day checkpoint:**
```
✅ Amplify production loads News, Games, Stories, About-team from CMS
✅ Editor can change content and see it on the live site
✅ No CORS errors in browser console
```

---

### ⚪ Saturday 2026-05-23 — Hardening + Go-Live

**Time budget:** 4 hours (assume morning go-live).

| Block | Task | Owner | Time |
|---|---|---|---|
| 1 | **Phase 10.1:** CloudWatch alarms on App Runner 5xx + RDS CPU + RDS storage | You run CLI | 30 min |
| 2 | **Phase 10.2:** WAF with managed rules (optional but recommended) | You | 30 min |
| 3 | **uSync export from production** to verify the model is reproducible (Settings → uSync → Export, then commit the output) | You | 15 min |
| 4 | **Final end-to-end check:** browse the live site, edit content in backoffice, confirm 5-second propagation; load a fresh browser session and confirm no auth issues | You | 30 min |
| 5 | **Document the launch:** runbook in [IMPLEMENTATION.md §15](IMPLEMENTATION.md#14-operational-runbook) (where to look when things break) and a credentials handoff | You | 30 min |
| 6 | **Buffer for any last-minute issues** | — | 2 hours |
| 7 | **🚀 Announce live.** | You | — |

---

## What we're explicitly NOT doing in this 4-day window

To make the deadline, we **defer** these (do them next week):

1. **Home page block content** — Hero Banner, Stat Blocks, etc. for the Home page body. Phase 9 leaves Home pointing to the legacy hard-coded version.
2. **About page body content** — same reason. We migrate the Team grid but not the timeline / mission / vision sections.
3. **Moo Family page** — entire page deferred.
4. **Editor onboarding** — Add additional Umbraco backoffice users, create reduced-permission roles. Just admin for now.
5. **uSync media migration via XML (Option C)** vs **manual backoffice upload (Option A)** — we'll attempt Option C Thursday; if it's flaky, fall back to Option A and finish manually by Saturday.
6. **Search / filtering** in the Delivery API. Use simple client-side filters first.

---

## Risk register

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| ACM cert validation slow | Medium | Half day | Start Tuesday so it has overnight to validate |
| RDS schema migration fails first boot | Low | Half day | Tested locally Wed first; collation prevents most issues |
| uSync image XML format doesn't import cleanly | Medium | Half day | Test Thursday with 1 image first, then batch |
| AWS S3 storage package compatibility | High | Full day | Pre-flight Tuesday tests it locally first |
| Production CORS rejects Amplify URL | Medium | 1 hour | Verified Wednesday with curl from a browser dev tool |
| Editor login fails due to bad seed password | Low | 1 hour | Read password from Secrets Manager fresh; never copy from terminal |
| DNS propagation slow at external DNS host | Medium | Half day | Use 60s TTL records; verify each step with `nslookup` |

---

## Daily standup checklist

Each morning, before starting:
1. Check yesterday's "end-of-day checkpoint" — anything red?
2. Check CloudWatch logs for App Runner — any errors overnight?
3. Check AWS billing alarm — any unexpected spend?
4. Review today's blocks. Anything blocking?

---

## What I need from you to start today

Three blockers — answer these and we can begin Pre-flight code changes:

1. **S3 bucket name** (paste the exact name).
2. **DNS host** for cowparadisegames.com (so I know which UI/screenshot to walk you through for CNAME records).
3. **Confirmation** you've installed AWS CLI v2 and run `aws configure`. If not, do that first — it's the gating step for everything else.

Once those are in, the first thing I'll do is the **Pre-flight code changes** (§3 of the deployment plan): re-add the AWS S3 storage NuGet, restore the config block, lock down production CORS. ~30 minutes of work and then we kick off Phase 4.
