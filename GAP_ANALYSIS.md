# Live site vs Umbraco — gap analysis (2026-05-28)

Source: parsed `https://cowparadisegames.com/assets/index-BRBU4lHB.js` (851 KB Vite bundle).
Routes confirmed: `/`, `/about-us`, `/games`, `/stories`, `/news`, `/moo-family`, `/login`, `/profile`, `/market`, `/privacy-policy`, `/terms`, `/admin/*`.

## What's marketing CMS content (Umbraco's job)
## What's app/admin functionality (NOT Umbraco's job)

The SPA's `/admin/*` route exposes a full admin panel — Achievement, Advertisement, Asset, Chest, Premium Item, Shop Item, Privilege, Reward Options (Common/Rare/Epic/Legendary), Battle Pass, Referrals, Transactions, leaderboards. These are app-backend data (DB + API), NOT Umbraco content. **Skip from this gap analysis.**

User-state pages (`/login`, `/profile`) are also app-managed, not CMS.

The marketplace (`/market`) is largely app data, though its hero/intro copy could live in CMS.

---

## Gap 1 — Missing pages in Umbraco

| Live route | In Umbraco? | Notes |
|---|---|---|
| `/privacy-policy` | ❌ MISSING | Long-form legal content (data rights, partners, cookies). Standard Page. |
| `/terms` | ❌ MISSING | Long-form legal content (rules: no cheating / no reverse engineering / no resale / no harmful behaviour / no unauthorized distribution / no unfair gameplay / no derivative works). Standard Page. |
| `/about-us` | ✅ exists as `/Home/About` | Path mismatch — CMS slug is `About`, frontend expects `about-us`. Might need urlSegment override or rename. |
| `/moo-family` | ✅ exists | Path mismatch — CMS slug is `Moo Family`, frontend uses `moo-family`. |
| `/login` `/profile` `/market` | n/a | App-managed, not CMS. |

## Gap 2 — Missing doc types in Umbraco

| Element / doc type | What it represents | Why needed |
|---|---|---|
| **Short** | Short-form video clip ("Cow Paradise Shorts", "Moo Shorts", "Game Shorts") | The site has a Shorts section separate from Stories. |
| **Learning Category** | Topic groupings: ABC Puzzles, Bedtime Smiles, Brain Games, Alphabet adventures, Candy words, Letters seek & find | "Learning Categories" section appears on Moo Family / Home page. |
| **Stat / Counter** | Single-number callouts | Already partially covered by `statBlock` element. |
| **Footer Quick Links** | Footer "Quick Links" section | Likely covered by existing `Settings → Footer Links Block List`. |

## Gap 3 — Missing content **instances** in Umbraco

### Games (9 in Umbraco; 11+ on live)
| Game | Umbraco? | S3 asset? | Live state |
|---|---|---|---|
| Cow Run | ✅ | `cowrun.webp` | Released, Google Play available |
| Moo Climb | ✅ | `MooClimb.webp` | Coming Soon |
| Moo Crush | ✅ | `MooCrush.webp` | Coming Soon |
| Moo Dash | ✅ | `MooDash.webp` | Coming Soon |
| Moo Rash | ✅ | `MooRush.webp` (spelling mismatch!) | Coming Soon |
| Moo Skate | ✅ | `MooSkate.webp` | Coming Soon |
| Moo Ski | ✅ | `Mooski.webp` | Early Access |
| **MooSoccor** (note spelling) | ✅ as "Moo Soccer" | `moo_soccer.webp` | "MooSoccor" appears in bundle — sic |
| Moo Tag | ✅ | `MooTag.webp` | Coming Soon |
| **Flying Moo** | ❌ MISSING | `FlyingMoo.webp` exists | Game node not in Umbraco |
| **Moo Chess** | ❌ MISSING | `moochess.webp` exists | Game node not in Umbraco |
| **Paintball Madness** | ⚠️ Lives as Story, but live also treats as game | `PaintBall_02.webp` exists | Steam link: `https://store.steampowered.com/app/3393780/Paintball_Madness/` |

