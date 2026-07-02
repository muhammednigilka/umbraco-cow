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
