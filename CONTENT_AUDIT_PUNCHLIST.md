# Content Audit & Fixes — cowparadisegames.com

**Date:** 2026-07-03 · **Scope:** every page and link on the live site, cross-checked against the
headless Umbraco content (uSync) and the live Delivery API for all 73 published nodes.

The site is a React SPA that renders entirely from this CMS via the Delivery API. A two-pass audit
(field-level + rendered/semantic) found placeholder, broken, and **mismatched** content. This
document records **what was fixed in the uSync content** (ships on the next deploy) and **what still
needs the team** (backoffice, assets, React, decisions).

---

## ✅ Fixed in this pass (uSync content → ships on next deploy)

| Area | Fix |
|---|---|
| **Stories (8)** | Removed the **Rickroll** video from all 8 stories; re-categorized all 8 to `Quick Learning Stories` so they surface in the Stories carousel; repointed the **Moo Shorts** & **Cow Paradise Shorts** carousels to real categories (they were filtering on tokens no content had → both rendered empty); fixed the Quick-Learning chip values to match story tags; "Subscribe" CTA → `/contact`. |
| **Shorts (21)** | Replaced stub `Short NN` titles and "Replace this…" descriptions with **real titles pulled from each YouTube video** + short descriptions; split across `Moo Shorts` (7, character/learning) and `Cow Paradise Shorts` (14, gameplay) so both Stories carousels populate. |
| **Footer** | `Terms` link `/terms` → **`/terms-of-service`** (was a 404 sitewide). |
| **Contact page** | Created a real **`/contact`** page (hero + contact email + socials + subscribe). All the former dead `#newsletter` CTAs (About, Market, Stories) now point here. |
| **Games — MooSoccer** | Fixed the **"Soccor" → "Soccer"** misspelling everywhere: node name, slug (`/games/moosoccor` → `/games/moo-soccer`), title, all headings, and URLs. |
| **Games — listing** | Replaced the leftover single-game hero (heading **"COWRUN"**, "Recently Released") with a proper games-index hero; removed the duplicate "Play Now" CTA that pointed at the same anchor. |
| **Games — all 12** | Genre-tailored **"What's New"** bullets (were byte-identical across every game); reworded the **"Meet the Friends Along the Way"** section (→ "See It in Action") which promised characters it never showed; fixed grammar ("is **a** action", "**adventure adventure**"). |
| **Games — misc** | Moo Ski banner "Coming Soon" → **"Early Access"** (matched its status); Moo Skate players **"Both"** → "Multiplayer"; Paintball `gameDetailsUrl` → internal (was off-site Steam); the 10 unreleased games' self-referential **"Play Now"** CTAs → **"Notify Me" → `/market`** (were no-ops). |
| **Home** | Rewrote the Trending subheading (was a copy-paste of the Powered-By line); de-duplicated the partner logo strip (2nd **Steam** → **Unity**). |
| **Moo Family** | Fixed the two dead hero anchors: **"Meet Characters"** now resolves (renamed the character section id `browse-stories` → `characters`); **"Start Learning"** `#learning` → `#learning-benefits`. Added the 4 missing **Educational Games** cards so the 8 category chips now have 8 matching cards. |
| **About** | Rewrote off-brand **"making blockchain feel human"** → "making learning feel like play". |
| **/characters & /shorts** | These landing pages returned **empty** (`properties:{}`). Added a `blocks` property to the `charactersFolder`/`shortsFolder` doc types and seeded a **hero + auto-sourced grid** so both pages now have real content. *(Depends on the React app rendering folder blocks — see C1.)* |

**Verified:** static grep clean (0 Rickrolls, 0 "Replace this", 0 bad `/terms`, 0 off-brand blockchain, 0 leftover "COWRUN" hero, 0 "Soccor", 0 grammar bugs, 0 dead `#newsletter`/`#characters`/`#learning` anchors); all 143 content JSON blocks parse.

**To go live:** commit → redeploy the CMS container → uSync auto-imports on boot (watch the cold-boot write-lock; import can be slow on first boot). Then re-pull the Delivery API to confirm.

---

## ⏳ Remaining — needs the team

### A. Backoffice actions (live CMS — cannot be done via the repo)

