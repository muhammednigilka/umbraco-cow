# Headless CMS Integration Guide — React + Umbraco Delivery API

> **Audience:** Any React developer connecting a frontend to the deployed Moo Family Umbraco CMS.
> **Self-contained.** Live URLs, live response samples, copy-paste code. No prior CMS or Umbraco knowledge required.

**Last updated:** 2026-05-29
**CMS:** Umbraco 17.4.0 (App Runner)
**API:** Umbraco Delivery API v2
**Live base URL:** `https://3b2umvhdys.us-east-1.awsapprunner.com`

---

## Table of contents

1. [TL;DR — 5-minute quick start](#1-tldr--5-minute-quick-start)
2. [Architecture](#2-architecture)
3. [API basics](#3-api-basics)
4. [Content model — what's in the CMS](#4-content-model--whats-in-the-cms)
4a. [Home page — section-by-section inventory](#4a-home-page--section-by-section-inventory)
5. [React project setup](#5-react-project-setup)
6. [The client library](#6-the-client-library)
7. [TypeScript types](#7-typescript-types)
8. [React hooks](#8-react-hooks)
9. [Media URLs (important)](#9-media-urls-important)
10. [Rich text rendering](#10-rich-text-rendering)
11. [Block list rendering](#11-block-list-rendering)
12. [Page-by-page integration recipes](#12-page-by-page-integration-recipes)
13. [SEO metadata](#13-seo-metadata)
14. [Caching, ISR, and freshness](#14-caching-isr-and-freshness)
15. [Error handling](#15-error-handling)
16. [Editor preview](#16-editor-preview)
17. [Troubleshooting](#17-troubleshooting)
18. [Cheat sheet — every URL you'll ever use](#18-cheat-sheet--every-url-youll-ever-use)

---

## 1. TL;DR — 5-minute quick start

Drop these in your Vite/CRA React project and you'll be reading content in under five minutes.

### Step 1 — Add environment variables

Create `.env` (or `.env.local`) at the root of your React app:

```bash
VITE_CMS_BASE_URL=https://3b2umvhdys.us-east-1.awsapprunner.com
VITE_CMS_API_KEY=Yvq69J37e5KCOzVUuleG7wRkDMA6krJdMwlFvW7Z84aHuAzF
```

Then add `.env.local` to `.gitignore` (this key gives read-only access but should not be in source control).

> **CRA users:** rename keys to `REACT_APP_CMS_BASE_URL` etc. and use `process.env.REACT_APP_*`.

### Step 2 — Create the client

`src/lib/cms.ts`:

```ts
const BASE = import.meta.env.VITE_CMS_BASE_URL;
const KEY  = import.meta.env.VITE_CMS_API_KEY;

export async function cms<T = unknown>(path: string, init?: RequestInit): Promise<T> {
  const url = `${BASE}/umbraco/delivery/api/v2${path}`;
  const res = await fetch(url, {
    ...init,
    headers: {
      "Api-Key": KEY,
      Accept: "application/json",
      ...init?.headers,
    },
  });
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`CMS ${res.status} on ${path}: ${body.slice(0, 200)}`);
  }
  return res.json();
}

export const mediaUrl = (relativeUrl: string | undefined): string => {
  if (!relativeUrl) return "";
  if (relativeUrl.startsWith("http")) return relativeUrl;
  return `${BASE}${relativeUrl}`;
};
```

### Step 3 — Use it

```tsx
import { useEffect, useState } from "react";
import { cms, mediaUrl } from "./lib/cms";

export function GamesPreview() {
  const [games, setGames] = useState<any[]>([]);
  useEffect(() => {
    cms<{ items: any[] }>("/content?filter=contentType:game&expand=properties[$all]")
      .then((d) => setGames(d.items));
  }, []);
  return (
    <ul>
      {games.map((g) => (
        <li key={g.id}>
          <img src={mediaUrl(g.properties.gameCoverImage?.[0]?.url)} alt={g.name} width={160} />
          <h3>{g.properties.gameTitle}</h3>
          <p>{g.properties.gameDescription}</p>
        </li>
      ))}
    </ul>
  );
}
```

You're done. The rest of this document is depth — types, hooks, block rendering, all content types, caching, troubleshooting.

---

## 2. Architecture

```
┌─────────────────────┐   HTTPS         ┌─────────────────────┐
│  React app          │ ───────────────▶│  Umbraco CMS        │
│  (Vite / Next /     │  GET /umbraco/  │  (App Runner)       │
│   CRA / Amplify)    │   delivery/api  │                     │
│                     │ ◀───────────────│  - SQL Server (RDS) │
│  - fetches JSON     │ application/json│  - S3 media         │
│  - renders UI       │                 │  - Delivery API v2  │
└─────────────────────┘                 └─────────────────────┘
                                                │
                                                ▼
                                        ┌───────────────┐
                                        │ S3 media URLs │
                                        │ (proxied via  │
                                        │  CMS)         │
                                        └───────────────┘
```

**Editor flow:** Edit content in `/umbraco` backoffice → save → it's instantly available to the React app on the next fetch (no rebuild, no deploy).

---

## 3. API basics

### Base URL

```
https://3b2umvhdys.us-east-1.awsapprunner.com
```

All API paths are prefixed with `/umbraco/delivery/api/v2`.

### Authentication

Every request needs this header:

```
Api-Key: Yvq69J37e5KCOzVUuleG7wRkDMA6krJdMwlFvW7Z84aHuAzF
```

If you omit it you get `401 Unauthorized`. The key is read-only for content delivery.

### CORS

The CMS currently allows requests from:

- `https://master.d3boy6qi81n9oz.amplifyapp.com` (Amplify preview)
- `https://cowparadisegames.com`
- `https://www.cowparadisegames.com`

For local dev (e.g. `http://localhost:5173`), ask the maintainer to add your origin to the App Runner `Cors__AllowedOrigins` env var, or temporarily run a small dev proxy (see [§17 Troubleshooting](#17-troubleshooting)).

### Two endpoint families

| Family | Returns | Use when |
|---|---|---|
| `/content?<filters>` | A *list* — `{ total, items: [...] }` | You want many items, filtered/sorted/paginated |
| `/content/item/<path>` | A *single object* | You know the exact URL slug of one node |

### Query operators

| Operator | Example | Meaning |
|---|---|---|
| `filter=contentType:X` | `filter=contentType:game` | Only items of that content type |
| `filter=propertyAlias:value` | `filter=gameIsFeatured:true` | Property matches value (string / bool / int) |
| `filter=name:contains:"x"` | `filter=name:contains:"Cow"` | Substring match (Umbraco docs: `contains`, `startsWith`, `endsWith`) |
| `sort=propertyAlias:asc\|desc` | `sort=newsPublishedDate:desc` | Order results |
| `take=N` | `take=50` | Page size (default 10, max 100) |
| `skip=N` | `skip=20` | Skip N items (for pagination) |
| `expand=properties[$all]` | always include | Expand all properties (without it you only get id/name/route) |
| `fields=properties[a,b]` | `fields=properties[gameTitle,gameCoverImage]` | Return only specific properties (smaller payload) |

You can chain filters — they're ANDed:

```
?filter=contentType:newsArticle&filter=newsCategory:Stories%20%26%20Learning&sort=newsPublishedDate:desc
```

(Note: `&` in values is URL-encoded as `%26`.)

### Pagination

```ts
const PAGE = 12;
const page1 = await cms(`/content?filter=contentType:story&take=${PAGE}&skip=0&expand=properties[$all]`);
const page2 = await cms(`/content?filter=contentType:story&take=${PAGE}&skip=${PAGE}&expand=properties[$all]`);
// `total` in the response tells you how many pages exist
const totalPages = Math.ceil(page1.total / PAGE);
```

---

## 4. Content model — what's in the CMS

There are **9 content types** you'll actually consume from the API, plus 5 folders and 16 block element types.

### Top-level pages (singletons)

| Content type | URL | Purpose |
|---|---|---|
| `home` | `/` | Homepage with hero, blocks, stats |
| `standardPage` | `/about/`, `/moo-family/`, `/privacy-policy/`, etc. | Generic content pages with block list |
| `settings` | (hidden, fetch by alias) | Global site settings (footer text, links, etc.) |

### Entity types (lists)

| Content type | Folder URL | Count |
|---|---|---|
| `game` | `/games/` | 12 games (Cow Run, Moo Chess, etc.) |
| `story` | `/stories/` | 8 stories |
| `newsArticle` | `/news/` | 6 articles |
| `character` | `/characters/` | 6 Moo Family characters |
| `teamMember` | `/team/` | 5 team members |
| `short` | `/shorts/` | YouTube shorts |

### Property aliases per type

This is what comes back in `properties` for each content type. Aliases are camelCase strings used in filters and code.

**`game`**
```
gameTitle: string                  // "COWRUN"
gameDescription: string            // free-text
gameCoverImage: MediaItem[]        // array, use [0]
gameStatus: string                 // "Released" | "In Development" | ...
gamePlatforms: string[]            // ["Browser", "PC"]
gameGenre: string                  // "Racing"
gameNumPlayers: string             // "Single Player"
gamePlayUrl: string                // external link
gameDetailsUrl: string             // canonical page URL
gameIsFeatured: boolean
```

**`story`**
```
storyTitle: string
storyDescription: string
storyThumbnail: MediaItem[] | null
storyVideoUrl: string              // YouTube URL
storyDuration: number              // seconds
storyTags: string[]
storyCategory: string              // "Quick Learning Stories" | ...
```

**`newsArticle`**
```
newsTitle: string
newsExcerpt: string
newsBody: RichText                 // { markup, blocks }
newsHeroImage: MediaItem[]
newsPublishedDate: string          // ISO date
newsCategory: string               // "Stories & Learning" | "Game Updates" | ...
```

**`character`**
```
characterName: string
characterRole: string              // "Curious Kid"
characterImage: MediaItem[]
characterDescription: string
characterAccentColor: string       // hex, e.g. "#3FBDF1"
```

**`teamMember`**
```
memberName: string
memberRole: string                 // "CEO", "Designer", ...
memberPhoto: MediaItem[]
memberBio: string
```

**`home` / `standardPage`**
```
title: string
metaDescription: string
heroImage: MediaItem[] | null
blocks: BlockList                  // see §11
```

**`settings`**
```
(custom global settings — fetch via /content/item/settings)
```

### Block types (used inside `blocks` on home/standardPage)

These appear inside `block.content.contentType`:

| Alias | Purpose | Key properties |
|---|---|---|
| `heroBanner` | Big banner | `bannerTitle, bannerSubtitle, bannerBody, bannerBackgroundImage, ctaPrimaryLabel/Url, ctaSecondaryLabel/Url` |
| `headingBlock` | A heading | `headingText, headingLevel` (`h1`–`h6`) |
| `richTextBlock` | Rich text content | `content: { markup, blocks }` |
| `statBlock` | Big stat number | `statValue, statLabel, statIcon` |
| `featureCard` | Numbered feature | `featureNumber, featureTitle, featureDescription, featureIcon` |
| `timelineItem` | Timeline entry | `timelineYear, timelineTitle, timelineDescription, timelineIcon` |
| `accordionItem` | Collapsible | `title, body` |
| `bulletList` | Bullets | items |
| `ctaBlock` | Single CTA | `label, url, style, openInNewTab` |
| `imageBlock` | Single image | image |
| `videoBlock` | Embedded video | `videoUrl, videoCaption` |
| `youTubeBlock` | YouTube embed | `youtubeUrl` |
| `playStoreBlock` | Play Store badge | `playStoreUrl` |
| `newsletterSignup` | Signup form | `newsletterTitle, newsletterDescription, newsletterCtaLabel, newsletterPlaceholder` |
| `logoStrip` | Logo carousel | list of `logoStripItem` |

---

## 4a. Home page — section-by-section inventory

This section catalogs every component on the live home page at https://cowparadisegames.com/ (snapshot 2026-05-29) and maps it to the CMS block (or data-driven fetch) that drives it. Read top-to-bottom in render order — this matches what the editor sees in the backoffice block list on the Home node.

**Total blocks on home node:** 24. **Data-driven sections layered on top:** 3 (Trending Games grid, Characters grid, Game Shorts grid).

### Header (out of scope of home block list)

Navigation (`Home / Games / Stories / Moo Family / About Us / Market / News / LOGIN`) is rendered by React routing — not stored in the home node. If you want it CMS-driven later, it belongs on the `settings` singleton, not here.

### Block list (in render order)

| # | Live section | CMS block | Verbatim values |
|---|---|---|---|
| 1 | **Hero banner** — tropical scene with overlay text. Eyebrow "Become a Cow Paradise" sits above the main headline "Where Games Become a Universe". Two CTAs below. | `heroBanner` | `bannerSubtitle` = "Become a Cow Paradise" · `bannerTitle` = "Where Games Become a Universe" · `bannerBody` = "We're building a playful universe filled with stories, adventures, and unforgettable characters. Play, learn, and grow with the Moo Family." · `bannerBackgroundImage` = *(media TBD — see Media assets below)* · `ctaPrimaryLabel` / `ctaPrimaryUrl` = "Explore Games" / `/games` · `ctaSecondaryLabel` / `ctaSecondaryUrl` = "Meet the Moo Family" / `/moo-family` |
| 2 | "What is Cow Paradise?" section heading | `headingBlock` | `headingText` = "What is Cow Paradise?" · `headingLevel` = `h2` |
| 3 | Intro paragraph beneath the heading | `richTextBlock` | "At Cow Paradise, we're creating more than just games -- we're building a playful universe filled with stories, adventures, and unforgettable characters." |
| 4 | Stat tile #1 | `statBlock` | `statValue` = "100+" · `statLabel` = "Kids Learning with Playing" |
| 5 | Stat tile #2 | `statBlock` | `statValue` = "20+" · `statLabel` = "Games" |
| 6 | Stat tile #3 | `statBlock` | `statValue` = "10+" · `statLabel` = "Years of Experience" |
| 7 | Stat tile #4 | `statBlock` | `statValue` = "95%" · `statLabel` = "Parents Satisfaction" |
| 8 | "Know more" CTA under the stats | `ctaBlock` | `label` = "Know more" · `url` = `/about` · `style` = `primary` · `openInNewTab` = `false` |
| 9 | Moo Family group illustration (right column of this section) | `imageBlock` | `image` = *(media TBD)* · `altText` = "The Moo Family characters together" · `caption` = "" |
| 10 | Three overlaid checkmark labels next to the illustration | `bulletList` | `bulletListTitle` = "" · `bulletItems` = `["Empower Creativity", "Foster Growth", "Build Community"]` |
| 11 | "Explore Trending Games" heading | `headingBlock` | `headingText` = "Explore Trending Games" · `headingLevel` = `h2` |
| 12 | Trending games subtitle | `richTextBlock` | "Teaming up with industry leaders to build the ultimate gaming universe." |
| 13 | "Featured Characters" heading | `headingBlock` | `headingText` = "Featured Characters" · `headingLevel` = `h2` |
| 14 | Featured characters intro paragraph | `richTextBlock` | "Meet the Moo Family -- six friendly characters who lead every story. Each brings a unique perspective on curiosity, kindness, and play." |
| 15 | "Browse Characters" CTA | `ctaBlock` | `label` = "Browse Characters" · `url` = `/moo-family` · `style` = `primary` |
| 16 | "Where Adventure Comes to Life" heading | `headingBlock` | `headingText` = "Where Adventure Comes to Life" · `headingLevel` = `h2` |
| 17 | Adventure video section body | `richTextBlock` | "In Cow Paradise, stories unfold across tropical islands, hidden treasures, and vibrant digital realms. It's a world filled with charm, creativity, and opportunity -- where players discover lovable characters, complete exciting challenges, and collect unique items that shape their identity. More than just a game, Cow Paradise is a universe built to grow with its community." |
| 18 | Video player with circular "Adventures" play button | `videoBlock` | `videoUrl` = *(TBD — placeholder empty until real video uploaded)* · `videoPosterImage` = *(media TBD)* · `videoCaption` = "Adventures" |
| 19 | "Game Shorts" heading | `headingBlock` | `headingText` = "Game Shorts" · `headingLevel` = `h2` |
| 20 | Shorts subtitle | `richTextBlock` | "Jump into the Moo Family's world and enjoy tiny adventures full of fun and wonder. Short, sweet, and always a little magical!" |
| 21 | "View more Stories" CTA below the shorts grid | `ctaBlock` | `label` = "View more Stories" · `url` = `/stories` · `style` = `primary` |
| 22 | Partner strip subtitle (sits above the logos on the live page) | `richTextBlock` | "Teaming up with industry leaders to build the ultimate gaming universe." |
| 23 | Partner logo carousel with section title "Powered by the Best in Gaming" | `logoStrip` (with nested `logoStripItem` block list, see below) | `logoStripTitle` = "Powered by the Best in Gaming" · `logoStripItems` = 6 entries |
| 24 | Newsletter signup ("Stay in the loop") that sits just above the footer | `newsletterSignup` | `newsletterTitle` = "Stay in the loop" · `newsletterDescription` = "Get a short email when we ship a new game, character, or story. No spam -- ever." · `newsletterCtaLabel` = "Subscribe for New Stories" · `newsletterPlaceholder` = "Enter your email" |

#### Nested logo strip items (block 23)

The `logoStripItems` property on block 23 is itself a nested Umbraco BlockList containing 6 `logoStripItem` entries — same shape as a top-level block list. Order matches the live carousel left-to-right:

| Item | `logoName` | `logoUrl` | `logoImage` |
|---|---|---|---|
| 1 | Steam | https://store.steampowered.com/ | *(media TBD)* |
| 2 | Epic Games | https://store.epicgames.com/ | *(media TBD)* |
| 3 | Immutable | https://www.immutable.com/ | *(media TBD)* |
| 4 | Unreal | https://www.unrealengine.com/ | *(media TBD)* |
| 5 | BGA | https://blockchaingamealliance.org/ | *(media TBD)* |
| 6 | Steam | https://store.steampowered.com/ | *(media TBD)* |

> Steam appears twice intentionally — that's how the live carousel renders (visual padding at the strip's end).

### Data-driven sections (NOT in the block list)

Three visible page sections are rendered by fetching content types directly, not by reading blocks. The headings, subtitles, and CTAs above/below each grid ARE block-driven (rows 11–12, 13–15, 19–21 above); only the *card grid itself* is data-driven.

| Section | Fetch URL | Notes |
|---|---|---|
| Trending Games grid (3 cards) | `/content?filter=contentType:game&filter=gameIsFeatured:true&take=3&expand=properties[$all]` | Renders between blocks 12 and 13. Falls back to first 3 games sorted by `name:asc` if fewer than 3 are featured. |
| Characters grid (6 cards) | `/content?filter=contentType:character&take=6&expand=properties[$all]` | Renders between blocks 15 and 16. Use `characterAccentColor` as the card backdrop. |
| Game Shorts grid (4 cards) | `/content?filter=contentType:short&take=4&expand=properties[$all]` | Renders between blocks 20 and 21. Embed YouTube via `shortYoutubeId`. |

### Media assets required

The home page references 4 media slots that have no value populated yet. Until a content editor uploads these via the backoffice, the affected sections will render with empty images:

1. **Hero banner background** — `heroBanner.bannerBackgroundImage` (block 1). Tropical beach / paradise scene.
2. **Moo Family group illustration** — `imageBlock.image` (block 9). Character ensemble for the "What is Cow Paradise?" section.
3. **Video poster image** — `videoBlock.videoPosterImage` (block 18). Tropical scene used as the play-button thumbnail.
4. **6 partner logos** — `logoStripItem.logoImage` on each of the 6 nested items in block 23 (Steam, Epic Games, Immutable, Unreal, BGA, Steam).

The `videoBlock.videoUrl` (block 18) also needs the real video URL once available.

### Hero overlay note

The hero block stores the overlay in two fields, rendered as eyebrow above main heading:

```
[bannerSubtitle — small, faded]   "Become a Cow Paradise"
[bannerTitle    — large, primary] "Where Games Become a Universe"
[bannerBody     — paragraph]      "We're building a playful universe..."
```

The previously seeded `bannerSubtitle` was "Welcome to Cow Paradise" — that was wrong and has been corrected to match the live overlay. If you're updating the editor docs or design system, treat `bannerSubtitle` as the eyebrow/kicker, not the page title.

---

## 5. React project setup

### 5.1 Install (no new deps required)

The integration uses native `fetch` and React hooks. **Zero new packages required.** If you want better DX:

```bash
# optional but recommended
npm i swr           # data fetching with cache + revalidation
# or
npm i @tanstack/react-query   # heavier but richer
```

### 5.2 Environment variables

**Vite** (`vite.config.ts` projects):

```bash
# .env.local
VITE_CMS_BASE_URL=https://3b2umvhdys.us-east-1.awsapprunner.com
VITE_CMS_API_KEY=Yvq69J37e5KCOzVUuleG7wRkDMA6krJdMwlFvW7Z84aHuAzF
```

Reference: `import.meta.env.VITE_CMS_BASE_URL`

**Create React App:**

```bash
# .env.local
REACT_APP_CMS_BASE_URL=https://3b2umvhdys.us-east-1.awsapprunner.com
REACT_APP_CMS_API_KEY=Yvq69J37e5KCOzVUuleG7wRkDMA6krJdMwlFvW7Z84aHuAzF
```

Reference: `process.env.REACT_APP_CMS_BASE_URL`

**Next.js (App Router):**

```bash
# .env.local
NEXT_PUBLIC_CMS_BASE_URL=https://3b2umvhdys.us-east-1.awsapprunner.com
NEXT_PUBLIC_CMS_API_KEY=Yvq69J37e5KCOzVUuleG7wRkDMA6krJdMwlFvW7Z84aHuAzF
# Or, for server-side only (recommended for security):
CMS_API_KEY=Yvq69J37e5KCOzVUuleG7wRkDMA6krJdMwlFvW7Z84aHuAzF
```

> **Important:** anything `VITE_*`, `REACT_APP_*`, or `NEXT_PUBLIC_*` is **bundled into the public JS** and visible to anyone with devtools. The Delivery API key is read-only so this is acceptable, but if you ever rotate it to a write-capable key, fetch only from a server / Next.js Route Handler.

### 5.3 Folder layout

```
src/
  lib/
    cms.ts             # the client (§6)
    cmsHooks.ts        # React hooks (§8)
    cmsTypes.ts        # TypeScript types (§7)
    mediaUrl.ts        # media helpers (§9)
  components/
    BlockRenderer.tsx  # block list rendering (§11)
    blocks/
      HeroBanner.tsx
      HeadingBlock.tsx
      RichTextBlock.tsx
      StatBlock.tsx
      ...
  pages/
    Home.tsx
    Games.tsx
    GameDetail.tsx
    News.tsx
    NewsDetail.tsx
    Stories.tsx
    About.tsx
```

---

## 6. The client library

`src/lib/cms.ts`:

```ts
const BASE: string = import.meta.env.VITE_CMS_BASE_URL;
const KEY: string  = import.meta.env.VITE_CMS_API_KEY;

if (!BASE) throw new Error("VITE_CMS_BASE_URL is not set");

/** Low-level fetch. All higher-level helpers go through this. */
export async function cms<T = unknown>(path: string, init?: RequestInit): Promise<T> {
  const url = `${BASE}/umbraco/delivery/api/v2${path}`;
  const res = await fetch(url, {
    ...init,
    headers: {
      "Api-Key": KEY,
      Accept: "application/json",
      ...init?.headers,
    },
  });
  if (!res.ok) {
    let detail = "";
    try { detail = await res.text(); } catch {}
    throw new CmsError(res.status, path, detail.slice(0, 500));
  }
  return res.json() as Promise<T>;
}

export class CmsError extends Error {
  constructor(public status: number, public path: string, public detail: string) {
    super(`CMS ${status} on ${path}: ${detail}`);
    this.name = "CmsError";
  }
}

/* ---------------------------- Convenience API ---------------------------- */

/** Always include this expand param — without it, properties are not returned. */
const EXPAND = "expand=properties[%24all]";

type ListResponse<T> = { total: number; items: T[] };

export const cmsApi = {
  /** Get one node by URL slug, e.g. `""` for home, `"games/cow-run"` for a game. */
  item: <T = any>(slug: string) =>
    cms<T>(`/content/item/${encodeURI(slug)}?${EXPAND}`),

  /** List nodes filtered by content type. */
  list: <T = any>(
    contentType: string,
    opts: { take?: number; skip?: number; sort?: string; filters?: string[] } = {}
  ) => {
    const params = new URLSearchParams();
    params.set("filter", `contentType:${contentType}`);
    opts.filters?.forEach((f) => params.append("filter", f));
    if (opts.sort) params.set("sort", opts.sort);
    params.set("take", String(opts.take ?? 100));
    if (opts.skip) params.set("skip", String(opts.skip));
    const qs = params.toString().replace("expand=properties%5B%24all%5D", EXPAND);
    return cms<ListResponse<T>>(`/content?${qs}&${EXPAND}`);
  },

  /** Generic search across any properties (Lucene-like, see Umbraco docs). */
  search: <T = any>(query: string, take = 20) =>
    cms<ListResponse<T>>(`/content?filter=${encodeURIComponent(query)}&take=${take}&${EXPAND}`),
};
```

Use it like:

```ts
import { cmsApi } from "./lib/cms";
import type { Game } from "./lib/cmsTypes";

const featured = await cmsApi.list<Game>("game", {
  filters: ["gameIsFeatured:true"],
  sort: "name:asc",
  take: 6,
});

const home   = await cmsApi.item("");                    // homepage
const game   = await cmsApi.item("games/cow-run");
const article = await cmsApi.item<NewsArticle>("news/a-universe-where-kids-learn-while-playing");
```

---

## 7. TypeScript types

`src/lib/cmsTypes.ts`:

```ts
/* ────────────────── Generic shapes ────────────────── */

export interface MediaItem {
  id: string;
  name: string;
  mediaType: "Image" | "File" | "Folder" | string;
  url: string;             // relative, e.g. "/media/.../cowrun.webp"
  extension: string;       // "webp", "png", "jpg", ...
  width: number;
  height: number;
  bytes: number;
  focalPoint: { left: number; top: number };
  crops: Array<{ alias: string; width: number; height: number }>;
  properties: Record<string, unknown>;
}

export interface RichText {
  markup: string;
  blocks: BlockListEntry[];   // for inline blocks inside rich text (usually [])
}

export interface BlockListEntry<TContent = AnyBlockContent> {
  content: TContent;
  settings: unknown | null;
}

export interface BlockList {
  items: BlockListEntry[];
}

export interface ContentRoute {
  path: string;
  queryString: string | null;
  startItem: { id: string; path: string };
}

export interface ContentItem<TProperties = Record<string, unknown>> {
  id: string;
  contentType: string;
  name: string;
  createDate: string;     // ISO
  updateDate: string;     // ISO
  route: ContentRoute;
  properties: TProperties;
  cultures: Record<string, unknown>;
}

export type ListResponse<T> = { total: number; items: ContentItem<T>[] };

/* ────────────────── Entity properties ────────────────── */

export interface GameProperties {
  gameTitle: string;
  gameDescription: string;
  gameCoverImage: MediaItem[] | null;
  gameStatus: string;
  gamePlatforms: string[];
  gameGenre: string;
  gameNumPlayers: string;
  gamePlayUrl: string;
  gameDetailsUrl: string;
  gameIsFeatured: boolean;
}
export type Game = ContentItem<GameProperties>;

export interface StoryProperties {
  storyTitle: string;
  storyDescription: string;
  storyThumbnail: MediaItem[] | null;
  storyVideoUrl: string;
  storyDuration: number;
  storyTags: string[];
  storyCategory: string;
}
export type Story = ContentItem<StoryProperties>;

export interface NewsArticleProperties {
  newsTitle: string;
  newsExcerpt: string;
  newsBody: RichText;
  newsHeroImage: MediaItem[] | null;
  newsPublishedDate: string;
  newsCategory: string;
}
export type NewsArticle = ContentItem<NewsArticleProperties>;

export interface CharacterProperties {
  characterName: string;
  characterRole: string;
  characterImage: MediaItem[] | null;
  characterDescription: string;
  characterAccentColor: string;
}
export type Character = ContentItem<CharacterProperties>;

export interface TeamMemberProperties {
  memberName: string;
  memberRole: string;
  memberPhoto: MediaItem[] | null;
  memberBio: string;
}
export type TeamMember = ContentItem<TeamMemberProperties>;

export interface PageProperties {
  title: string;
  metaDescription: string;
  heroImage: MediaItem[] | null;
  blocks: BlockList;
}
export type HomePage = ContentItem<PageProperties>;
export type StandardPage = ContentItem<PageProperties>;

/* ────────────────── Block content types ────────────────── */

export interface HeroBannerProps {
  bannerTitle: string;
  bannerSubtitle: string;
  bannerBody: string;
  bannerBackgroundImage: MediaItem[] | null;
  ctaPrimaryLabel: string;
  ctaPrimaryUrl: string;
  ctaSecondaryLabel: string | null;
  ctaSecondaryUrl: string | null;
}

export interface HeadingBlockProps {
  headingText: string;
  headingLevel: "h1" | "h2" | "h3" | "h4" | "h5" | "h6";
}

export interface RichTextBlockProps {
  content: RichText;
}

export interface StatBlockProps {
  statValue: string;
  statLabel: string;
  statIcon: MediaItem[] | null;
}

export interface FeatureCardProps {
  featureNumber: string;
  featureTitle: string;
  featureDescription: string;
  featureIcon: MediaItem[] | null;
}

export interface TimelineItemProps {
  timelineYear: string;
  timelineTitle: string;
  timelineDescription: string;
  timelineIcon: MediaItem[] | null;
}

export interface CtaBlockProps {
  label: string;
  url: string;
  style: "primary" | "secondary" | "ghost" | string;
  openInNewTab: boolean;
}

export interface NewsletterSignupProps {
  newsletterTitle: string;
  newsletterDescription: string;
  newsletterCtaLabel: string;
  newsletterPlaceholder: string;
}

export type AnyBlockContent =
  | { contentType: "heroBanner"; id: string; properties: HeroBannerProps }
  | { contentType: "headingBlock"; id: string; properties: HeadingBlockProps }
  | { contentType: "richTextBlock"; id: string; properties: RichTextBlockProps }
  | { contentType: "statBlock"; id: string; properties: StatBlockProps }
  | { contentType: "featureCard"; id: string; properties: FeatureCardProps }
  | { contentType: "timelineItem"; id: string; properties: TimelineItemProps }
  | { contentType: "ctaBlock"; id: string; properties: CtaBlockProps }
  | { contentType: "newsletterSignup"; id: string; properties: NewsletterSignupProps }
  | { contentType: string; id: string; properties: Record<string, unknown> };
```

---

## 8. React hooks

`src/lib/cmsHooks.ts`:

```ts
import { useEffect, useRef, useState } from "react";
import { cms, CmsError } from "./cms";

interface CmsState<T> {
  data: T | null;
  error: CmsError | null;
  loading: boolean;
}

/** Generic hook. Pass the full path (after /umbraco/delivery/api/v2). */
export function useCms<T = any>(path: string | null): CmsState<T> {
  const [state, setState] = useState<CmsState<T>>({ data: null, error: null, loading: !!path });
  const inFlight = useRef<AbortController | null>(null);

  useEffect(() => {
    if (!path) {
      setState({ data: null, error: null, loading: false });
      return;
    }
    inFlight.current?.abort();
    const ctrl = new AbortController();
    inFlight.current = ctrl;
    setState((s) => ({ ...s, loading: true, error: null }));

    cms<T>(path, { signal: ctrl.signal })
      .then((d) => !ctrl.signal.aborted && setState({ data: d, error: null, loading: false }))
      .catch((e: any) => {
        if (e.name === "AbortError") return;
        setState({ data: null, error: e, loading: false });
      });

    return () => ctrl.abort();
  }, [path]);

  return state;
}

/** Single item by slug. */
export function useCmsItem<T = any>(slug: string | null) {
  return useCms<T>(slug == null ? null : `/content/item/${encodeURI(slug)}?expand=properties[$all]`);
}

/** Filtered list. */
export function useCmsList<T = any>(opts: {
  contentType: string;
  filters?: string[];
  sort?: string;
  take?: number;
  skip?: number;
}) {
  const params = new URLSearchParams();
  params.set("filter", `contentType:${opts.contentType}`);
  opts.filters?.forEach((f) => params.append("filter", f));
  if (opts.sort) params.set("sort", opts.sort);
  params.set("take", String(opts.take ?? 100));
  if (opts.skip) params.set("skip", String(opts.skip));
  params.set("expand", "properties[$all]");
  return useCms<{ total: number; items: T[] }>(`/content?${params.toString()}`);
}
```

Usage:

```tsx
import { useCmsList, useCmsItem } from "./lib/cmsHooks";
import type { Game } from "./lib/cmsTypes";

function GamesGrid() {
  const { data, loading, error } = useCmsList<Game>({
    contentType: "game",
    sort: "name:asc",
  });

  if (loading) return <Skeleton count={6} />;
  if (error)   return <ErrorBanner error={error} />;
  if (!data)   return null;

  return (
    <div className="grid grid-cols-3 gap-4">
      {data.items.map((g) => <GameCard key={g.id} game={g} />)}
    </div>
  );
}
```

---

## 9. Media URLs (important)

Media URLs in API responses are **relative paths** like `/media/e3b3717172255e4fb2217739512a4154/cowrun.webp`. You have to prefix them.

### The helper

`src/lib/mediaUrl.ts`:

```ts
const BASE: string = import.meta.env.VITE_CMS_BASE_URL;

export function mediaUrl(input: string | null | undefined): string;
export function mediaUrl(input: { url: string } | null | undefined): string;
export function mediaUrl(items: Array<{ url: string }> | null | undefined): string;
export function mediaUrl(input: any): string {
  if (!input) return "";
  if (Array.isArray(input)) return mediaUrl(input[0]);
  if (typeof input === "string") {
    return input.startsWith("http") ? input : `${BASE}${input}`;
  }
  if (typeof input.url === "string") return mediaUrl(input.url);
  return "";
}
```

### Usage

```tsx
import { mediaUrl } from "../lib/mediaUrl";

// Game cover (Media Picker returns array)
<img src={mediaUrl(game.properties.gameCoverImage)} alt={game.properties.gameTitle} />

// Or being explicit
<img src={mediaUrl(game.properties.gameCoverImage?.[0])} alt={game.properties.gameTitle} />
```

### Responsive images / ImageSharp

The CMS serves images through ImageSharp. You can request resized versions by appending query params:

```tsx
<img
  src={mediaUrl(image) + "?width=600&format=webp&quality=80"}
  srcSet={
    `${mediaUrl(image)}?width=300&format=webp 300w,` +
    `${mediaUrl(image)}?width=600&format=webp 600w,` +
    `${mediaUrl(image)}?width=1200&format=webp 1200w`
  }
  sizes="(max-width: 600px) 100vw, 600px"
  alt={imageItem.name}
  width={imageItem.width}
  height={imageItem.height}
/>
```

Supported params: `width`, `height`, `format` (`webp`, `jpg`, `png`), `quality` (1–100), `rmode` (`crop`, `pad`, `max`).

### Focal point

Each media item has a `focalPoint: { left, top }` (0–1 each). Use it for `object-position` on `cover`-sized images:

```tsx
const fp = imageItem.focalPoint;
<img
  src={mediaUrl(imageItem)}
  style={{
    objectFit: "cover",
    objectPosition: `${fp.left * 100}% ${fp.top * 100}%`,
  }}
/>
```

---

## 10. Rich text rendering

Rich text fields return `{ markup: "<p>...</p>", blocks: [] }`. Render the HTML carefully.

### Simple (trusting CMS content)

```tsx
import type { RichText } from "../lib/cmsTypes";

export function RichTextView({ value }: { value: RichText }) {
  return <div className="rich-text" dangerouslySetInnerHTML={{ __html: value.markup }} />;
}
```

> **Safe because** the markup comes from your authenticated backoffice editors. Umbraco sanitizes TinyMCE output server-side.

### Hardened (defense in depth)

If you want a belt + suspenders, sanitize with DOMPurify:

```bash
npm i dompurify
npm i -D @types/dompurify
```

```tsx
import DOMPurify from "dompurify";

export function RichTextView({ value }: { value: RichText }) {
  const clean = DOMPurify.sanitize(value.markup, { USE_PROFILES: { html: true } });
  return <div className="rich-text" dangerouslySetInnerHTML={{ __html: clean }} />;
}
```

### Rewriting media URLs inside the markup

Rich text may include `<img src="/media/...">` referring to the CMS. Rewrite at render time:

```ts
const BASE = import.meta.env.VITE_CMS_BASE_URL;
function rewriteMedia(html: string) {
  return html.replace(/src="\/media\//g, `src="${BASE}/media/`);
}

<div dangerouslySetInnerHTML={{ __html: rewriteMedia(value.markup) }} />
```

---

## 11. Block list rendering

Block lists on `home` and `standardPage` give you `properties.blocks.items[]`. Each item has `content.contentType` plus `content.properties`. Render with a registry of block components.

### The dispatcher

`src/components/BlockRenderer.tsx`:

```tsx
import type { BlockListEntry } from "../lib/cmsTypes";
import { HeroBanner }        from "./blocks/HeroBanner";
import { HeadingBlock }      from "./blocks/HeadingBlock";
import { RichTextBlock }     from "./blocks/RichTextBlock";
import { StatBlock }         from "./blocks/StatBlock";
import { FeatureCard }       from "./blocks/FeatureCard";
import { TimelineItem }      from "./blocks/TimelineItem";
import { CtaBlock }          from "./blocks/CtaBlock";
import { NewsletterSignup }  from "./blocks/NewsletterSignup";

const REGISTRY: Record<string, React.ComponentType<any>> = {
  heroBanner: HeroBanner,
  headingBlock: HeadingBlock,
  richTextBlock: RichTextBlock,
  statBlock: StatBlock,
  featureCard: FeatureCard,
  timelineItem: TimelineItem,
  ctaBlock: CtaBlock,
  newsletterSignup: NewsletterSignup,
};

export function BlockRenderer({ blocks }: { blocks: BlockListEntry[] }) {
  return (
    <>
      {blocks.map((b) => {
        const Comp = REGISTRY[b.content.contentType];
        if (!Comp) {
          if (import.meta.env.DEV) {
            console.warn(`[BlockRenderer] No component for "${b.content.contentType}"`);
          }
          return null;
        }
        return <Comp key={b.content.id} {...b.content.properties} />;
      })}
    </>
  );
}
```

### Example block components

`src/components/blocks/HeroBanner.tsx`:

```tsx
import type { HeroBannerProps } from "../../lib/cmsTypes";
import { mediaUrl } from "../../lib/mediaUrl";

export function HeroBanner(p: HeroBannerProps) {
  return (
    <section
      className="hero"
      style={{
        backgroundImage: p.bannerBackgroundImage
          ? `url(${mediaUrl(p.bannerBackgroundImage)})`
          : undefined,
      }}
    >
      {p.bannerSubtitle && <span className="hero__eyebrow">{p.bannerSubtitle}</span>}
      <h1>{p.bannerTitle}</h1>
      <p>{p.bannerBody}</p>
      <div className="hero__ctas">
        {p.ctaPrimaryLabel && (
          <a href={p.ctaPrimaryUrl} className="btn btn--primary">{p.ctaPrimaryLabel}</a>
        )}
        {p.ctaSecondaryLabel && (
          <a href={p.ctaSecondaryUrl ?? "#"} className="btn btn--secondary">{p.ctaSecondaryLabel}</a>
        )}
      </div>
    </section>
  );
}
```

`src/components/blocks/HeadingBlock.tsx`:

```tsx
import type { HeadingBlockProps } from "../../lib/cmsTypes";

export function HeadingBlock(p: HeadingBlockProps) {
  const Tag = p.headingLevel || "h2";
  return <Tag className={`heading heading--${Tag}`}>{p.headingText}</Tag>;
}
```

`src/components/blocks/RichTextBlock.tsx`:

```tsx
import { RichTextView } from "../RichTextView";
import type { RichTextBlockProps } from "../../lib/cmsTypes";

export const RichTextBlock = (p: RichTextBlockProps) => <RichTextView value={p.content} />;
```

`src/components/blocks/StatBlock.tsx`:

```tsx
import type { StatBlockProps } from "../../lib/cmsTypes";

export const StatBlock = (p: StatBlockProps) => (
  <div className="stat">
    <div className="stat__value">{p.statValue}</div>
    <div className="stat__label">{p.statLabel}</div>
  </div>
);
```

`src/components/blocks/FeatureCard.tsx`:

```tsx
import type { FeatureCardProps } from "../../lib/cmsTypes";

export const FeatureCard = (p: FeatureCardProps) => (
  <article className="feature">
    <span className="feature__num">{p.featureNumber}</span>
    <h3>{p.featureTitle}</h3>
    <p>{p.featureDescription}</p>
  </article>
);
```

`src/components/blocks/TimelineItem.tsx`:

```tsx
import type { TimelineItemProps } from "../../lib/cmsTypes";

export const TimelineItem = (p: TimelineItemProps) => (
  <li className="timeline-item">
    <div className="timeline-item__year">{p.timelineYear}</div>
    <h4>{p.timelineTitle}</h4>
    <p>{p.timelineDescription}</p>
  </li>
);
```

`src/components/blocks/CtaBlock.tsx`:

```tsx
import type { CtaBlockProps } from "../../lib/cmsTypes";

export const CtaBlock = (p: CtaBlockProps) => (
  <a
    className={`btn btn--${p.style}`}
    href={p.url}
    target={p.openInNewTab ? "_blank" : undefined}
    rel={p.openInNewTab ? "noopener noreferrer" : undefined}
  >
    {p.label}
  </a>
);
```

`src/components/blocks/NewsletterSignup.tsx`:

```tsx
import { useState } from "react";
import type { NewsletterSignupProps } from "../../lib/cmsTypes";

export function NewsletterSignup(p: NewsletterSignupProps) {
  const [email, setEmail] = useState("");
  return (
    <form className="newsletter" onSubmit={(e) => { e.preventDefault(); /* TODO submit */ }}>
      <h3>{p.newsletterTitle}</h3>
      <p>{p.newsletterDescription}</p>
      <input
        type="email"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        placeholder={p.newsletterPlaceholder}
        required
      />
      <button type="submit">{p.newsletterCtaLabel}</button>
    </form>
  );
}
```

### Adjacent-block grouping

When the CMS gives you a heading followed by several stat blocks followed by a CTA — and you want to wrap related ones into a section — group at render time:

```tsx
function groupStats(items: BlockListEntry[]): (BlockListEntry | { kind: "statGroup"; items: BlockListEntry[] })[] {
  const out: any[] = [];
  let i = 0;
  while (i < items.length) {
    if (items[i].content.contentType === "statBlock") {
      const group = [];
      while (i < items.length && items[i].content.contentType === "statBlock") {
        group.push(items[i++]);
      }
      out.push({ kind: "statGroup", items: group });
    } else {
      out.push(items[i++]);
    }
  }
  return out;
}
```

Then render groups as `<div className="stats-row">...</div>`.

---

## 12. Page-by-page integration recipes

### 12.1 Homepage

```tsx
import { useCmsItem } from "../lib/cmsHooks";
import type { HomePage } from "../lib/cmsTypes";
import { BlockRenderer } from "../components/BlockRenderer";
import { Helmet } from "react-helmet-async";

export function HomePageView() {
  const { data, loading, error } = useCmsItem<HomePage>("");
  if (loading) return <FullPageSkeleton />;
  if (error)   return <ErrorBanner error={error} />;
  if (!data)   return null;
  const p = data.properties;

  return (
    <>
      <Helmet>
        <title>{p.title}</title>
        <meta name="description" content={p.metaDescription} />
      </Helmet>
      <main>
        <BlockRenderer blocks={p.blocks.items} />
      </main>
    </>
  );
}
```

### 12.2 Games list

```tsx
import { useState } from "react";
import { useCmsList } from "../lib/cmsHooks";
import type { Game } from "../lib/cmsTypes";
import { mediaUrl } from "../lib/mediaUrl";

const ALL = "All";

export function GamesPage() {
  const [genre, setGenre] = useState<string>(ALL);
  const { data, loading } = useCmsList<Game>({ contentType: "game", sort: "name:asc" });
  const games = data?.items ?? [];

  const genres = Array.from(new Set(games.map((g) => g.properties.gameGenre))).sort();
  const filtered = genre === ALL ? games : games.filter((g) => g.properties.gameGenre === genre);

  return (
    <main>
      <h1>Games</h1>
      <nav className="filters">
        {[ALL, ...genres].map((g) => (
          <button key={g} onClick={() => setGenre(g)} className={genre === g ? "active" : ""}>
            {g}
          </button>
        ))}
      </nav>
      {loading && <Skeleton count={6} />}
      <ul className="grid grid-cols-3 gap-4">
        {filtered.map((g) => (
          <li key={g.id}>
            <a href={g.route.path}>
              <img src={mediaUrl(g.properties.gameCoverImage)} alt={g.properties.gameTitle} />
              <h3>{g.properties.gameTitle}</h3>
              <p>{g.properties.gameDescription}</p>
              <div className="meta">
                <span className="badge">{g.properties.gameStatus}</span>
                <span>{g.properties.gameGenre}</span>
              </div>
            </a>
          </li>
        ))}
      </ul>
    </main>
  );
}
```

### 12.3 Single game

```tsx
import { useParams } from "react-router-dom";
import { useCmsItem } from "../lib/cmsHooks";
import type { Game } from "../lib/cmsTypes";
import { mediaUrl } from "../lib/mediaUrl";

export function GameDetail() {
  const { slug } = useParams();
  const { data, loading, error } = useCmsItem<Game>(slug ? `games/${slug}` : null);
  if (loading) return <Skeleton />;
  if (error?.status === 404) return <NotFound />;
  if (error)   return <ErrorBanner error={error} />;
  if (!data)   return null;
  const p = data.properties;

  return (
    <article>
      <img src={mediaUrl(p.gameCoverImage)} alt={p.gameTitle} />
      <h1>{p.gameTitle}</h1>
      <p>{p.gameDescription}</p>
      <dl>
        <dt>Status</dt><dd>{p.gameStatus}</dd>
        <dt>Genre</dt><dd>{p.gameGenre}</dd>
        <dt>Players</dt><dd>{p.gameNumPlayers}</dd>
        <dt>Platforms</dt><dd>{p.gamePlatforms.join(", ")}</dd>
      </dl>
      {p.gamePlayUrl && (
        <a href={p.gamePlayUrl} className="btn btn--primary" target="_blank" rel="noreferrer">
          Play now
        </a>
      )}
    </article>
  );
}
```

### 12.4 News listing with category tabs

```tsx
import { useState } from "react";
import { useCmsList } from "../lib/cmsHooks";
import type { NewsArticle } from "../lib/cmsTypes";
import { mediaUrl } from "../lib/mediaUrl";

export function NewsPage() {
  const [category, setCategory] = useState<string | null>(null);
  const { data, loading } = useCmsList<NewsArticle>({
    contentType: "newsArticle",
    sort: "newsPublishedDate:desc",
    filters: category ? [`newsCategory:${category}`] : [],
  });
  const items = data?.items ?? [];
  const categories = ["Stories & Learning", "Game Updates", "Community"];

  return (
    <main>
      <h1>News</h1>
      <nav>
        <button onClick={() => setCategory(null)} className={!category ? "active" : ""}>All</button>
        {categories.map((c) => (
          <button key={c} onClick={() => setCategory(c)} className={category === c ? "active" : ""}>
            {c}
          </button>
        ))}
      </nav>
      {loading && <Skeleton />}
      <ul>
        {items.map((a) => (
          <li key={a.id}>
            <a href={a.route.path}>
              {a.properties.newsHeroImage && (
                <img src={mediaUrl(a.properties.newsHeroImage)} alt="" />
              )}
              <time>{new Date(a.properties.newsPublishedDate).toLocaleDateString()}</time>
              <h3>{a.properties.newsTitle}</h3>
              <p>{a.properties.newsExcerpt}</p>
            </a>
          </li>
        ))}
      </ul>
    </main>
  );
}
```

### 12.5 Single news article

```tsx
import { useParams } from "react-router-dom";
import { useCmsItem } from "../lib/cmsHooks";
import type { NewsArticle } from "../lib/cmsTypes";
import { mediaUrl } from "../lib/mediaUrl";
import { RichTextView } from "../components/RichTextView";

export function NewsDetail() {
  const { slug } = useParams();
  const { data } = useCmsItem<NewsArticle>(slug ? `news/${slug}` : null);
  if (!data) return null;
  const p = data.properties;
  return (
    <article>
      <header>
        <time>{new Date(p.newsPublishedDate).toLocaleDateString()}</time>
        <h1>{p.newsTitle}</h1>
        <p className="lead">{p.newsExcerpt}</p>
        <img src={mediaUrl(p.newsHeroImage)} alt={p.newsTitle} />
      </header>
      <RichTextView value={p.newsBody} />
    </article>
  );
}
```

### 12.6 Team section (used on About)

```tsx
import { useCmsList } from "../lib/cmsHooks";
import type { TeamMember } from "../lib/cmsTypes";
import { mediaUrl } from "../lib/mediaUrl";

export function TeamGrid() {
  const { data } = useCmsList<TeamMember>({ contentType: "teamMember", sort: "name:asc" });
  if (!data) return null;
  return (
    <ul className="team-grid">
      {data.items.map((m) => (
        <li key={m.id}>
          <img src={mediaUrl(m.properties.memberPhoto)} alt={m.properties.memberName} />
          <h4>{m.properties.memberName}</h4>
          <p className="role">{m.properties.memberRole}</p>
          <p>{m.properties.memberBio}</p>
        </li>
      ))}
    </ul>
  );
}
```

### 12.7 Characters with their accent color

```tsx
import { useCmsList } from "../lib/cmsHooks";
import type { Character } from "../lib/cmsTypes";
import { mediaUrl } from "../lib/mediaUrl";

export function CharactersStrip() {
  const { data } = useCmsList<Character>({ contentType: "character", sort: "name:asc" });
  if (!data) return null;
  return (
    <ul className="characters">
      {data.items.map((c) => (
        <li key={c.id} style={{ "--accent": c.properties.characterAccentColor } as any}>
          <img src={mediaUrl(c.properties.characterImage)} alt={c.properties.characterName} />
          <h4>{c.properties.characterName}</h4>
          <p>{c.properties.characterRole}</p>
        </li>
      ))}
    </ul>
  );
}
```

### 12.8 Stories with category + YouTube embed

```tsx
import { useState } from "react";
import { useCmsList } from "../lib/cmsHooks";
import type { Story } from "../lib/cmsTypes";

function youTubeId(url: string): string | null {
  const m = url.match(/(?:youtube\.com\/(?:watch\?v=|embed\/)|youtu\.be\/)([^&\?]+)/);
  return m?.[1] ?? null;
}

export function StoriesPage() {
  const [cat, setCat] = useState<string | null>(null);
  const { data } = useCmsList<Story>({
    contentType: "story",
    filters: cat ? [`storyCategory:${cat}`] : [],
  });
  const items = data?.items ?? [];
  return (
    <main>
      <h1>Stories</h1>
      <nav>
        <button onClick={() => setCat(null)}>All</button>
        {["Quick Learning Stories", "Moo Shorts", "Bedtime"].map((c) => (
          <button key={c} onClick={() => setCat(c)}>{c}</button>
        ))}
      </nav>
      <ul>
        {items.map((s) => {
          const id = youTubeId(s.properties.storyVideoUrl);
          return (
            <li key={s.id}>
              <h3>{s.properties.storyTitle}</h3>
              <p>{s.properties.storyDescription}</p>
              {id && (
                <iframe
                  src={`https://www.youtube.com/embed/${id}`}
                  title={s.properties.storyTitle}
                  allow="autoplay; encrypted-media; picture-in-picture"
                  allowFullScreen
                />
              )}
              <small>{Math.round(s.properties.storyDuration / 60)} min</small>
            </li>
          );
        })}
      </ul>
    </main>
  );
}
```

---

## 13. SEO metadata

For each page-level content type (`home`, `standardPage`, `newsArticle`), use `title` and `metaDescription` (or `newsTitle`/`newsExcerpt`).

```tsx
import { Helmet } from "react-helmet-async";

<Helmet>
  <title>{p.title} | Cow Paradise</title>
  <meta name="description" content={p.metaDescription} />
  <meta property="og:title" content={p.title} />
  <meta property="og:description" content={p.metaDescription} />
  {p.heroImage?.[0] && (
    <meta property="og:image" content={mediaUrl(p.heroImage[0]) + "?width=1200&format=jpg"} />
  )}
  <meta name="twitter:card" content="summary_large_image" />
</Helmet>
```

For news articles, also set the published date:

```tsx
<meta property="article:published_time" content={p.newsPublishedDate} />
<meta property="article:section" content={p.newsCategory} />
```

---

## 14. Caching, ISR, and freshness

### Browser cache

Wrap your hook with SWR or React Query for stale-while-revalidate behavior:

```tsx
import useSWR from "swr";
import { cms } from "./lib/cms";

function useGames() {
  return useSWR(
    "/content?filter=contentType:game&expand=properties[$all]",
    cms,
    { revalidateOnFocus: false, dedupingInterval: 60_000 }
  );
}
```

### Edge cache

If you're on Amplify/CloudFront/Vercel, add cache headers on the CMS response. Currently the CMS doesn't set them; you can add a Lambda@Edge or a CloudFront response policy that adds:

```
Cache-Control: public, max-age=60, stale-while-revalidate=300
```

### When does content change?

Editor publishes in backoffice → Delivery API immediately returns the new value. **No CMS-side cache TTL**, so you control freshness on the client. Default 60s SWR cache is a safe sweet spot.

---

## 15. Error handling

The `CmsError` from §6 includes `status`, `path`, `detail`. Branch on it:

```tsx
if (error) {
  if (error.status === 401) return <p>Auth misconfigured. Check VITE_CMS_API_KEY.</p>;
  if (error.status === 404) return <NotFoundPage />;
  if (error.status >= 500)  return <p>CMS is having a moment. Retry shortly.</p>;
  return <p>Couldn't load content: {error.message}</p>;
}
```

Add a top-level boundary so a thrown render error doesn't blank the whole app:

```tsx
import { ErrorBoundary } from "react-error-boundary";

<ErrorBoundary FallbackComponent={({ error }) => <p>Crashed: {error.message}</p>}>
  <Routes>...</Routes>
</ErrorBoundary>
```

### Retry with backoff

For flaky networks:

```ts
async function cmsRetry<T>(path: string, attempts = 3): Promise<T> {
  let lastErr;
  for (let i = 0; i < attempts; i++) {
    try { return await cms<T>(path); }
    catch (e) {
      lastErr = e;
      if (e instanceof CmsError && [401, 403, 404].includes(e.status)) throw e;
      await new Promise((r) => setTimeout(r, 200 * 2 ** i));
    }
  }
  throw lastErr;
}
```

---

## 16. Editor preview

The Delivery API has a built-in preview mode: editors can see unpublished changes by passing a `Preview` header. **Don't enable this in your public app** — it's only for an editor's logged-in preview environment.

If you want a preview workflow:

```ts
// Only on a separate /preview route, gated by some token from the editor
fetch(url, { headers: { "Api-Key": key, Preview: "true" } });
```

---

## 17. Troubleshooting

### `401 Unauthorized` everywhere
- Missing `Api-Key` header. Check `.env.local` is loaded (restart dev server after changes).
- Vite vs CRA env prefix mismatch (`VITE_` vs `REACT_APP_`).

### `CORS error` in browser console
- Your dev origin isn't in `Cors__AllowedOrigins`. Add it on the CMS side. Quick fix for local dev — add a Vite proxy:

```ts
// vite.config.ts
export default defineConfig({
  server: {
    proxy: {
      "/umbraco": {
        target: "https://3b2umvhdys.us-east-1.awsapprunner.com",
        changeOrigin: true,
        secure: true,
      },
    },
  },
});
```
Then set `VITE_CMS_BASE_URL=` (empty) so calls hit `/umbraco/...` relative to the dev server.

### Response has `total > 0` but `items` is empty
- You forgot `expand=properties[$all]`. The base list response omits properties.

### Properties exist in backoffice but not in API
- The content type isn't in `Umbraco:CMS:DeliveryApi:AllowedContentTypeAliases`. Currently allowed: `home`, `standardPage`, `settings`, `game`, `story`, `newsArticle`, `character`, `teamMember`, `short`, and the folder types. Ask the CMS maintainer to add new ones.

### Media URLs show 404
- You forgot the base prefix. Use `mediaUrl()`. Direct `<img src="/media/...">` won't resolve against the React app.

### Block returns `null` in render
- Unknown `contentType` not in `REGISTRY`. Add a component for it. Check the dev console for `[BlockRenderer] No component for "X"`.

### Filter with spaces / special characters
- URL-encode the value: `newsCategory:Stories%20%26%20Learning`. JS `URLSearchParams` handles this for you.

### Sorting by a custom property doesn't work
- The property must be a sortable type (string / number / datetime). Block-list or rich-text fields aren't sortable.

### Image renders but blurry / wrong size
- You're loading the original (often 4MB+). Always append `?width=600&format=webp`. See [§9](#9-media-urls-important).

---

## 18. Cheat sheet — every URL you'll ever use

Base: `https://3b2umvhdys.us-east-1.awsapprunner.com/umbraco/delivery/api/v2`
Header on every request: `Api-Key: Yvq69J37e5KCOzVUuleG7wRkDMA6krJdMwlFvW7Z84aHuAzF`

```bash
# ─── Home page (single item + the 3 data-driven grids) ───
# The home node itself (24-block list — see §4a for the section-by-section inventory)
GET /content/item/?expand=properties[$all]
# Trending Games grid (renders between blocks 12 and 13)
GET /content?filter=contentType:game&filter=gameIsFeatured:true&take=3&expand=properties[$all]
# Featured Characters grid (renders between blocks 15 and 16)
GET /content?filter=contentType:character&take=6&expand=properties[$all]
# Game Shorts grid (renders between blocks 20 and 21)
GET /content?filter=contentType:short&take=4&expand=properties[$all]

# ─── Single items ───
# About page
# About page
GET /content/item/about?expand=properties[$all]
# Privacy / Terms
GET /content/item/privacy-policy?expand=properties[$all]
GET /content/item/terms-of-service?expand=properties[$all]
# A specific game
GET /content/item/games/cow-run?expand=properties[$all]
# A specific story
GET /content/item/stories/fun-and-learning?expand=properties[$all]
# A specific news article
GET /content/item/news/a-universe-where-kids-learn-while-playing?expand=properties[$all]

# ─── Listings (default take=10; use take=100 for full lists) ───
GET /content?filter=contentType:game&expand=properties[$all]&take=100
GET /content?filter=contentType:game&filter=gameIsFeatured:true&expand=properties[$all]
GET /content?filter=contentType:game&sort=name:asc&take=100&expand=properties[$all]

GET /content?filter=contentType:story&take=100&expand=properties[$all]
GET /content?filter=contentType:story&filter=storyCategory:Moo%20Shorts&expand=properties[$all]

GET /content?filter=contentType:newsArticle&sort=newsPublishedDate:desc&take=100&expand=properties[$all]
GET /content?filter=contentType:newsArticle&filter=newsCategory:Game%20Updates&expand=properties[$all]

GET /content?filter=contentType:character&take=100&expand=properties[$all]
GET /content?filter=contentType:teamMember&take=100&expand=properties[$all]
GET /content?filter=contentType:short&take=100&expand=properties[$all]

# ─── Pagination ───
GET /content?filter=contentType:story&take=12&skip=0&expand=properties[$all]
GET /content?filter=contentType:story&take=12&skip=12&expand=properties[$all]

# ─── Lightweight (only specific fields) ───
GET /content?filter=contentType:game&fields=properties[gameTitle,gameCoverImage]&take=100

# ─── Media (via CMS proxy) ───
GET /media/<guid-no-dashes>/<filename>
# Resized via ImageSharp
GET /media/<guid>/<filename>?width=600&format=webp&quality=80
```

---

## Appendix A — Live response samples

Each sample below is a real response from the deployed CMS at 2026-05-29.

### `/content?filter=contentType:game&take=1&expand=properties[$all]`

```json
{
  "total": 12,
  "items": [{
    "contentType": "game",
    "name": "Cow Run",
    "createDate": "2026-05-18T13:00:00Z",
    "updateDate": "2026-05-28T22:00:23.347Z",
    "route": {
      "path": "/games/cow-run/",
      "queryString": null,
      "startItem": { "id": "f1a00002-0000-0000-0000-000000000002", "path": "home" }
    },
    "id": "f1a00020-0000-0000-0000-000000000020",
    "properties": {
      "gameTitle": "COWRUN",
      "gameDescription": "Dash, drift, and jump through crazy tracks ...",
      "gameCoverImage": [{
        "focalPoint": { "left": 0.5, "top": 0.5 },
        "crops": [],
        "id": "e3b37171-7225-5e4f-b221-7739512a4154",
        "name": "Cow Run Cover",
        "mediaType": "Image",
        "url": "/media/e3b3717172255e4fb2217739512a4154/cowrun.webp",
        "extension": "webp",
        "width": 832, "height": 832, "bytes": 793126,
        "properties": {}
      }],
      "gameStatus": "Released",
      "gamePlatforms": ["Browser", "PC"],
      "gameGenre": "Racing",
      "gameNumPlayers": "Single Player",
      "gamePlayUrl": "https://play.google.com/store/apps/...",
      "gameDetailsUrl": "https://cowparadisegames.com/games/cow-run",
      "gameIsFeatured": true
    },
    "cultures": {}
  }]
}
```

### Homepage `/content/item/`

Trimmed for length — full shape: `{ id, contentType: "home", name: "Home", route: {...}, properties: { title, metaDescription, heroImage, blocks: { items: [BlockListEntry, ...] } } }`.

Each `blocks.items[]` looks like:

```json
{
  "content": {
    "contentType": "heroBanner",
    "id": "7705a7cd-fce3-9d47-8427-22d796f016f0",
    "properties": {
      "bannerTitle": "Where Games Become a Universe",
      "bannerSubtitle": "Welcome to Cow Paradise",
      "bannerBody": "We're building a playful universe ...",
      "bannerBackgroundImage": null,
      "ctaPrimaryLabel": "Explore Games",
      "ctaPrimaryUrl": "/games",
      "ctaSecondaryLabel": "Meet the Moo Family",
      "ctaSecondaryUrl": "/moo-family"
    }
  },
  "settings": null
}
```

---

## Appendix B — File checklist

When you're done you should have:

```
src/
  lib/
    cms.ts             ✓
    cmsHooks.ts        ✓
    cmsTypes.ts        ✓
    mediaUrl.ts        ✓
  components/
    BlockRenderer.tsx  ✓
    RichTextView.tsx   ✓
    blocks/
      HeroBanner.tsx
      HeadingBlock.tsx
      RichTextBlock.tsx
      StatBlock.tsx
      FeatureCard.tsx
      TimelineItem.tsx
      CtaBlock.tsx
      NewsletterSignup.tsx
.env.local             ✓ (not committed)
.gitignore             contains .env.local
```

---

## Appendix C — Quick smoke test

After wiring up, paste this into your browser console on the React app page:

```js
fetch("https://3b2umvhdys.us-east-1.awsapprunner.com/umbraco/delivery/api/v2/content?take=5", {
  headers: { "Api-Key": "Yvq69J37e5KCOzVUuleG7wRkDMA6krJdMwlFvW7Z84aHuAzF" }
}).then(r => r.json()).then(d => console.log("total:", d.total, d.items.map(i => i.name)));
```

If it logs `total: 72` and a list of names — you're connected. If it errors with CORS, the React app's origin isn't whitelisted yet.

---

**End of document.** Anything missing or unclear, ask the CMS maintainer to update this file alongside the change.
