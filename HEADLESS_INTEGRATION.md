# Headless CMS Integration Guide — React + Umbraco Delivery API

> **Audience:** Any React developer connecting a frontend to the deployed Moo Family Umbraco CMS.
> **Self-contained.** Live URLs, live response samples, copy-paste code. No prior CMS or Umbraco knowledge required.

**Last updated:** 2026-05-29 (section-block model — every menu page)
**CMS:** Umbraco 17.4.0 (App Runner)
**API:** Umbraco Delivery API v2
**Live base URL:** `https://3b2umvhdys.us-east-1.awsapprunner.com`

---

## Table of contents

1. [TL;DR — 5-minute quick start](#1-tldr--5-minute-quick-start)
2. [Architecture](#2-architecture)
3. [API basics](#3-api-basics)
4. [Content model — what's in the CMS](#4-content-model--whats-in-the-cms)
4a. [Per-page section inventory — all 8 menu pages](#4a-per-page-section-inventory--all-8-menu-pages)
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
19. [All pages — Next.js implementation with section-block dispatch](#19-all-pages--nextjs-implementation-with-section-block-dispatch)

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

The Delivery API is **public** in production (`DeliveryApi:PublicAccess: true`) — no `Api-Key` header is required. If you want to send one anyway for compatibility with older clients, the read-only key is:

```
Api-Key: Yvq69J37e5KCOzVUuleG7wRkDMA6krJdMwlFvW7Z84aHuAzF
```

### CORS

The CMS currently allows requests from:

- `https://master.d3boy6qi81n9oz.amplifyapp.com` (Amplify preview)
- `https://staging.cowparadisegames.com`
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
blocks: BlockList                  // detail-page section blocks (see §11); optional, all images optional
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
blocks: BlockList                  // detail-page section blocks (see §11); optional
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
blocks: BlockList                  // detail-page section blocks (see §11); optional
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
siteName: string
footerText: RichText               // copyright / legal line
footerGroups: BlockList            // the footer "menu" — ordered list of footerGroup blocks
```

Each `footerGroups.items[].content` is a **`footerGroup`** element:
```
footerGroupHeading: string         // "Quick Links" | "Community" | "Support" | "Follow Us"
footerGroupType: string            // "links" | "socialLeft" | "socialRight"
footerGroupLinks: BlockList        // list of ctaBlock: { label, url, style, openInNewTab }
```
Render rule: `footerGroupType === "links"` → a text-link column titled by `footerGroupHeading`.
`"socialLeft"` / `"socialRight"` → the left / right social sign-post; render each `ctaBlock` as a
brand icon, mapping the link's `label` ("Facebook" | "Instagram" | "X") to the icon. The left and
right social groups intentionally hold **different URLs**. (Replaces the old flat `footerLinks` +
`socialLinks` properties.)

### Block types (used inside `blocks` on home/standardPage/folder pages)

These appear inside `block.content.contentType`. There are **two families**:

**A. Section blocks** (one per React component — these are what the React UI dispatches on for every menu page):

| Alias | Purpose | Key properties |
|---|---|---|
| `heroCarouselSection` | Home carousel hero | `heroSectionId, heroBackgroundVideoUrl, heroBackgroundVideoPoster: MediaItem[], heroFallbackImage: MediaItem[], heroAutoplayIntervalMs: number, heroSlides: BlockList` (slides = `heroCarouselSlide` with `slideKicker, slideTitle, slideAccentColor`) |
| `whatIsCowParadiseSection` | Home intro band | `whatIsSectionId, whatIsHeading, whatIsDescription, whatIsStats: BlockList<statBlock>, whatIsBullets: BlockList<bulletItem>, whatIsCtaLabel, whatIsCtaUrl, whatIsCtaImage: MediaItem[], whatIsImage: MediaItem[], whatIsImageAlt` |
| `trendingGamesSection` | Home games carousel + featured characters callout | `trendingSectionId, trendingHeading, trendingSubheading, trendingGameSourceMode: "auto"\|"manual", trendingSelectedGames: ContentRef[], trendingMaxItems, trendingFeaturedCharactersHeading, trendingFeaturedCharactersDescription, trendingFeaturedCharactersCtaLabel/Url/Image, trendingFeaturedCharacters: ContentRef[]` |
| `playVideoSection` | Home full-bleed video promo | `playVideoSectionId, playVideoBackgroundImage: MediaItem[], playVideoBackgroundImageAlt, playVideoHeading, playVideoDescription, playVideoUrl, playVideoButtonImage: MediaItem[]` |
| `gameShortsSection` | Home shorts carousel | `shortsSectionId, shortsHeading, shortsDescription, shortsSourceMode, shortsSelectedShorts: ContentRef[], shortsMaxItems, shortsMobileAutoAdvanceMs, shortsCtaLabel/Url/Image` |
| `poweredBySection` | Home partner logos | `poweredBySectionId, poweredByHeading, poweredBySubheading, poweredByLogos: BlockList<logoStripItem>` |
| `pageHeroSection` | Generic page hero (Games, Stories, News, About, Market, Login + Moo Family variants) | `pageHeroSectionId, pageHeroBackgroundImage, pageHeroBackgroundImageAlt, pageHeroEyebrow, pageHeroHeading, pageHeroSubheading, pageHeroLogoImage, pageHeroCtaPrimaryLabel/Url/Image, pageHeroCtaSecondaryLabel/Url/Image` |
| `pageCtaBannerSection` | Standalone CTA banner (Stories "Coming Soon", About "Join Community", Market "Notify Me") | `ctaBannerSectionId, ctaBannerBackgroundImage, ctaBannerHeading, ctaBannerSubheading, ctaBannerCtaLabel/Url/Image` |
| `entityCarouselSection` | Horizontal-scroll entity carousel (Stories Quick Learning / Moo Shorts / CP Shorts) | `entityCarouselSectionId, entityCarouselHeading, entityCarouselSubheading, entityCarouselFilters: BlockList<filterChip>, entityCarouselSourceMode, entityCarouselEntityType: "story"\|"short"\|"game"\|"newsArticle"\|"character"\|"teamMember", entityCarouselCategoryFilter, entityCarouselMaxItems, entityCarouselSelectedStories/Shorts/Games/NewsArticles/Characters/TeamMembers: ContentRef[]` |
| `entityGridSection` | Grid of entities (Games "All Games", News listing, About "Our Team") | Same as `entityCarouselSection` with prefix `entityGrid*` + `entityGridLayout: "grid"\|"staggered"` |
| `richTextWithImageSection` | Two-column heading + body + side image (About "About Us", Moo Family "Browse Stories") | `richTextImageSectionId, richTextImageHeading, richTextImageBody: RichText, richTextImageImage, richTextImageImageAlt, richTextImagePosition: "left"\|"right"` |
| `imageOverlayBannerSection` | Full-bleed image with overlay heading (About "Moo Journey") | `imgOverlaySectionId, imgOverlayBackgroundImage, imgOverlayBackgroundImageAlt, imgOverlayHeading, imgOverlaySubheading` |
| `headingStatsSection` | Heading + ornament + stats grid (Moo Family "Learning Impact") | `headingStatsSectionId, headingStatsHeading, headingStatsSubheading, headingStatsOrnamentImage, headingStatsItems: BlockList<statBlock>` |
| `imageAccordionSection` | Side image + accordion (Moo Family "Smart Learning") | `imageAccordionSectionId, imageAccordionImage, imageAccordionImageAlt, imageAccordionHeading, imageAccordionDescription, imageAccordionItems: BlockList<accordionItem>` |
| `mooFamilyCharacterHeroSection` | Moo Family hero with 3-character collage | `mfCharacterHeroSectionId, mfCharacterHeroBackgroundColor, mfCharacterHeroHeading, mfCharacterHeroSubheading, mfCharacterHeroCtaPrimaryLabel/Url, mfCharacterHeroCtaSecondaryLabel/Url, mfCharacterHeroFeaturedCharacters: ContentRef[]` |
| `numberedBenefitsSection` | Numbered list of benefits (Moo Family "Learning with the Moo Family") | `numberedBenefitsSectionId, numberedBenefitsHeading, numberedBenefitsSubheading, numberedBenefitsItems: BlockList<numberedBenefit>` |
| `centerImageBenefitsSection` | Center family image + 4 icon cards around it (Moo Family "Why Kids Love") | `centerImgBenefitsSectionId, centerImgBenefitsHeading, centerImgBenefitsSubheading, centerImgBenefitsImage, centerImgBenefitsItems: BlockList<iconBenefit>` |
| `educationalGamesSection` | Category chips + custom game cards (Moo Family "Variety of Educational Games") | `eduGamesSectionId, eduGamesHeading, eduGamesSubheading, eduGamesCategoryFilters: BlockList<filterChip>, eduGamesCards: BlockList<educationalGameCard>` |
| `impactTimelineSection` | Year-stamped timeline cards (About "Our Impact") | `impactTimelineSectionId, impactTimelineHeading, impactTimelineSubheading, impactTimelineCards: BlockList<impactTimelineCard>` |
| `missionVisionSection` | 3-column Mission/Vision strip (About) | `missionVisionSectionId, missionVisionMissionHeading, missionVisionMissionBody, missionVisionCenterHeading, missionVisionDecorativeImage1/2, missionVisionVisionHeading, missionVisionVisionBody` |

**Nested item element types** (only inside the BlockList properties above):

| Alias | Properties | Used by |
|---|---|---|
| `heroCarouselSlide` | `slideKicker, slideTitle, slideAccentColor` | `heroCarouselSection.heroSlides` |
| `bulletItem` | `bulletText, bulletIcon` | `whatIsCowParadiseSection.whatIsBullets` |
| `filterChip` | `filterChipLabel, filterChipValue` | `entityCarousel/GridSection.*Filters`, `educationalGamesSection.eduGamesCategoryFilters` |
| `numberedBenefit` | `numberedBenefitNumber, numberedBenefitTitle, numberedBenefitDescription` | `numberedBenefitsSection.numberedBenefitsItems` |
| `iconBenefit` | `iconBenefitIcon, iconBenefitTitle, iconBenefitDescription` | `centerImageBenefitsSection.centerImgBenefitsItems` |
| `educationalGameCard` | `eduGameCardIcon, eduGameCardTitle, eduGameCardDescription, eduGameCardBackgroundColor` | `educationalGamesSection.eduGamesCards` |
| `impactTimelineCard` | `impactTimelineCardYear, impactTimelineCardTitle, impactTimelineCardDescription, impactTimelineCardIcon, impactTimelineCardAccentColor` | `impactTimelineSection.impactTimelineCards` |
| `statBlock` | `statValue, statLabel, statIcon` | `whatIsCowParadiseSection.whatIsStats`, `headingStatsSection.headingStatsItems` |
| `logoStripItem` | `logoName, logoImage, logoUrl` | `poweredBySection.poweredByLogos` |
| `accordionItem` | `accordionTitle, accordionContent` | `imageAccordionSection.imageAccordionItems` |

**B. Primitive blocks** (still allowed on `standardPage` for one-off cases; the Home + 7 menu pages use section blocks instead):

| Alias | Purpose | Key properties |
|---|---|---|
| `heroBanner` | Single hero | `bannerTitle, bannerSubtitle, bannerBody, bannerBackgroundImage, ctaPrimaryLabel/Url, ctaSecondaryLabel/Url` |
| `headingBlock` | Heading | `headingText, headingLevel` (`h1`–`h6`) |
| `richTextBlock` | Rich text | `content: { markup, blocks }` |
| `featureCard` | Numbered feature | `featureNumber, featureTitle, featureDescription, featureIcon` |
| `timelineItem` | Timeline entry | `timelineYear, timelineTitle, timelineDescription, timelineIcon` |
| `bulletList` | Bullets via `MultipleTextstring` | `bulletListTitle, bulletItems: string[]` |
| `ctaBlock` | Single CTA | `label, url, style, openInNewTab` |
| `imageBlock` | Single image | `image, altText, caption` |
| `videoBlock` | Embedded video | `videoUrl, videoPosterImage, videoCaption` |
| `youtubeBlock` | YouTube embed | `youtubeUrl` |
| `playstoreBlock` | Play Store badge | `playStoreUrl` |
| `newsletterSignup` | Signup form | `newsletterTitle, newsletterDescription, newsletterCtaLabel, newsletterPlaceholder` |
| `logoStrip` | Logo carousel | `logoStripTitle, logoStripItems: BlockList<logoStripItem>` |

---

## 4a. Per-page section inventory — all 8 menu pages

Every menu page now exposes a section-block composition that maps 1:1 to a React component. This section is the contract: for each page, you get the fetch URL, the section blocks in render order, and the entity content types it depends on.

> **The rule:** one CMS section block = one React component. The frontend renders each page by mapping `blocks.items[].content.contentType` to a section component (see §11 + §19). No string switching on heading text or block index.

### 4a.1 Home — `GET /content/item/`

| # | Section block | Renders | Entity refs |
|---|---|---|---|
| 1 | `heroCarouselSection` | Carousel hero with autoplaying background video + N slides (kicker + title) | — |
| 2 | `whatIsCowParadiseSection` | Intro band: heading, description, 4 stats (statBlock), 3 bullets (bulletItem), CTA, Moo Family group image | — |
| 3 | `trendingGamesSection` | Horizontal scrolling games carousel + "Featured Characters" callout | `game` (3–12 via `auto`/`manual`), `character` (3) |
| 4 | `playVideoSection` | Full-bleed tropical scene + heading + body + play button | — |
| 5 | `gameShortsSection` | Vertical-video shorts carousel (mobile) / grid (desktop) | `short` (up to 4) |
| 6 | `poweredBySection` | Partner logo strip | nested `logoStripItem` |
| 7 | `newsletterSignup` | "Stay in the loop" form | — |

**Entity fetches the React side does on top of the home blocks** (when section block has `sourceMode: "auto"`):

| Section's `entityType` | Fetch | Notes |
|---|---|---|
| Trending games | `GET /content?filter=contentType:game&filter=gameIsFeatured:true&take={trendingMaxItems}&expand=properties[$all]` | Falls back to `sort=name:asc&take={N}` if fewer than `N` are featured |
| Featured characters | `GET /content?filter=contentType:character&take=3&expand=properties[$all]` | Use `characterAccentColor` as card backdrop |
| Game shorts | `GET /content?filter=contentType:short&take={shortsMaxItems}&expand=properties[$all]` | Embed via YouTube ID parsed from `storyVideoUrl` |

When `sourceMode: "manual"`, use the matching `selected*` ContentRef array on the section block instead of the auto fetch — the IDs already point to the entries the editor picked.

### 4a.2 Games — `GET /content/item/games/`

`gamesFolder` content node. Two section blocks:

| # | Section block | Renders | Entity refs |
|---|---|---|---|
| 1 | `pageHeroSection` | Background image + eyebrow "Recently Released" + game logo + body + "View Details" / "Play Now" CTAs | — |
| 2 | `entityGridSection` | All Games filterable grid | `game` (auto, max=24) |

Filter chips on block 2: `entityGridFilters` carries `[{label: "Platform", value: "platform"}, {label: "Genre", value: "genre"}, ...]` — React side maps chip values to client-side filters over the games list.

Game cards: `GET /content?filter=contentType:game&take={entityGridMaxItems}&expand=properties[$all]` (or use `entityGridSelectedGames` ContentRefs when manual).

### 4a.3 Stories — `GET /content/item/stories/`

`storiesFolder` content node. Five section blocks:

| # | Section block | Renders | Entity refs |
|---|---|---|---|
| 1 | `pageHeroSection` | Background banner + "Stories from the Moo Family World" + subheading | — |
| 2 | `entityCarouselSection` | "Quick Learning Stories" with 3 filter chips (All / Cow Paradise / Moo Family) | `story` (auto, `categoryFilter: "Quick Learning Stories"`) |
| 3 | `entityCarouselSection` | "Moo Shorts" carousel | `short` (auto, `categoryFilter: "MooFamily"`) |
| 4 | `entityCarouselSection` | "Cow Paradise Shorts" carousel | `short` (auto, `categoryFilter: "CowParadise"`) |
| 5 | `pageCtaBannerSection` | "More Adventures Coming Soon" + "Subscribe for More" CTA | — |

For each carousel, fetch with the `categoryFilter` value: `GET /content?filter=contentType:{entityType}&filter=storyCategory:{categoryFilter}&take={maxItems}&expand=properties[$all]` (use `shortCategory` for shorts).

### 4a.4 Moo Family — `GET /content/item/moo-family/`

`standardPage` content node. Seven section blocks, all Moo-Family-specific:

| # | Section block | Renders | Entity refs |
|---|---|---|---|
| 1 | `mooFamilyCharacterHeroSection` | Peach hero with heading + subheading + 2 CTAs + 3-character overlapping collage | `character` (3) |
| 2 | `numberedBenefitsSection` | "Learning with the Moo Family" + 6 numbered cards | nested `numberedBenefit` |
| 3 | `richTextWithImageSection` | "Meet the Friends Who Make Learning Fun" + side image | — |
| 4 | `centerImageBenefitsSection` | "Why Kids Love Learning" + central family image + 4 icon benefit cards around it | nested `iconBenefit` |
| 5 | `educationalGamesSection` | 8 category chips (Alphabet / Words / Spelling / Reading / Writing / Numbers / Brain Games / Creativity) + 4 game cards | nested `filterChip` + `educationalGameCard` |
| 6 | `headingStatsSection` | "Learning That Makes a Difference" + ornament + 4 stats | nested `statBlock` |
| 7 | `imageAccordionSection` | "Smart Learning" image + 4 accordion items | nested `accordionItem` |

The educational game cards on block 5 are **inline cards**, not references into the `game` content type — these represent learning categories, not playable games.

### 4a.5 About Us — `GET /content/item/about/`

`standardPage` content node. Seven section blocks:

| # | Section block | Renders | Entity refs |
|---|---|---|---|
| 1 | `pageHeroSection` | "The Story Behind Cow Paradise" hero | — |
| 2 | `richTextWithImageSection` | "About Us" body + Moo Family image (image position = `right`) | — |
| 3 | `imageOverlayBannerSection` | Full-bleed "THE MOO JOURNEY" banner | — |
| 4 | `impactTimelineSection` | "Our Impact" + 4 timeline cards (year, title, description, icon, accent color) | nested `impactTimelineCard` |
| 5 | `missionVisionSection` | 3-column Mission / "WHERE WE'RE HEADED" / Vision strip with 2 decorative images | — |
| 6 | `entityGridSection` | "Our Team" staggered grid (`entityGridLayout: "staggered"`) | `teamMember` (auto) |
| 7 | `pageCtaBannerSection` | "Join Our Community" + "Subscribe for More" CTA | — |

Team grid fetch: `GET /content?filter=contentType:teamMember&take={maxItems}&expand=properties[$all]`.

### 4a.6 News — `GET /content/item/news/`

`newsFolder` content node. Two section blocks:

| # | Section block | Renders | Entity refs |
|---|---|---|---|
| 1 | `pageHeroSection` | "Cow Paradise News & Updates" hero | — |
| 2 | `entityGridSection` | "All News Updates" + 6 category chips (All / Game Updates / Stories & Learning / Events / Community / Rewards) + news cards grid | `newsArticle` (auto, max=24) |

Selected chip's value becomes a server-side filter: `GET /content?filter=contentType:newsArticle&filter=newsCategory:{value}&take={maxItems}&sort=newsPublishedDate:desc&expand=properties[$all]`. When the chip value is `all`, omit the `newsCategory` filter.

### 4a.7 Market — `GET /content/item/market/`

`standardPage` content node. Two section blocks (placeholder until store launches):

| # | Section block | Renders | Entity refs |
|---|---|---|---|
| 1 | `pageHeroSection` | "Coming Soon" eyebrow + "The Cow Paradise Market" hero | — |
| 2 | `pageCtaBannerSection` | "Be First in Line" + "Notify Me" CTA pointing at the newsletter form | — |

When the store actually launches, replace block 2 with an `entityGridSection` pointing at a future `marketItem` content type.

### 4a.8 Login — `GET /content/item/login/`

`standardPage` content node. One section block:

| # | Section block | Renders | Entity refs |
|---|---|---|---|
| 1 | `pageHeroSection` | "Welcome Back to Cow Paradise" hero + 2 CTAs (Terms of Service / Privacy Policy) | — |

The actual auth form (email/password fields, signup tab, validation) is React-owned — the CMS only stores the page chrome around it (background, heading, T&C link targets).

### 4a.9 Profile — not CMS-backed

`/profile` is user-data driven (avatar, stats, transaction history, achievements). No CMS node, no Delivery API fetch. Treat any "Coming soon" placeholder copy inside tabs as React-static for now.

### Settings / Footer / Header

Navigation, footer text, footer groups (nav columns + left/right social sign-posts) — fetched from the `settings` singleton (`GET /content/item/settings/?expand=properties[$all]`), not from any page node. See §4 for the `footerGroups` property shape (grouped model; replaces the old flat `footerLinks`/`socialLinks`). The header `Home / Games / Stories / Moo Family / About Us / Market / News / Profile / LOGIN` is **not** CMS-driven (live in React routing today); to make it editable later, model it as a `BlockList<navItem>` on `settings`.

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

Every menu page follows the **same shape**: fetch the page node, dispatch its `blocks.items[]` through a `BlockRenderer` registry that maps each section block alias to a React component (see §19 for the registry). Sections that pull entities do their own fetches *inside* the section component (or upstream in a Server Component).

### 12.1 Universal page view (works for all 8 menu pages)

```tsx
import { useCmsItem } from "../lib/cmsHooks";
import { BlockRenderer } from "../components/BlockRenderer";
import { Helmet } from "react-helmet-async";

interface PageNode {
  properties: {
    title?: string;             // home / standardPage
    metaDescription?: string;   // home / standardPage
    blocks: { items: BlockListItem[] };
  };
  name: string;                  // fallback when title is empty (folder nodes)
}

export function CmsPage({ slug }: { slug: string }) {
  // slug = "" for home, "about", "moo-family", "games", "stories", "news", "market", "login"
  const { data, loading, error } = useCmsItem<PageNode>(slug);
  if (loading) return <FullPageSkeleton />;
  if (error)   return <ErrorBanner error={error} />;
  if (!data)   return null;
  const p = data.properties;
  const pageTitle = p.title || data.name;

  return (
    <>
      <Helmet>
        <title>{pageTitle} | Cow Paradise</title>
        {p.metaDescription && <meta name="description" content={p.metaDescription} />}
      </Helmet>
      <main>
        <BlockRenderer blocks={p.blocks?.items ?? []} />
      </main>
    </>
  );
}
```

Wire your router once:

```tsx
<Routes>
  <Route path="/"             element={<CmsPage slug="" />} />
  <Route path="/games"        element={<CmsPage slug="games" />} />
  <Route path="/stories"      element={<CmsPage slug="stories" />} />
  <Route path="/moo-family"   element={<CmsPage slug="moo-family" />} />
  <Route path="/about-us"     element={<CmsPage slug="about" />} />
  <Route path="/market"       element={<CmsPage slug="market" />} />
  <Route path="/news"         element={<CmsPage slug="news" />} />
  <Route path="/login"        element={<CmsPage slug="login" />} />
  <Route path="/profile"      element={<ProfilePage />} />
  {/* Profile is user-data driven — not CMS-backed */}
</Routes>
```

Per-page nuances are then handled inside the section components, not at the page level.

### 12.2 Home page quirks (slug = "")

The Trending Games and Game Shorts sections do their own entity fetches based on `sourceMode`:

```tsx
// inside TrendingGamesSection.tsx
function useTrendingGames(b: TrendingGamesProps) {
  if (b.trendingGameSourceMode === "manual") {
    return b.trendingSelectedGames; // already ContentRef[] resolved by ?expand
  }
  return useCmsList<Game>({
    contentType: "game",
    filters: ["gameIsFeatured:true"],
    take: b.trendingMaxItems ?? 12,
    sort: "name:asc",
  }).data?.items ?? [];
}
```

Same pattern for `gameShortsSection` (entity = `short`) and `trendingFeaturedCharacters` (entity = `character`, exactly 3).

### 12.3 Games / Stories / News (folder pages with auto-feed entity grids)

Folder pages (`gamesFolder`, `storiesFolder`, `newsFolder`) expose `blocks.items[]` exactly like home/standardPage — the universal `CmsPage` works as-is. The `entityGridSection` / `entityCarouselSection` inside each handles the entity fetch:

```tsx
// inside EntityGridSection.tsx — reused by Games "All Games" and News "All News"
function useEntityGrid(b: EntityGridProps) {
  if (b.entityGridSourceMode === "manual") {
    // Pick the matching selected* picker per entityType
    return b[`entityGridSelected${capitalize(plural(b.entityGridEntityType))}`];
  }
  const filters: string[] = [];
  if (b.entityGridCategoryFilter) {
    const catProp = `${b.entityGridEntityType}Category`; // newsCategory, storyCategory, ...
    filters.push(`${catProp}:${b.entityGridCategoryFilter}`);
  }
  return useCmsList({
    contentType: b.entityGridEntityType,
    filters,
    take: b.entityGridMaxItems ?? 12,
    sort: defaultSortFor(b.entityGridEntityType),
  }).data?.items ?? [];
}
```

Filter chips on the section (`entityGridFilters`) are client-side filters over the result.

### 12.4 About Us (`standardPage` with `entityGridSection` for Team)

Same `CmsPage` flow. The Team section renders the `entityGridSection` block with `entityGridEntityType: "teamMember"` and `entityGridLayout: "staggered"` — the section component reads the layout and stacks team-member cards with alternating-row vertical offset.

### 12.5 Moo Family (`standardPage` with 7 unique section types)

Same `CmsPage` flow. The 5 Moo-Family-specific section components (`mooFamilyCharacterHeroSection`, `numberedBenefitsSection`, `centerImageBenefitsSection`, `educationalGamesSection`, `imageAccordionSection`) plus the 2 generic ones (`richTextWithImageSection`, `headingStatsSection`) all dispatch through the same `BlockRenderer` registry. The 3-character collage in the hero pulls from `mfCharacterHeroFeaturedCharacters` (already resolved ContentRefs because we use `?expand=properties[$all]`).

### 12.6 Market + Login

Both are minimal — Market is 2 blocks (`pageHeroSection` + `pageCtaBannerSection`), Login is 1 (`pageHeroSection`). The Login auth form (React component) is mounted *under* the CMS-driven chrome:

```tsx
// inside the page itself or as part of pageHeroSection rendering
<>
  <BlockRenderer blocks={p.blocks.items} />
  {pathname === "/login" && <AuthForm />}
</>
```

### 12.7 Entity detail pages

Below are detail recipes for each entity type — used when the user clicks a card on a listing page and goes to `/games/{slug}`, `/news/{slug}`, etc.

> **CMS-composed detail pages:** `game`, `story`, and `character` now expose a **`blocks`** BlockList (same section-block palette as `standardPage` — see §11/§19). When `properties.blocks` is present, render it through the **same section-block dispatcher** used for menu pages instead of (or in addition to) the flat-field markup below. All 12 games ship a seeded 6-section detail page (hero → trailer video → what's-new → about → spec stats → CTA); story/character `blocks` start empty for editors to fill. Every section image is optional, so guard `mediaUrl()` on empty arrays.

#### Single game

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

#### Single news article

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

#### Single story (with YouTube embed)

```tsx
import { useParams } from "react-router-dom";
import { useCmsItem } from "../lib/cmsHooks";
import type { Story } from "../lib/cmsTypes";

function youTubeId(url: string): string | null {
  const m = url.match(/(?:youtube\.com\/(?:watch\?v=|embed\/)|youtu\.be\/)([^&\?]+)/);
  return m?.[1] ?? null;
}

export function StoryDetail() {
  const { slug } = useParams();
  const { data } = useCmsItem<Story>(slug ? `stories/${slug}` : null);
  if (!data) return null;
  const p = data.properties;
  const id = p.storyVideoUrl ? youTubeId(p.storyVideoUrl) : null;
  return (
    <article>
      <h1>{p.storyTitle}</h1>
      <p>{p.storyDescription}</p>
      {id && (
        <iframe
          src={`https://www.youtube.com/embed/${id}`}
          title={p.storyTitle}
          allow="autoplay; encrypted-media; picture-in-picture"
          allowFullScreen
        />
      )}
      <small>{Math.round(p.storyDuration / 60)} min</small>
    </article>
  );
}
```

#### Removed (now embedded as section blocks)

The old standalone recipes for Games-list, News-list, Stories-list, Team-grid, and Characters-strip are replaced by the section blocks above. The fetches still happen — but they happen *inside* `entityCarouselSection` / `entityGridSection` components driven by the section block's `entityType` + `sourceMode` properties, not as separate page-level fetches.

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

## 19. All pages — Next.js implementation with section-block dispatch

A complete Next.js (App Router) + Tailwind implementation that renders **every menu page** from the CMS using a single section-block dispatch pattern. The home page from https://cowparadisegames.com/ plus Games, Stories, Moo Family, About Us, News, Market, Login — all share the same page route and the same `BlockRenderer` registry. Only the leaf section components differ.

### 19.1 Architecture

- **Server components do all fetching.** Each request to `/<slug>` (or `/` for home) fetches the page node + any auto-mode entity feeds in parallel. No client-side data fetching for the initial render.
- **Block registry, not switch statements.** Every section block alias (`pageHeroSection`, `entityCarouselSection`, `whatIsCowParadiseSection`, etc.) maps to a single React component in a registry. The `BlockRenderer` looks up the component by `block.content.contentType` and renders it. Adding a new section block = adding one entry to the registry.
- **Section components fetch their own entities.** `entityCarouselSection` / `entityGridSection` / `trendingGamesSection` / `gameShortsSection` / `mooFamilyCharacterHeroSection` all read `sourceMode` from their props and either follow the manual ContentRefs or run an auto-feed fetch upstream in a Server Component.
- **ISR with `revalidate: 60`.** Backoffice edits show within ~60s without redeploy.
- **`next/image` for media** with the CMS host in `remotePatterns`.
- **Fonts via `next/font/google`** — Fredoka (display) + Rubik (body).

### 19.2 Project setup

#### `next.config.mjs`

```js
const CMS_HOST = new URL(process.env.CMS_BASE_URL ?? 'https://3b2umvhdys.us-east-1.awsapprunner.com').host;

/** @type {import('next').NextConfig} */
const nextConfig = {
  images: {
    remotePatterns: [{ protocol: 'https', hostname: CMS_HOST, pathname: '/media/**' }],
  },
};

export default nextConfig;
```

#### `tailwind.config.ts`

```ts
import type { Config } from 'tailwindcss';

const config: Config = {
  content: ['./app/**/*.{ts,tsx}', './components/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        'brand-cyan':   '#06c7f2',  // section headings, primary
        'brand-gold':   '#ffe500',  // hero kicker, accents
        'brand-peach':  '#ffedd3',  // soft section backgrounds
        'brand-cream':  '#fff5de',  // pale section backgrounds
        'ink':          '#1F2937',  // body text
      },
      fontFamily: {
        display: ['var(--font-fredoka)', 'system-ui', 'sans-serif'],
        body:    ['var(--font-rubik)',   'system-ui', 'sans-serif'],
      },
    },
  },
};
export default config;
```

#### `app/layout.tsx`

```tsx
import './globals.css';
import { Fredoka, Rubik } from 'next/font/google';

const fredoka = Fredoka({ subsets: ['latin'], weight: ['400','500','600','700'], variable: '--font-fredoka' });
const rubik   = Rubik  ({ subsets: ['latin'], weight: ['300','400','500','600','700'], variable: '--font-rubik' });

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${fredoka.variable} ${rubik.variable}`}>
      <body className="font-body bg-white text-ink antialiased">
        <SiteHeader />
        {children}
        <SiteFooter />
      </body>
    </html>
  );
}
```

`SiteHeader` and `SiteFooter` are React components fetching the `settings` singleton via `cms('/content/item/settings')` if you want them CMS-driven. Otherwise they can be static (the live site is).

### 19.3 The CMS client

Use the client from [§6](#6-the-client-library). For Next.js Server Components, the fetch automatically participates in route revalidation:

```ts
// lib/cms.ts
const BASE = process.env.CMS_BASE_URL!;
const KEY  = process.env.CMS_API_KEY!;

export async function cms<T = unknown>(path: string, opts?: { revalidate?: number }): Promise<T> {
  const res = await fetch(`${BASE}/umbraco/delivery/api/v2${path}`, {
    headers: { 'Api-Key': KEY, Accept: 'application/json' },
    next: { revalidate: opts?.revalidate ?? 60 },
  });
  if (!res.ok) throw new Error(`CMS ${res.status} on ${path}`);
  return res.json();
}

export const mediaUrl = (m?: { url?: string } | { url?: string }[]) => {
  const url = Array.isArray(m) ? m[0]?.url : m?.url;
  return url ? (url.startsWith('http') ? url : `${BASE}${url}`) : '';
};
```

### 19.4 The block registry

The heart of the pattern: one component per section block alias.

```tsx
// components/blocks/registry.tsx
import { HeroCarouselSection }       from './HeroCarouselSection';
import { WhatIsCowParadiseSection }  from './WhatIsCowParadiseSection';
import { TrendingGamesSection }      from './TrendingGamesSection';
import { PlayVideoSection }          from './PlayVideoSection';
import { GameShortsSection }         from './GameShortsSection';
import { PoweredBySection }          from './PoweredBySection';
import { NewsletterSignup }          from './NewsletterSignup';
import { PageHeroSection }           from './PageHeroSection';
import { PageCtaBannerSection }      from './PageCtaBannerSection';
import { EntityCarouselSection }     from './EntityCarouselSection';
import { EntityGridSection }         from './EntityGridSection';
import { RichTextWithImageSection }  from './RichTextWithImageSection';
import { ImageOverlayBannerSection } from './ImageOverlayBannerSection';
import { HeadingStatsSection }       from './HeadingStatsSection';
import { ImageAccordionSection }     from './ImageAccordionSection';
import { MooFamilyCharacterHeroSection } from './MooFamilyCharacterHeroSection';
import { NumberedBenefitsSection }   from './NumberedBenefitsSection';
import { CenterImageBenefitsSection } from './CenterImageBenefitsSection';
import { EducationalGamesSection }   from './EducationalGamesSection';
import { ImpactTimelineSection }     from './ImpactTimelineSection';
import { MissionVisionSection }      from './MissionVisionSection';

export const BLOCK_REGISTRY: Record<string, React.FC<any>> = {
  // Home-specific sections
  heroCarouselSection:           HeroCarouselSection,
  whatIsCowParadiseSection:      WhatIsCowParadiseSection,
  trendingGamesSection:          TrendingGamesSection,
  playVideoSection:              PlayVideoSection,
  gameShortsSection:             GameShortsSection,
  poweredBySection:              PoweredBySection,
  newsletterSignup:              NewsletterSignup,

  // Cross-page generic sections
  pageHeroSection:               PageHeroSection,
  pageCtaBannerSection:          PageCtaBannerSection,
  entityCarouselSection:         EntityCarouselSection,
  entityGridSection:             EntityGridSection,
  richTextWithImageSection:      RichTextWithImageSection,
  imageOverlayBannerSection:     ImageOverlayBannerSection,
  headingStatsSection:           HeadingStatsSection,
  imageAccordionSection:         ImageAccordionSection,

  // Moo Family-specific sections
  mooFamilyCharacterHeroSection: MooFamilyCharacterHeroSection,
  numberedBenefitsSection:       NumberedBenefitsSection,
  centerImageBenefitsSection:    CenterImageBenefitsSection,
  educationalGamesSection:       EducationalGamesSection,

  // About Us-specific sections
  impactTimelineSection:         ImpactTimelineSection,
  missionVisionSection:          MissionVisionSection,
};

export function BlockRenderer({ blocks }: { blocks: BlockListItem[] }) {
  return (
    <>
      {blocks.map((b) => {
        const Cmp = BLOCK_REGISTRY[b.content.contentType];
        if (!Cmp) {
          console.warn(`No component registered for ${b.content.contentType}`);
          return null;
        }
        return <Cmp key={b.content.id} {...b.content.properties} />;
      })}
    </>
  );
}
```

### 19.5 The universal page route

One route file handles all 8 menu pages.

```tsx
// app/[[...slug]]/page.tsx — catches "/", "/games", "/stories", "/moo-family", "/about-us", "/market", "/news", "/login"
import { notFound } from 'next/navigation';
import { cms } from '@/lib/cms';
import { BlockRenderer } from '@/components/blocks/registry';
import type { Metadata } from 'next';

// Map URL slug → Delivery API slug. Most are 1:1; about-us is the one rename.
const URL_TO_CMS: Record<string, string> = {
  '':            '',          // home
  'games':       'games',
  'stories':     'stories',
  'moo-family':  'moo-family',
  'about-us':    'about',     // CMS node is at /about/
  'market':      'market',
  'news':        'news',
  'login':       'login',
};

interface Props { params: { slug?: string[] } }

async function fetchPage(urlSlug: string) {
  const cmsSlug = URL_TO_CMS[urlSlug];
  if (cmsSlug === undefined) return null;
  const path = cmsSlug === '' ? '/content/item/' : `/content/item/${cmsSlug}/`;
  return cms(`${path}?expand=properties[$all]`, { revalidate: 60 });
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const slug = params.slug?.join('/') ?? '';
  const data = await fetchPage(slug);
  if (!data) return {};
  const p = (data as any).properties;
  return {
    title: `${p.title || (data as any).name} | Cow Paradise`,
    description: p.metaDescription,
  };
}

export default async function Page({ params }: Props) {
  const slug = params.slug?.join('/') ?? '';
  const data = await fetchPage(slug);
  if (!data) return notFound();
  const p = (data as any).properties;
  return (
    <main>
      <BlockRenderer blocks={p.blocks?.items ?? []} />
    </main>
  );
}

// Pre-render the 8 CMS-backed routes at build time
export function generateStaticParams() {
  return Object.keys(URL_TO_CMS).map((slug) => ({
    slug: slug === '' ? [] : slug.split('/'),
  }));
}
```

`/profile` is NOT in this route — Profile is user-data driven, so it lives at `app/profile/page.tsx` with its own data flow.

### 19.6 Section component examples

#### Generic: `PageHeroSection`

```tsx
// components/blocks/PageHeroSection.tsx
import Image from 'next/image';
import { mediaUrl } from '@/lib/cms';

interface PageHeroProps {
  pageHeroSectionId?: string;
  pageHeroBackgroundImage?: { url: string }[];
  pageHeroBackgroundImageAlt?: string;
  pageHeroEyebrow?: string;
  pageHeroHeading: string;
  pageHeroSubheading?: string;
  pageHeroLogoImage?: { url: string }[];
  pageHeroCtaPrimaryLabel?: string;
  pageHeroCtaPrimaryUrl?: string;
  pageHeroCtaPrimaryImage?: { url: string }[];
  pageHeroCtaSecondaryLabel?: string;
  pageHeroCtaSecondaryUrl?: string;
  pageHeroCtaSecondaryImage?: { url: string }[];
}

export function PageHeroSection(p: PageHeroProps) {
  const bg = mediaUrl(p.pageHeroBackgroundImage);
  const logo = mediaUrl(p.pageHeroLogoImage);
  return (
    <section id={p.pageHeroSectionId} className="relative min-h-[min(72vh,820px)] overflow-hidden">
      {bg && (
        <Image src={bg} alt={p.pageHeroBackgroundImageAlt ?? ''}
               fill priority sizes="100vw" className="object-cover object-center" />
      )}
      <div className="relative z-10 max-w-[1860px] mx-auto px-4 py-24 sm:px-8 md:px-12">
        {p.pageHeroEyebrow && (
          <h2 className="font-display text-3xl md:text-4xl text-brand-cyan font-bold">{p.pageHeroEyebrow}</h2>
        )}
        {logo && <img src={logo} alt="" className="mt-5 h-28 md:h-32 w-auto" />}
        <h1 className="font-display text-5xl md:text-7xl text-brand-cyan font-bold mt-4">{p.pageHeroHeading}</h1>
        {p.pageHeroSubheading && <p className="mt-6 max-w-2xl text-lg text-ink">{p.pageHeroSubheading}</p>}
        <div className="mt-6 flex gap-4 flex-wrap">
          {p.pageHeroCtaPrimaryLabel && (
            <a href={p.pageHeroCtaPrimaryUrl} className="btn btn-primary">{p.pageHeroCtaPrimaryLabel}</a>
          )}
          {p.pageHeroCtaSecondaryLabel && (
            <a href={p.pageHeroCtaSecondaryUrl} className="btn btn-secondary">{p.pageHeroCtaSecondaryLabel}</a>
          )}
        </div>
      </div>
    </section>
  );
}
```

Used on Games, Stories, News, About Us, Market, Login (and the optional eyebrow + logo image accommodate the page-specific variations).

#### Entity-driven: `EntityGridSection`

```tsx
// components/blocks/EntityGridSection.tsx
import { cms } from '@/lib/cms';

interface EntityGridProps {
  entityGridSectionId?: string;
  entityGridHeading: string;
  entityGridSubheading?: string;
  entityGridFilters?: { items: { content: { properties: { filterChipLabel: string; filterChipValue: string } } }[] };
  entityGridSourceMode?: 'auto' | 'manual';
  entityGridEntityType: 'game' | 'story' | 'short' | 'newsArticle' | 'character' | 'teamMember';
  entityGridCategoryFilter?: string;
  entityGridMaxItems?: number;
  entityGridLayout?: 'grid' | 'staggered';
  entityGridSelectedGames?: any[];
  entityGridSelectedNewsArticles?: any[];
  entityGridSelectedTeamMembers?: any[];
  // ... other selected* arrays as needed
}

async function fetchEntities(p: EntityGridProps) {
  if (p.entityGridSourceMode === 'manual') {
    // Pick the matching selected* picker per entityType
    switch (p.entityGridEntityType) {
      case 'game':        return p.entityGridSelectedGames ?? [];
      case 'newsArticle': return p.entityGridSelectedNewsArticles ?? [];
      case 'teamMember':  return p.entityGridSelectedTeamMembers ?? [];
      // ... other cases
    }
  }
  const filters: string[] = [`contentType:${p.entityGridEntityType}`];
  if (p.entityGridCategoryFilter && p.entityGridCategoryFilter !== 'all') {
    const catProp = {
      newsArticle: 'newsCategory',
      story:       'storyCategory',
      short:       'shortCategory',
    }[p.entityGridEntityType];
    if (catProp) filters.push(`${catProp}:${p.entityGridCategoryFilter}`);
  }
  const qs = filters.map((f) => `filter=${encodeURIComponent(f)}`).join('&');
  const sort = p.entityGridEntityType === 'newsArticle' ? 'newsPublishedDate:desc' : 'name:asc';
  const take = p.entityGridMaxItems ?? 24;
  const data = await cms<{ items: any[] }>(`/content?${qs}&sort=${sort}&take=${take}&expand=properties[$all]`);
  return data.items;
}

export async function EntityGridSection(p: EntityGridProps) {
  const entities = await fetchEntities(p);
  const filters = p.entityGridFilters?.items ?? [];
  const isStaggered = p.entityGridLayout === 'staggered';

  return (
    <section id={p.entityGridSectionId} className="px-4 sm:px-8 md:px-12 py-16">
      <div className="max-w-[1860px] mx-auto">
        <h2 className="font-display text-5xl md:text-7xl text-brand-cyan font-bold">{p.entityGridHeading}</h2>
        {p.entityGridSubheading && <p className="mt-3 text-lg">{p.entityGridSubheading}</p>}
        {filters.length > 0 && (
          <nav className="mt-10 flex flex-wrap gap-4">
            {filters.map((f) => (
              <FilterChip key={f.content.properties.filterChipValue}
                          label={f.content.properties.filterChipLabel}
                          value={f.content.properties.filterChipValue} />
            ))}
          </nav>
        )}
        <ul className={`mt-12 grid gap-10 ${isStaggered ? 'staggered-grid' : 'grid-cols-1 sm:grid-cols-2 lg:grid-cols-3'}`}>
          {entities.map((e) => <EntityCard key={e.id} entity={e} entityType={p.entityGridEntityType} />)}
        </ul>
      </div>
    </section>
  );
}
```

`EntityCard` is a small dispatcher that renders the right card layout by `entityType` (game card / news card / team member card / character card / etc.).

### 19.7 Auto vs manual sourceMode (cheat sheet)

Section blocks that fetch entities (`trendingGamesSection`, `gameShortsSection`, `entityCarouselSection`, `entityGridSection`, `mooFamilyCharacterHeroSection`) all follow the same pattern:

```ts
async function resolveEntities(b: SectionWithEntities) {
  if (b.sourceMode === 'manual') {
    // selectedX is already an array of expanded ContentRefs because we used ?expand=properties[$all]
    return b[`selected${capitalize(plural(b.entityType))}`];
  }
  // auto: fetch from /content with the right filters
  const filters = [`contentType:${b.entityType}`];
  if (b.categoryFilter)        filters.push(`${b.entityType}Category:${b.categoryFilter}`);
  if (b.entityType === 'game') filters.push(`gameIsFeatured:true`);  // home only
  const qs = filters.map((f) => `filter=${encodeURIComponent(f)}`).join('&');
  return (await cms(`/content?${qs}&take=${b.maxItems}&expand=properties[$all]`)).items;
}
```

### 19.8 Per-page composition reference

Once the registry + universal page route are in place, every page is described by its section block list (already documented in [§4a](#4a-per-page-section-inventory--all-8-menu-pages)). Quick summary:

| Page | URL | Section blocks rendered (in order) |
|---|---|---|
| Home | `/` | `heroCarouselSection` · `whatIsCowParadiseSection` · `trendingGamesSection` · `playVideoSection` · `gameShortsSection` · `poweredBySection` · `newsletterSignup` |
| Games | `/games` | `pageHeroSection` · `entityGridSection` |
| Stories | `/stories` | `pageHeroSection` · `entityCarouselSection` ×3 · `pageCtaBannerSection` |
| Moo Family | `/moo-family` | `mooFamilyCharacterHeroSection` · `numberedBenefitsSection` · `richTextWithImageSection` · `centerImageBenefitsSection` · `educationalGamesSection` · `headingStatsSection` · `imageAccordionSection` |
| About Us | `/about-us` | `pageHeroSection` · `richTextWithImageSection` · `imageOverlayBannerSection` · `impactTimelineSection` · `missionVisionSection` · `entityGridSection` (team, staggered) · `pageCtaBannerSection` |
| News | `/news` | `pageHeroSection` · `entityGridSection` |
| Market | `/market` | `pageHeroSection` · `pageCtaBannerSection` |
| Login | `/login` | `pageHeroSection` (form mounts under the chrome) |
| Profile | `/profile` | *(not CMS-backed — user-data driven)* |

### 19.9 Troubleshooting

| Symptom | Fix |
|---|---|
| `No component registered for X` console warning | Add `X` to `BLOCK_REGISTRY` in `components/blocks/registry.tsx`. |
| Sections render but nested item lists are empty (e.g. `whatIsBullets.items === undefined`) | Make sure you fetched with `?expand=properties[$all]` — nested BlockLists need explicit expansion. |
| Carousel arrows do nothing | The carousel component must have `'use client'` at the top. Server components can't hold local state. |
| `next/image` says "Invalid src prop" | The CMS host isn't in `next.config.mjs > images.remotePatterns`. Update with `CMS_BASE_URL` host. |
| One section renders but its data is stale | ISR cache is at 60s. Either wait or call `revalidateTag('cms')` after a CMS edit (see [§14](#14-caching-isr-and-freshness)). |
| Auto-mode entity fetch returns 401 | Server-side fetch needs the `Api-Key` header. Make sure `process.env.CMS_API_KEY` is set in your Next.js environment. |
| About Us "team" grid renders ungated members | Add the `?filter=teamMemberIsActive:true` filter once that property is added to the `teamMember` content type. |

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