1. **Delete the stray duplicate "Stories" folder.** A second `storiesFolder` (id `7178385b-850d-42b2-bd6d-c0fcacdcf9ab`) is mis-parented under the *Fun & Learning* story, producing the route `/stories/fun-and-learning/stories/`. It was created in the backoffice (not seeded), so uSync won't remove it — **delete it in the backoffice**.
2. **Set the Featured Characters pickers** (2 min): Home → *Trending* section → *Featured Characters* = 3 characters (e.g. Moo, Milo, Ellie); Moo Family → *hero* → *Featured Characters* = same 3. *(Left for the backoffice because the picker's stored UDI format has no precedent in the repo to copy safely; the UI writes it correctly.)*

### B. Assets to upload (via backoffice — media does **not** travel through the repo)

> Media binaries are git-ignored and served from the live CMS `/media` path, so images/videos must be uploaded in the **backoffice**, not committed. Adding files to the repo would ship broken `/media/...` references.

- **Total empty:** ~272 image fields and 22 video fields across the content. Most are *optional* decorative icons (stat/bullet/benefit/ornament) that render gracefully — low priority.
- **High-priority imagery:** the 3 missing **character portraits** (Moo, Milo, Tina); the **Moo Tag** cover (only game with no cover); the **home hero** background (video + fallback); the **6 partner logos** (Steam, Epic, Immutable, Unreal, BGA, Unity); the 8 **story thumbnails**; page hero backgrounds (About, Moo Family, Games, Stories, News, Market, Login, Contact, and the 12 game heroes).
- **Videos (real URLs):** the 8 **story videos** (blanked for now — likely on the @moofamily_official / @CowParadiseGames YouTube channels); the **home "Where Adventure Comes to Life"** play video; the 12 game **"See It in Action"** trailers.

### C. React coordination (front-end repo — not this CMS)

1. **Confirm the SPA renders `charactersFolder`/`shortsFolder` blocks.** `/characters` and `/shorts` now expose a hero + grid via the API. If the SPA hard-codes those routes, wire them into the same BlockRenderer the other pages use.
2. **Educational Games chip filtering.** The 8 chips can't actually filter until `educationalGameCard` gains a `category` field (schema) and the React filter binds chip→category. Right now all 8 cards show (aligned with the 8 chips), but clicking a chip has no data to filter on.
3. **Filter-chip contract is inconsistent.** `/games` chips are facet *dimensions* (Platform/Genre/Status/Players) while `/stories` & `/news` chips are *values* — the model doesn't distinguish them, so React special-cases per page. Worth documenting/unifying.
4. **`#newsletter` anchor.** No page exposes a `newsletter` section id (the home `newsletterSignup` block has no id field). I routed the "Subscribe/Notify" CTAs to `/contact`; if you'd rather they scroll to an on-page signup, add a `newsletter` sectionId and repoint.
5. **Header "Profile"** links to `/profile`, which has no CMS page (user-data-driven) — confirm it's handled entirely React-side.
6. **Real store/play links** for the unreleased games (currently "Notify Me" → `/market`) once they launch.

### D. Decisions to confirm

- **Moo Rash vs Moo Rush** — the game's cover asset is named `MooRush.webp`, suggesting the intended name is "Moo Rush". Left **as-is** ("Moo Rash") pending your call (renaming changes the public URL).
- **Footer social handles** — two conflicting sets remain (`/cowparadise` vs `/cowparadisegames`). Both kept per request; pick the correct one when ready.
- **Contact email** — the new Contact page uses `hello@cowparadisegames.com`. Confirm or replace with the real address.

---

## Round 2 — Characters / educational-games / game rules (CMS enablement + React handoff)

**Why:** the live `/characters`, character detail pages (e.g. `/characters/daddy-moo`), and the
educational-game detail pages (`/moo-family/games/<slug>`) are **hardcoded in the React front-end** —
they 404 on the CMS API. The React bundle also already reads a set of character fields from the CMS
and falls back to hardcoded data because the doctype lacked them. This round makes the CMS the source
of truth by adding those fields and rebuilding content to match the live data (extracted verbatim
from the bundle). **Most of it is enablement** — it renders on the live site only after the React
team switches those pages from hardcoded → CMS.

### Done in the CMS (this round)
- **`character` doctype** — added 6 fields React already reads: `characterCategory` (Moo Family /
  Cow Paradise), `characterTraits` (comma-separated), `characterPersonality`, `characterTakeaway`
  (the "Children learn that…" line), `characterLearnIntro`, and `characterLearnPoints` (a BlockList
  of accordion items = `accordionTitle` + `accordionContent`).
- **Characters rebuilt to the live 12** (was 6): Moo Family — `little-jack, daddy-moo, mommy-moo,
  milo, bella, daisy`; Cow Paradise — `rocky, coco, zara, pepe, luna, toby`. Node names match the
  live slugs, so `/characters/daddy-moo` etc. are now **real CMS nodes**. All fields populated from
  the live data. `characterImage` left empty (see assets note).
- **`educationalGameCard` doctype** — added `eduGameCardCategory` and `eduGameCardSlug`; tagged all 8
  cards (one per category: Alphabet/Words/Spelling/Reading/Writing/Numbers/Brain Games/Creativity).
- **Game rules** — added a **"How to Play"** section (id `how-to-play`) into each of the 12
  `game.blocks` with per-genre rules. This one **renders now** (React already renders `game.blocks`).

### React work required to make the rest render (hand-off)
1. **Characters page + detail:** switch `/characters` and `/characters/<slug>` from the hardcoded
   array to the CMS `character` nodes (match by node slug/id, CMS-primary). Read the new fields:
   `characterCategory`, `characterTraits` (string → split on comma), `characterPersonality`,
   `characterTakeaway`, `characterLearnIntro`, and `characterLearnPoints.items[].content.properties`
   (`accordionTitle` → title, `accordionContent` → body). Wire the "All / Moo Family / Cow Paradise"
   chips to `characterCategory`.
2. **Educational games:** wire the category chips on `/moo-family` to `eduGameCardCategory`, and add
   the `/moo-family/games/<slug>` detail route reading `eduGameCardSlug` (detail content model TBD).
3. **Character "Adventures" carousel** (related games/stories per character) needs a
   character→games/stories relationship — not modelled yet; add a picker/relation field if wanted.

### Notes / limitations
- **Character images:** the live art are React static assets (`/images/character_*.png`), not CMS
  media, so `characterImage` stays empty until uploaded in the backoffice (or React keeps its own
  `/images/*` paths). Same for edu-game icons.
- The old CMS characters (Moo, Ellie, Lulu, Tina) were repurposed onto the new nodes by reusing their
  keys, so no orphan nodes remain; the old `/characters/{moo,ellie,lulu,tina}` slugs no longer exist.

---

## Round 3 — Educational games as real pages + governed categories + character relations + first-class rules

**Why:** Round 2 left the educational games as hardcoded/placeholder *cards* with no CMS route
(`/moo-family/games/<slug>` 404'd), the category fields as free text (so chip filtering couldn't
bind), no character→games/stories relationship, and game rules buried inside `game.blocks`. This
round makes those real in the CMS.

### Done in the CMS (this round)
- **New `educationalGame` doctype** (routable, IsElement=false) + **`educationalGamesFolder`** container,
  nested under the Moo Family node so nodes route at **`/moo-family/games/<slug>`**. Fields:
  `eduGameTitle`, `eduGameDescription`, `eduGameCategory` (governed dropdown), `eduGameCoverImage`,
  `eduGameIcon`, `eduGameBackgroundColor`, `eduGameHowToPlay` (RichText), `eduGameAgeRange`,
  `eduGameSkills`, `eduGamePlayUrl`, `blocks` (shared page-block palette). Slug = node URL segment.
- **8 educationalGame nodes seeded** under `/moo-family/games/` (Alphabet Adventure, Word Sprint,
  Number Garden, Brain Boost, Spelling Bee, Story Explorer, Doodle & Write, Color Studio). *These are
  placeholders carried over from the old cards — replace with the real catalog (e.g. `alphabet-adventures`,
  `abc-puzzles`) when provided.* Images left empty (backoffice upload).
- **Moo Family page** — the `educationalGamesSection` block was replaced by an **`entityGridSection`**
  (auto mode, `entityGridEntityType=["educationalGame"]`, 8 category chips) so the listing auto-sources
  the new nodes. Chip `filterChipValue`s are now the exact Title-Case category labels.
- **Governed category dropdowns** — new `Character - Category - Dropdown` (Moo Family / Cow Paradise)
  and `Educational Game - Category - Dropdown` (Alphabet/Words/Spelling/Reading/Writing/Numbers/Brain
  Games/Creativity). `character.characterCategory`, `educationalGameCard.eduGameCardCategory`, and
  `educationalGame.eduGameCategory` now use them; the 12 character values were rewritten to array form
  (`["Moo Family"]` / `["Cow Paradise"]`). `educationalGame` added to `EntityTypeDropdown`.
- **Character → related content** — added `characterRelatedGames` (Game picker) and
  `characterRelatedStories` (Story picker) MNTP fields on `character` (empty by default; populate to
  drive the per-character "Adventures" carousel).
- **Game rules promoted** — new first-class `gameHowToPlay` (RichText) on `game`; the "How to Play"
  block was migrated out of `game.blocks` into this field and removed from all 12 game nodes (so it no
  longer renders as a duplicated section).
- **Delivery API** — `educationalGame` + `educationalGamesFolder` added to `AllowedContentTypeAliases`
  in `appsettings.json` (base file only; Dev/Prod inherit — do not add a partial array there).

### React work required to make the rest render (hand-off)
1. **Educational game detail:** add the `/moo-family/games/<slug>` route. Resolve by Delivery API route
   (`/umbraco/delivery/api/v2/content/item/moo-family/games/<slug>`) or `filter=contentType:educationalGame`
   + match the node's URL segment (slug is the route segment, **not** a field). Render `eduGameTitle`,
   `eduGameDescription`, `eduGameCoverImage`, `eduGameIcon`, `eduGameBackgroundColor`, `eduGameHowToPlay`
   (HTML), `eduGameAgeRange`, `eduGameSkills` (split on `,`), `eduGamePlayUrl`, and `blocks` (same block
   renderer as `game`).
2. **Moo Family listing:** the educational section is now an `entityGridSection` (was
   `educationalGamesSection`). Reuse the same grid renderer as `/games` and `/characters`: auto-source
   `entityGridEntityType[0] === "educationalGame"`, render the 8 `entityGridFilters` chips, filter by
   exact label (`eduGameCategory[0] === filterChipValue`, no lowercasing).
3. **Characters:** bind the new `characterRelatedGames` / `characterRelatedStories` MNTP arrays (link to
   `/games/<slug>` and `/stories/<slug>`); read category from `characterCategory[0]`.
4. **Game rules:** read the new `gameHowToPlay` (HTML) instead of the former `how-to-play` block (now
   removed from `game.blocks`). Same field shape as `eduGameHowToPlay`.

### Parsing notes
- `Umbraco.DropDown.Flexible` fields return a JSON **array** (`eduGameCategory`, `characterCategory`,
  `entityGridEntityType`/`SourceMode`/`Layout`) — read `[0]`.
- New aliases the front-end must handle: `educationalGame`, `educationalGamesFolder`.

---

## Round 4 — Game platform links + News section to match Figma

### Done in the CMS (this round)
- **`game.gamePlatformLinks`** — new Block List of `gamePlatformLink`
  (`platformName` governed dropdown, `platformLabel`, `platformUrl`, `platformIcon`). Seeded on all
  12 games, one row per value already in that game's `gamePlatforms`. `gamePlatforms` is unchanged and
  remains the filterable taxonomy field; the new Block List is presentation only.
- **6 platform icons** as media — Epic Games / Apple App Store / Google Play / Browser / PC as
  `umbracoMediaVectorGraphics`, Steam as a 64px `Image`. New `Icon Media Picker (Image or SVG)`
  DataType, since the standard `Image Media Picker` filters to the Image type and cannot see SVGs.
- **`newsArticle`** gained `newsTags`, `newsRelatedArticles` (reuses the existing News Article Content
  Picker) and `newsBodyBlocks` (heading + coloured-bullet sections + inline images, rendered *after*
  the `newsBody` rich text).
- **News categories** — the six Figma categories were **appended** to `News - Category - Dropdown`
  (now 11). Editors add more in Settings → Data Types; a new save guard blocks removing an item that
  is still assigned to content. The listing's filter chips were extended to match.
- **3 Figma articles seeded** — "Guide to Understanding Children Development Stages" (full detail page,
  5 body sections + inline image), plus the two sidebar "Latest Articles". Tags backfilled on the
  existing 6 so every card badge in the design has a value.
- **Delivery API property filtering built** — stock Umbraco only filters on `contentType`/`name`/
  `createDate`/`updateDate`; everything else 400s. Three handlers in `src/MooFamily.Cms.Web/DeliveryApi/`
  now make `newsCategory`, `newsTags`, `newsPublishedDate`, `gamePlatforms`, `gameStatus`, `gameGenre`,
  `gameIsFeatured`, `storyCategory`, `storyTags`, `shortCategory`, `characterCategory` and
  `eduGameCategory` genuinely queryable. **Requires an Examine index rebuild after deploy.**
- **Synced `deploy/apprunner-config.json`** — it was missing `educationalGame` /
  `educationalGamesFolder` (indices 15/16) that `appsettings.json` has.
  **This was *not* a live bug**, contrary to the initial read: .NET config providers overlay
  per-key, so the env vars only override indices 0–14 and 15/16 still come from `appsettings.json`.
  Verified against production after deploy — `?filter=contentType:educationalGame` returns
  **8 items**. The file is a documentation mirror, so it is now accurate, but no
  `aws apprunner update-service` is needed.

### 🐞 Found while verifying — Moo Tag's cover image is broken (pre-existing, NOT fixed)

`Media/Moo_Tag_Cover.config` has the key `0eb2aa47-be1d-7d44-9022-1b6469750757` — a **version 7**
GUID. Umbraco's `IMediaPathScheme` rejects v7 media keys, so the media item fails to import and
`moo-tag`'s `gameCoverImage` comes back **null** from the Delivery API. Verified locally:

```
GET /content/item/games/moo-tag/?expand=properties[$all]   -> gameCoverImage: null
GET /content/item/games/cow-run/?expand=properties[$all]   -> /media/e3b3.../cowrun.webp
```

Root cause is the same `New-DeterministicGuid` byte-order bug described in
`scripts/assets/platform-icons/README.md` — `backfill-media.ps1` forces the version nibble into
`$bytes[6]`, but `[Guid]::new(byte[])` reads Data3 little-endian so the version comes from
`$bytes[7]`. Of the 28 original media keys, exactly one happened to land on v7.

**Left unfixed — it is a separate defect and needs a decision.** The fix is small:
1. Change the key in `Media/Moo_Tag_Cover.config` to a v4 value (e.g. `0eb2aa47-be1d-4d44-9022-1b6469750757`
   — flipping only the version nibble keeps it recognisable).
2. Leave `umbracoFile`'s `src` pointing at the existing S3 folder so **no binary has to move**.
3. Update the `mediaKey` in `Content/Home/Games/MooTag.config`'s `gameCoverImage`.
4. Re-import Content + Media.

### ⏳ Remaining — needs the team
- **Real store URLs.** Only 2 of 21 platform rows have one: Cow Run → Browser (its details page) and
  Paintball Madness → PC (its real Steam listing). The other 19 point at `/market`, matching the
  existing decision for unreleased titles. Replace as each store listing goes live.
- **Steam icon source.** The design export is a 659×659 base64 PNG wrapped in `<svg>` — not a vector.
  It is stored as a 64px PNG instead. Drop a genuine vector at
  `scripts/assets/platform-icons/steam-source.svg` and run
  `pwsh scripts/backfill-game-platforms.ps1 -RasteriseOnly`, or supply a real `steam.svg` and switch
  that row to `MediaType='svg'`. **The Steam icon is currently unreferenced** — no game lists Steam
  in `gamePlatforms` (see the Paintball note below).
- **Browser / PC icons** are neutral placeholder glyphs drawn in-repo. Replace
  `scripts/assets/platform-icons/{browser,pc}.svg` with brand assets and re-run the backfill; the
  media keys do not change.
- **Two platform/URL contradictions**, deliberately *not* auto-corrected:
  - Cow Run's `gamePlayUrl` is a Google Play link, but its `gamePlatforms` is `["Browser","PC"]` —
    Google Play is not listed, so no platform row carries that link.
  - Paintball Madness ships on **Steam** but its `gamePlatforms` says `["PC"]`. The Steam URL is
    attached to the PC row. Retagging it would let the Steam badge render.
- **Hero images for the 3 new articles** reuse existing news heroes so the pages render. Swap in the
  real Figma exports.
- **Body copy for sections 3–5** of "Children Development Stages". The Figma repeats section 2's
  placeholder text verbatim for the last three sections; genuine copy was written instead. Replace
  with final copy when the content team supplies it.
- **Sidebar category counts** are derived from the real article count, not the Figma numbers
  (120 / 100 / 80 / 60 / 110 / 40). Those are design placeholders — there is nowhere to author a count
  against a dropdown item, and there are 9 articles. Confirm the real numbers are acceptable.
- **12 filter chips** is a wide row on mobile. Design call.
- **S3 upload not run.** `scripts/backfill-game-platforms.ps1` was run with `-SkipUpload`, so the repo
  has the media XML but the binaries are not in S3 yet. Run it without that flag (needs AWS creds)
  before the icons will resolve.

### Deploy status (as at commit `e8728a4`)

| Step | State |
|---|---|
| Icons uploaded to S3 (`image/svg+xml`) | ✅ done — 5 of 6; Steam skipped, no source vector |
| Pushed to `master`, cms-deploy workflow | ✅ succeeded |
| App Runner rolled out the new image | ✅ succeeded |
| **Schema** live in production | ✅ `gamePlatformLinks`, `newsTags`, `newsRelatedArticles`, `newsBodyBlocks` all present on the production doctypes |
| Custom filter/sort handlers live | ✅ `?filter=newsCategory:Events` → 200 (was 400); unregistered `gameTitle` still 400s |
| **Content + Media import** | ⛔ **not done — needs a decision, see below** |
| Examine index rebuild | ⛔ not done — needed before `newsTags` / `gamePlatforms` filters return rows |

### ⚠️ Production content has diverged badly from the repo — read before importing

Live production vs `uSync/v17/Content/`:

| Type | Live | Repo | Delta |
|---|---|---|---|
| `game` | **3** (Cow Run, Moo Rash, Paintball Madness) | 12 | +9 |
| `newsArticle` | **5** | 9 | +4 |
| `educationalGame` | 8 | 8 | — |
| `story` | 8 | 8 | — |
| `character` | 8 | 8 | — |

A full uSync Content import would **create 9 games and 4 news articles** in production and
**overwrite** whatever editors have changed on the 3 live games and 5 live articles. That is a
large content change, not a schema top-up. Until it runs, `gamePlatformLinks` is `null` on every
live game and the new news fields are empty — the schema is there, the values are not.

Recommended order when you do run it:
1. Snapshot the production database.
2. Settings → uSync → Import, **Content and Media handlers only** (never a full import).
3. Settings → Examine Management → `DeliveryApiContentIndex` → **Rebuild**.
4. Re-check `?filter=contentType:game&filter=gamePlatforms:Browser` returns rows.

If the 9 missing games were deliberately removed, do **not** import Content — instead delete them
from `uSync/v17/Content/Home/Games/` so the repo stops disagreeing with production.

`python scripts/validate-usync-json.py` before committing any further content edits.

### Parsing notes
- `newsTags` is a JSON **array** (`Umbraco.DropDown.Flexible`, multiple) — read the whole array, not `[0]`.
  Values are stored **without** a leading `#`.
- `newsBodySectionBarColor` is an **object** `{ value, label }`, not a string — same as
  `gameInFeatureBackgroundColor`. Both fields hold the hex **without** `#` (e.g. `e4572e`),
  so read `.value` and prepend `#`.
- `platformIcon` may be an `Image` **or** a `umbracoMediaVectorGraphics` item. SVGs return
  `width: null` / `height: null` and ignore ImageSharp resize params — size them in CSS.
- `newsRelatedArticles` may include the current article; Umbraco's picker cannot exclude self.