### Game play URLs — needs update
- Cow Run → **`https://play.google.com/store/apps/details?id=com.CowParadise.CowRun&pcampaignid=web_share`** (real Google Play)
  Currently set to `https://cowparadisegames.com/games/cow-run` (placeholder)
- Paintball Madness → **`https://store.steampowered.com/app/3393780/Paintball_Madness/`** (real Steam)

### Stories — 9 in Umbraco; site has 21 YouTube videos
The bundle exposes 21 YouTube video IDs. Mapping to story names will require visual confirmation, but these are the real story video IDs:
`GmmCJCuhXVY`, `MRr53jCZJao`, `MYl5Sihfi2Y`, `QyAQ293-8zk`, `VJ2yel1dsR8`, `WC0SFtTKsic`, `WNcScFUqoE0`, `_R0c9ANHA6Y`, `clrJzbMww8A`, `dwfgWy7OrTo`, `f8qPIUjkhAs`, `fMLO7IQ4pEo`, `gqmTuG2SR7w`, `lk8ASXS-Ic4`, `op3qTKf1J4U`, `p7kd-dIerWk`, `pMgbrxNSOac`, `r8CfSREXCYk`, `s5SzQJWYYT8`, `xiZdAnjGxag`, `yVMOiyrTjlk`

Story / shorts titles observed in bundle (likely the 21 entries split across Stories + Shorts):
- The Big Showdown
- The Spark
- Meet Atlas
- Helping a Friend
- Understanding Feelings
- Bedtime Smiles
- Hero highlights
- Cow Paradise growth journey timeline
- (plus the 9 already in Umbraco)

### News articles — 6 in Umbraco; live confirms 6
Titles match. ✓

### Team members — 5 in Umbraco
"Cameron Williamson" appears in bundle — likely a placeholder/demo name in the admin panel, not a real team member.

### Characters — 6 in Umbraco
Live site confirms 6 ("Six friendly characters"). ✓

## Gap 4 — Page content (block lists)

### Home page hero stats / sections missing in Umbraco
- "200K Downloads", "Parents Satisfaction", "Years of Experience" stat-row likely
- "THE MOO JOURNEY" timeline
- "Powered by the Best in Gaming" (logo strip — 10 PoweredBy SVGs exist in S3 already)
- "Why Kids Love Learning with..." section
- "Subscribe for new stories" — newsletterSignup block exists, not used on Home yet
- "Join Our Community" / "Join the Cowverse" — CTA block opportunity

### About page sections (live has more depth than current Umbraco blocks)
- "From Napkin Doodles to Game Hero" (likely a timeline heading)
- "The Story Behind Cow Paradise"
- "Cow Paradise growth journey timeline" — timelineItem element exists, unused
- "Make Learning Fun" / "Empower Creativity" / "Foster Growth" / "Build Community" — 4-feature feature card grid
- Mission / Vision (partially done)

### Moo Family page sections
- "Meet the Friends Who…" — character grid header
- "Learning Categories" — 6 categories (ABC Puzzles, Bedtime Smiles, Brain Games, Alphabet adventures, Candy words, Letters seek & find)
- "Cow Paradise Shorts" section — needs Short content type or block

## Recommended order of work

1. **Quick wins** (text only, no new doc types)
   - Update Cow Run play URL to real Google Play link
   - Add Paintball Madness Steam URL
   - Fix Moo Soccer / MooSoccor spelling (decide which is canonical)
   - Add Privacy Policy + Terms of Service as new Standard Page nodes

2. **Add missing games** (2-3 instances using existing Game doc type)
   - Flying Moo, Moo Chess + possibly Paintball Madness (as game, not story)

3. **Expand Home / About / Moo Family block content** to match live structure (feature cards, timeline, logo strip, newsletter, stat row)

4. **Map 21 YouTube videos** to story + shorts content (needs user visual review of live site)

5. **Add new doc types** (only if you intend to manage these via CMS):
   - Short
   - Learning Category

6. **Future / out of scope here**: marketplace, achievements, privileges, etc. (app-managed).
