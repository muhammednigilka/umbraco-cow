# Headless CMS Integration Guide — React + Umbraco Delivery API

> **Audience:** A React developer integrating the Moo Family Umbraco CMS into an existing React/Vite app.
> Self-contained. Assumes the CMS is running locally on `http://localhost:5000`.

**Last updated:** 2026-05-18
**CMS:** Umbraco 17.4.0 (self-hosted)
**API:** Umbraco Delivery API v2 (built-in headless JSON)

---

## 1. Architecture overview

```
┌──────────────────┐         HTTPS         ┌───────────────────────┐
│  React app       │ ────────────────────▶ │  Umbraco CMS          │
│  (Vite/Amplify)  │   GET /umbraco/       │  (App Runner / local) │
│                  │      delivery/api/v2  │                       │
│  - fetches JSON  │ ◀──────────────────── │  Delivery API v2      │
│  - renders pages │     application/json  │  - reads SQLite/SQL   │
└──────────────────┘                       │  - serves media from  │
                                           │    S3+CloudFront      │
                                           └───────────────────────┘
```

Editors create content in the Umbraco backoffice → it's instantly available to your React app as JSON.

---

## 2. Quick reference: every URL

Base URL: `http://localhost:5000` (dev) or `https://cms.your-domain.com` (prod).
All endpoints below are appended to that base.

| Goal | URL |
|---|---|
| **Home page content** | `/umbraco/delivery/api/v2/content/item/?expand=properties[$all]` |
| **Single page by URL slug** | `/umbraco/delivery/api/v2/content/item/{slug}?expand=properties[$all]` |
| **Global site settings (footer, site name)** | `/umbraco/delivery/api/v2/content/item/settings?expand=properties[$all]` |
| **List all games** | `/umbraco/delivery/api/v2/content?filter=contentType:game&expand=properties[$all]&take=100` |
| **Featured games** | `/umbraco/delivery/api/v2/content?filter=contentType:game&filter=gameIsFeatured:true&expand=properties[$all]` |
| **Single game by path** | `/umbraco/delivery/api/v2/content/item/games/{slug}?expand=properties[$all]` |
| **List all stories** | `/umbraco/delivery/api/v2/content?filter=contentType:story&expand=properties[$all]&take=100` |
| **Stories by category** | `/umbraco/delivery/api/v2/content?filter=contentType:story&filter=storyCategory:Moo Shorts&expand=properties[$all]` |
| **List all news articles (newest first)** | `/umbraco/delivery/api/v2/content?filter=contentType:newsArticle&sort=newsPublishedDate:desc&expand=properties[$all]` |
| **News by category** | `/umbraco/delivery/api/v2/content?filter=contentType:newsArticle&filter=newsCategory:Game Updates&expand=properties[$all]` |
| **Single news article** | `/umbraco/delivery/api/v2/content/item/news/{slug}?expand=properties[$all]` |
| **List all characters** | `/umbraco/delivery/api/v2/content?filter=contentType:character&expand=properties[$all]` |
| **List all team members** | `/umbraco/delivery/api/v2/content?filter=contentType:teamMember&expand=properties[$all]` |

### About `expand=properties[$all]`
Without this query parameter, the API returns only `id`, `name`, `contentType`, `route`. With it, every property of every node is included. **Always include it** unless you're doing a lightweight tree fetch.

### About `filter=contentType:X`
You can chain multiple filters. Each `filter=` is ANDed. Example:
`...?filter=contentType:newsArticle&filter=newsCategory:Events&filter=newsPublishedDate>2024-01-01`

### About `sort=field:asc|desc`
Works on any property that's a sortable type (string, integer, datetime). Examples:
- `sort=newsPublishedDate:desc`
- `sort=storyDuration:asc`
- `sort=name:asc`

### About `take=N` and `skip=N`
Default `take` is 10. Use `take=100` for full lists or implement pagination with `skip`.

---

## 3. Authentication

### Local development
The CMS is configured with `DeliveryApi:PublicAccess = true` in `appsettings.Development.json`. **No header needed.**

### Production
`DeliveryApi:PublicAccess = false`. Send an API key in every request:

```
Api-Key: <your-secret>
```

The key value lives in AWS Secrets Manager (`moofamily/umbraco/delivery-api-key`) and is exposed to the React app via Amplify env vars (`VITE_UMBRACO_API_KEY`).

---

## 4. CORS

Umbraco's CORS is configured in [appsettings.json](src/MooFamily.Cms.Web/appsettings.json) at `Cors:AllowedOrigins`. Current allowed origins:

- `http://localhost:3000` (Create React App default)
- `http://localhost:5173` (Vite default)
- (Phase 6+) `https://master.d3boy6qi81n9oz.amplifyapp.com` and `https://your-domain.com`

If your dev server runs on a different port, edit `appsettings.json` → restart the CMS.

---

## 5. React client setup

### 5.1 Environment variables

**`.env.local`** in your React project root (gitignored):
```bash
VITE_UMBRACO_API_BASE_URL=http://localhost:5000
# VITE_UMBRACO_API_KEY=  # leave unset locally
```

**Production (Amplify console → Environment variables):**
```
VITE_UMBRACO_API_BASE_URL=https://cms.your-domain.com
VITE_UMBRACO_API_KEY=<from-aws-secrets-manager>
```

If you're using Create React App instead of Vite, swap `VITE_` for `REACT_APP_` and `import.meta.env` for `process.env`.

### 5.2 Install dependencies (optional but recommended)

```bash
npm install swr
# or
npm install @tanstack/react-query
```

Either gives you caching, retries, loading state, and stale-while-revalidate. The examples below use SWR but plain `fetch` + `useEffect` also works.

### 5.3 The client library

Create `src/lib/umbracoClient.ts`:

```ts
const API_BASE = import.meta.env.VITE_UMBRACO_API_BASE_URL ?? "http://localhost:5000";
const API_KEY = import.meta.env.VITE_UMBRACO_API_KEY;

const headers: HeadersInit = {
  Accept: "application/json",
  ...(API_KEY ? { "Api-Key": API_KEY } : {}),
};

export async function umbracoFetch<T>(path: string): Promise<T> {
  const res = await fetch(`${API_BASE}${path}`, { headers });
  if (!res.ok) {
    throw new Error(`Umbraco fetch ${path} failed: ${res.status} ${res.statusText}`);
  }
  return res.json();
}

const EXPAND = "expand=properties[$all]";

// ─── Pages ─────────────────────────────────────────────────────────────

export const getHome = () =>
  umbracoFetch(`/umbraco/delivery/api/v2/content/item/?${EXPAND}`);

export const getPageByPath = (path: string) =>
  umbracoFetch(`/umbraco/delivery/api/v2/content/item${path.startsWith("/") ? path : "/" + path}?${EXPAND}`);

export const getSettings = () =>
  umbracoFetch(`/umbraco/delivery/api/v2/content/item/settings?${EXPAND}`);

// ─── Collections ──────────────────────────────────────────────────────

function listEndpoint(contentType: string, extra = "") {
  return `/umbraco/delivery/api/v2/content?filter=contentType:${contentType}&${EXPAND}&take=100${extra}`;
}

export const getGames = () => umbracoFetch(listEndpoint("game"));
export const getFeaturedGames = () =>
  umbracoFetch(listEndpoint("game", "&filter=gameIsFeatured:true"));
export const getGameBySlug = (slug: string) =>
  umbracoFetch(`/umbraco/delivery/api/v2/content/item/games/${slug}?${EXPAND}`);

export const getStories = () => umbracoFetch(listEndpoint("story"));
export const getStoriesByCategory = (category: string) =>
  umbracoFetch(listEndpoint("story", `&filter=storyCategory:${encodeURIComponent(category)}`));

export const getNews = () =>
  umbracoFetch(listEndpoint("newsArticle", "&sort=newsPublishedDate:desc"));
export const getNewsBySlug = (slug: string) =>
  umbracoFetch(`/umbraco/delivery/api/v2/content/item/news/${slug}?${EXPAND}`);
export const getNewsByCategory = (category: string) =>
  umbracoFetch(listEndpoint("newsArticle", `&filter=newsCategory:${encodeURIComponent(category)}&sort=newsPublishedDate:desc`));

export const getCharacters = () => umbracoFetch(listEndpoint("character"));
export const getTeam = () => umbracoFetch(listEndpoint("teamMember"));
```

### 5.4 TypeScript types

Create `src/lib/umbracoTypes.ts`:

```ts
// ─── Generic envelope ─────────────────────────────────────────────────

export interface UmbracoListResponse<T> {
  total: number;
  items: T[];
}

export interface UmbracoNode<Props = Record<string, unknown>> {
  contentType: string;
  name: string;
  id: string;
  createDate: string;
  updateDate: string;
  route: {
    path: string;                  // e.g. "/games/cow-run/"
    queryString: string | null;
    startItem: { id: string; path: string };
  };
  properties: Props;
  cultures: Record<string, unknown>;
}

// ─── Media (returned when properties have uploaded images) ────────────

export interface UmbracoMediaItem {
  url: string;                     // absolute or relative
  width?: number;
  height?: number;
  bytes?: number;
  extension?: string;
  focalPoint?: { left: number; top: number } | null;
  crops?: unknown[];
}

// Media properties are arrays even when "single image only"
export type MediaPickerValue = UmbracoMediaItem[] | null;

// ─── Rich text (returned by RichTextEditor properties) ────────────────

export interface RichTextValue {
  markup: string;                  // HTML string, safe to dangerouslySetInnerHTML
  blocks: null | unknown;
}

// ─── Page properties (existing 3 doc types) ───────────────────────────

export interface HomeProps {
  title: string;
  metaDescription: string;
  heroImage: MediaPickerValue;
  blocks: BlockListValue | null;
}

export interface StandardPageProps {
  title: string;
  metaDescription: string;
  blocks: BlockListValue | null;
}

export interface SettingsProps {
  siteName: string;
  footerText: RichTextValue;
  footerLinks: BlockListValue | null;
  socialLinks: BlockListValue | null;
}

// ─── Entity properties (the 5 data types we added) ────────────────────

export interface GameProps {
  gameTitle: string;
  gameDescription: string;
  gameCoverImage: MediaPickerValue;
  gameStatus: string;              // "Released" | "Coming Soon" | "Early Access"
  gamePlatforms: string[];         // e.g. ["Steam", "Browser"]
  gameGenre: string;
  gameNumPlayers: string;
  gamePlayUrl: string;
  gameDetailsUrl: string;
  gameIsFeatured: boolean;
}

export interface StoryProps {
  storyTitle: string;
  storyDescription: string;
  storyThumbnail: MediaPickerValue;
  storyVideoUrl: string;
  storyDuration: number;           // seconds
  storyTags: string[];             // ["Cow Paradise", "Moo Family"]
  storyCategory: string;           // "Quick Learning Stories" | "Moo Shorts" | "Cow Paradise Shorts"
}

export interface NewsArticleProps {
  newsTitle: string;
  newsExcerpt: string;
  newsBody: RichTextValue;
  newsHeroImage: MediaPickerValue;
  newsPublishedDate: string;       // ISO 8601
  newsCategory: string;
}

export interface CharacterProps {
  characterName: string;
  characterRole: string;
  characterImage: MediaPickerValue;
  characterDescription: string;
  characterAccentColor: string;    // hex e.g. "#3FBDF1"
}

export interface TeamMemberProps {
  memberName: string;
  memberRole: string;
  memberPhoto: MediaPickerValue;
  memberBio: string;
}

// ─── Block List (used by Home.blocks, StandardPage.blocks, Settings.*Links) ───

export interface BlockItem<C = Record<string, unknown>> {
  content: {
    contentType: string;           // e.g. "heroBanner", "statBlock"
    id: string;
    properties: C;
  };
  settings?: { contentType: string; id: string; properties: Record<string, unknown> };
}

export interface BlockListValue {
  items: BlockItem[];
}

// ─── Block element properties (all 16 element types) ──────────────────
// Existing 6:

export interface HeadingBlockProps   { headingText: string; headingLevel: string; }
export interface RichTextBlockProps  { content: RichTextValue; }
export interface ImageBlockProps     { image: MediaPickerValue; altText: string; caption: string; alignment: string; }
export interface YouTubeBlockProps   { videoUrl: string; caption: string; }
export interface PlayStoreBlockProps { playStoreUrl: string; label: string; showQrCode: boolean; }
export interface CtaBlockProps       { label: string; url: string; style: string; openInNewTab: boolean; }

// New 10:

export interface HeroBannerProps {
  bannerTitle: string;
  bannerSubtitle: string;
  bannerBody: string;
  bannerBackgroundImage: MediaPickerValue;
  ctaPrimaryLabel: string;
  ctaPrimaryUrl: string;
  ctaSecondaryLabel: string;
  ctaSecondaryUrl: string;
}
export interface StatBlockProps         { statValue: string; statLabel: string; statIcon: MediaPickerValue; }
export interface FeatureCardProps       { featureNumber: string; featureTitle: string; featureDescription: string; featureIcon: MediaPickerValue; }
export interface TimelineItemProps      { timelineYear: string; timelineTitle: string; timelineDescription: string; timelineIcon: MediaPickerValue; }
export interface AccordionItemProps     { accordionTitle: string; accordionContent: RichTextValue; }
export interface NewsletterSignupProps  { newsletterTitle: string; newsletterDescription: string; newsletterCtaLabel: string; newsletterPlaceholder: string; }
export interface LogoStripItemProps     { logoName: string; logoImage: MediaPickerValue; logoUrl: string; }
export interface LogoStripProps         { logoStripTitle: string; logoStripItems: BlockListValue; }
export interface BulletListProps        { bulletListTitle: string; bulletItems: string[]; }
export interface VideoBlockProps        { videoUrl: string; videoPosterImage: MediaPickerValue; videoCaption: string; }
```

---

## 6. Page-by-page integration

Each section below shows a working component. Drop them into your routes.

### 6.1 Home page

```tsx
// src/pages/HomePage.tsx
import useSWR from "swr";
import { getHome, getFeaturedGames, getCharacters } from "../lib/umbracoClient";
import type { UmbracoNode, HomeProps, GameProps, CharacterProps, UmbracoListResponse } from "../lib/umbracoTypes";

export function HomePage() {
  const { data: home } = useSWR<UmbracoNode<HomeProps>>("home", getHome);
  const { data: games } = useSWR<UmbracoListResponse<UmbracoNode<GameProps>>>("featured-games", getFeaturedGames);
  const { data: chars } = useSWR<UmbracoListResponse<UmbracoNode<CharacterProps>>>("characters", getCharacters);

  if (!home) return <div>Loading…</div>;

  return (
    <main>
      <h1>{home.properties.title}</h1>
      <p>{home.properties.metaDescription}</p>

      <section>
        <h2>Trending Games</h2>
        {games?.items.map((g) => (
          <article key={g.id}>
            <h3>{g.properties.gameTitle}</h3>
            <p>{g.properties.gameDescription}</p>
            <span>{g.properties.gameStatus}</span>
          </article>
        ))}
      </section>

      <section>
        <h2>Featured Characters</h2>
        {chars?.items.map((c) => (
          <article key={c.id} style={{ background: c.properties.characterAccentColor }}>
            <h3>{c.properties.characterName}</h3>
            <p>{c.properties.characterRole}</p>
          </article>
        ))}
      </section>
    </main>
  );
}
```

### 6.2 Games page (full list with filters)

```tsx
// src/pages/GamesPage.tsx
import { useState } from "react";
import useSWR from "swr";
import { getGames } from "../lib/umbracoClient";
import type { UmbracoListResponse, UmbracoNode, GameProps } from "../lib/umbracoTypes";

const STATUS_OPTIONS = ["All", "Released", "Coming Soon", "Early Access"];

export function GamesPage() {
  const [status, setStatus] = useState("All");
  const { data, error } = useSWR<UmbracoListResponse<UmbracoNode<GameProps>>>("games", getGames);

  if (error) return <div>Failed to load games.</div>;
  if (!data) return <div>Loading…</div>;

  const filtered = data.items.filter(
    (g) => status === "All" || g.properties.gameStatus === status
  );

  return (
    <main>
      <h1>All Games</h1>
      <div>
        {STATUS_OPTIONS.map((s) => (
          <button key={s} onClick={() => setStatus(s)} disabled={status === s}>{s}</button>
        ))}
      </div>
      <ul>
        {filtered.map((g) => (
          <li key={g.id}>
            <h3>{g.properties.gameTitle}</h3>
            <p>{g.properties.gameDescription}</p>
            <small>{g.properties.gamePlatforms.join(" · ")}</small>
            {g.properties.gamePlayUrl && (
              <a href={g.properties.gamePlayUrl} target="_blank" rel="noopener">Play Now</a>
            )}
          </li>
        ))}
      </ul>
    </main>
  );
}
```

### 6.3 Stories page (tabbed by category)

```tsx
// src/pages/StoriesPage.tsx
import { useState } from "react";
import useSWR from "swr";
import { getStories } from "../lib/umbracoClient";
import type { UmbracoListResponse, UmbracoNode, StoryProps } from "../lib/umbracoTypes";

const CATEGORIES = ["Quick Learning Stories", "Moo Shorts", "Cow Paradise Shorts"];

function formatDuration(sec: number) {
  const m = Math.floor(sec / 60);
  const s = (sec % 60).toString().padStart(2, "0");
  return `${m}:${s}`;
}

export function StoriesPage() {
  const [tab, setTab] = useState(CATEGORIES[0]);
  const { data } = useSWR<UmbracoListResponse<UmbracoNode<StoryProps>>>("stories", getStories);
  if (!data) return null;

  return (
    <main>
      <h1>Stories from the Moo Family World</h1>
      <nav>
        {CATEGORIES.map((c) => (
          <button key={c} onClick={() => setTab(c)} aria-current={tab === c}>{c}</button>
        ))}
      </nav>
      <ul>
        {data.items
          .filter((s) => s.properties.storyCategory === tab)
          .map((s) => (
            <li key={s.id}>
              <span>{formatDuration(s.properties.storyDuration)}</span>
              <h3>{s.properties.storyTitle}</h3>
              <p>{s.properties.storyDescription}</p>
            </li>
          ))}
      </ul>
    </main>
  );
}
```

### 6.4 News list + detail

```tsx
// src/pages/NewsPage.tsx
import useSWR from "swr";
import { Link } from "react-router-dom"; // or your router
import { getNews } from "../lib/umbracoClient";
import type { UmbracoListResponse, UmbracoNode, NewsArticleProps } from "../lib/umbracoTypes";

export function NewsPage() {
  const { data } = useSWR<UmbracoListResponse<UmbracoNode<NewsArticleProps>>>("news", getNews);
  if (!data) return null;

  return (
    <main>
      <h1>Cow Paradise News & Updates</h1>
      <ul>
        {data.items.map((n) => (
          <li key={n.id}>
            <span className="badge">{n.properties.newsCategory}</span>
            <h3><Link to={`/news${n.route.path.replace("/news", "")}`}>{n.properties.newsTitle}</Link></h3>
            <time dateTime={n.properties.newsPublishedDate}>
              {new Date(n.properties.newsPublishedDate).toLocaleDateString()}
            </time>
            <p>{n.properties.newsExcerpt}</p>
          </li>
        ))}
      </ul>
    </main>
  );
}
```

```tsx
// src/pages/NewsArticlePage.tsx
import { useParams } from "react-router-dom";
import useSWR from "swr";
import { getNewsBySlug } from "../lib/umbracoClient";
import type { UmbracoNode, NewsArticleProps } from "../lib/umbracoTypes";

export function NewsArticlePage() {
  const { slug } = useParams<{ slug: string }>();
  const { data } = useSWR<UmbracoNode<NewsArticleProps>>(
    slug ? `news/${slug}` : null,
    () => getNewsBySlug(slug!)
  );
  if (!data) return null;

  return (
    <article>
      <h1>{data.properties.newsTitle}</h1>
      <time>{new Date(data.properties.newsPublishedDate).toLocaleDateString()}</time>
      <div dangerouslySetInnerHTML={{ __html: data.properties.newsBody.markup }} />
    </article>
  );
}
```

### 6.5 About page (with team)

```tsx
// src/pages/AboutPage.tsx
import useSWR from "swr";
import { getPageByPath, getTeam } from "../lib/umbracoClient";
import type { UmbracoListResponse, UmbracoNode, StandardPageProps, TeamMemberProps } from "../lib/umbracoTypes";

export function AboutPage() {
  const { data: page } = useSWR<UmbracoNode<StandardPageProps>>("about", () => getPageByPath("/about"));
  const { data: team } = useSWR<UmbracoListResponse<UmbracoNode<TeamMemberProps>>>("team", getTeam);
  if (!page) return null;

  return (
    <main>
      <h1>{page.properties.title}</h1>
      <p>{page.properties.metaDescription}</p>

      <section>
        <h2>Our Team</h2>
        <div className="team-grid">
          {team?.items.map((m) => (
            <div key={m.id}>
              <h3>{m.properties.memberName}</h3>
              <p>{m.properties.memberRole}</p>
              {m.properties.memberBio && <small>{m.properties.memberBio}</small>}
            </div>
          ))}
        </div>
      </section>
    </main>
  );
}
```

### 6.6 Site-wide footer (driven by Settings)

```tsx
// src/components/Footer.tsx
import useSWR from "swr";
import { getSettings } from "../lib/umbracoClient";
import type { UmbracoNode, SettingsProps } from "../lib/umbracoTypes";

export function Footer() {
  const { data } = useSWR<UmbracoNode<SettingsProps>>("settings", getSettings);
  if (!data) return null;

  return (
    <footer>
      <h4>{data.properties.siteName}</h4>
      <div dangerouslySetInnerHTML={{ __html: data.properties.footerText.markup }} />
    </footer>
  );
}
```

---

## 7. Images & media

### 7.1 What you get when media IS uploaded

Once an editor uploads media in the backoffice and picks it in a Media Picker property, the API returns:

```json
{
  "characterImage": [
    {
      "url": "/media/abc123/littlejack.png",
      "width": 600,
      "height": 800,
      "bytes": 184320,
      "extension": "png",
      "focalPoint": null
    }
  ]
}
```

Important things:
- The value is **always an array**, even for "single image" pickers. Use `.[0]?.url`.
- In **local dev**, `url` is a path like `/media/abc/image.png` — prefix with the API base URL to load it.
- In **production**, `url` will point at `https://media.your-domain.com/...` (CloudFront in front of S3, Phase 4–6).

### 7.2 Helper

```ts
// in umbracoClient.ts
export function mediaUrl(media: MediaPickerValue): string | null {
  if (!media || media.length === 0) return null;
  const url = media[0].url;
  if (url.startsWith("http")) return url;     // already absolute (production CloudFront)
  return `${API_BASE}${url}`;                  // prefix base in dev
}
```

```tsx
import { mediaUrl } from "../lib/umbracoClient";

<img src={mediaUrl(character.properties.characterImage) ?? "/placeholder.png"} alt={character.properties.characterName} />
```

### 7.3 Image resizing
Umbraco runs ImageSharp out of the box. Append query params to the media URL:

| Parameter | Effect |
|---|---|
| `?width=600` | Resize to 600px wide, keep aspect |
| `?height=400` | Resize to 400px tall |
| `?width=600&height=400&rmode=crop` | Force exact size, crop overflow |
| `?width=600&format=webp` | Convert to WebP |
| `?width=600&quality=80` | JPEG/WebP quality 0–100 |

Example: `<img src={`${mediaUrl(...)}?width=600&format=webp`} />`

### 7.4 What you get when media is NOT uploaded
The property returns `null`. Always guard with `?.` and provide a fallback image.

---

## 8. Block List rendering

The Home page (`home.blocks`) and Standard Pages (`standardPage.blocks`) use Block Lists. Currently empty in test content, but here's how to render them once editors add blocks.

```tsx
// src/components/BlockRenderer.tsx
import type { BlockItem } from "../lib/umbracoTypes";
import { HeroBanner } from "./blocks/HeroBanner";
import { StatBlock } from "./blocks/StatBlock";
import { FeatureCard } from "./blocks/FeatureCard";
import { TimelineItem } from "./blocks/TimelineItem";
import { AccordionItem } from "./blocks/AccordionItem";
import { NewsletterSignup } from "./blocks/NewsletterSignup";
import { LogoStrip } from "./blocks/LogoStrip";
import { BulletList } from "./blocks/BulletList";
import { VideoBlock } from "./blocks/VideoBlock";
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
          case "heroBanner":       return <HeroBanner key={id} {...(properties as any)} />;
          case "statBlock":        return <StatBlock key={id} {...(properties as any)} />;
          case "featureCard":      return <FeatureCard key={id} {...(properties as any)} />;
          case "timelineItem":     return <TimelineItem key={id} {...(properties as any)} />;
          case "accordionItem":    return <AccordionItem key={id} {...(properties as any)} />;
          case "newsletterSignup": return <NewsletterSignup key={id} {...(properties as any)} />;
          case "logoStrip":        return <LogoStrip key={id} {...(properties as any)} />;
          case "bulletList":       return <BulletList key={id} {...(properties as any)} />;
          case "videoBlock":       return <VideoBlock key={id} {...(properties as any)} />;
          case "headingBlock":     return <HeadingBlock key={id} {...(properties as any)} />;
          case "richTextBlock":    return <RichTextBlock key={id} {...(properties as any)} />;
          case "imageBlock":       return <ImageBlock key={id} {...(properties as any)} />;
          case "youtubeBlock":     return <YouTubeBlock key={id} {...(properties as any)} />;
          case "playStoreBlock":   return <PlayStoreBlock key={id} {...(properties as any)} />;
          case "ctaBlock":         return <CtaBlock key={id} {...(properties as any)} />;
          default:
            console.warn(`Unknown block type: ${contentType}`);
            return null;
        }
      })}
    </>
  );
}
```

Then in any page that has a blocks property:

```tsx
{page.properties.blocks?.items && <BlockRenderer blocks={page.properties.blocks.items} />}
```

Example individual block component:

```tsx
// src/components/blocks/HeroBanner.tsx
import type { HeroBannerProps } from "../../lib/umbracoTypes";
import { mediaUrl } from "../../lib/umbracoClient";

export function HeroBanner(p: HeroBannerProps) {
  return (
    <section
      style={{ backgroundImage: `url(${mediaUrl(p.bannerBackgroundImage) ?? ""})` }}
      className="hero-banner"
    >
      <h1>{p.bannerTitle}</h1>
      {p.bannerSubtitle && <p>{p.bannerSubtitle}</p>}
      {p.bannerBody && <p>{p.bannerBody}</p>}
      <div className="ctas">
        {p.ctaPrimaryLabel && <a href={p.ctaPrimaryUrl} className="cta primary">{p.ctaPrimaryLabel}</a>}
        {p.ctaSecondaryLabel && <a href={p.ctaSecondaryUrl} className="cta secondary">{p.ctaSecondaryLabel}</a>}
      </div>
    </section>
  );
}
```

```tsx
// src/components/blocks/StatBlock.tsx
import type { StatBlockProps } from "../../lib/umbracoTypes";

export function StatBlock(p: StatBlockProps) {
  return (
    <div className="stat">
      <div className="stat-value">{p.statValue}</div>
      <div className="stat-label">{p.statLabel}</div>
    </div>
  );
}
```

```tsx
// src/components/blocks/YouTubeBlock.tsx
import type { YouTubeBlockProps } from "../../lib/umbracoTypes";

function extractVideoId(input: string): string | null {
  if (/^[a-zA-Z0-9_-]{11}$/.test(input)) return input;
  const m = input.match(/(?:youtube\.com\/watch\?v=|youtu\.be\/)([a-zA-Z0-9_-]{11})/);
  return m ? m[1] : null;
}

export function YouTubeBlock(p: YouTubeBlockProps) {
  const id = extractVideoId(p.videoUrl);
  if (!id) return null;
  return (
    <figure>
      <div className="aspect-video">
        <iframe
          src={`https://www.youtube.com/embed/${id}`}
          title={p.caption ?? "YouTube video"}
          allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
          allowFullScreen
          style={{ width: "100%", height: "100%" }}
        />
      </div>
      {p.caption && <figcaption>{p.caption}</figcaption>}
    </figure>
  );
}
```

Build out one block component per element type the same way.

---

## 9. Caching & performance

### 9.1 Server-side caching

Umbraco caches Delivery API responses in memory. Repeat requests for the same content are sub-millisecond.

### 9.2 Client-side caching

If you used SWR (recommended):
```ts
import { SWRConfig } from "swr";

<SWRConfig
  value={{
    revalidateOnFocus: false,        // don't re-fetch when user tabs back
    dedupingInterval: 60_000,        // dedupe identical requests within 60s
    errorRetryCount: 2,
  }}
>
  <App />
</SWRConfig>
```

### 9.3 Pre-fetching

For navigation that's predictable (e.g. hovering a link), trigger the fetch early:
```ts
import { mutate } from "swr";
import { getGameBySlug } from "./lib/umbracoClient";

<Link
  to={`/games/${slug}`}
  onMouseEnter={() => mutate(`game/${slug}`, getGameBySlug(slug))}
>
```

### 9.4 SSR / static generation

For SEO-critical pages, fetch at build time:
```ts
// next.js example
export async function getStaticProps() {
  const page = await getPageByPath("/about");
  return { props: { page }, revalidate: 60 };
}
```

---

## 10. Error handling

### 10.1 Network errors
`umbracoFetch` throws on non-2xx. With SWR, capture in `error`:
```tsx
const { data, error, isLoading } = useSWR(...);
if (isLoading) return <Spinner />;
if (error) return <ErrorBoundary />;
if (!data) return <EmptyState />;
```

### 10.2 Common HTTP codes you'll see

| Code | Meaning | Fix |
|---|---|---|
| 200 | OK | — |
| 401 | Unauthorized | Add `Api-Key` header (production only) |
| 404 | Not Found | Slug doesn't exist or content is unpublished |
| 415 | Unsupported Media Type | Add `Accept: application/json` header (the client does this) |
| 500 | Server error | Check Umbraco CloudWatch logs (Phase 10) |

### 10.3 Empty content
If editors haven't published anything yet:
```ts
if (data.total === 0) return <EmptyState />;
```

### 10.4 Failing gracefully
For pages still backed by hard-coded data, feature-flag the migration:
```tsx
const USE_CMS = import.meta.env.VITE_USE_CMS_FOR_GAMES === "true";
return USE_CMS ? <GamesPage /> : <GamesPageLegacy />;
```

---

## 11. Production deployment

### 11.1 Amplify environment variables

Set in the Amplify console → Hosting → Environment variables (per branch):

```
VITE_UMBRACO_API_BASE_URL=https://cms.your-domain.com
VITE_UMBRACO_API_KEY=<32-char-hex from AWS Secrets Manager>
```

### 11.2 CORS on the CMS side

In Umbraco's [appsettings.json](src/MooFamily.Cms.Web/appsettings.json), the `Cors:AllowedOrigins` value must include your Amplify domain. The default is:
```
Cors:AllowedOrigins=http://localhost:3000,http://localhost:5173,https://master.d3boy6qi81n9oz.amplifyapp.com,https://your-domain.com
```

In App Runner, this is configured via the `Cors__AllowedOrigins` env var (Phase 6).

### 11.3 Phase 9 feature-flag rollout

IMPLEMENTATION.md Phase 9 calls for a per-page rollout:
```
VITE_USE_CMS_FOR_HOME=true
VITE_USE_CMS_FOR_ABOUT=true
VITE_USE_CMS_FOR_GAMES=false   # flip when ready
```

This way you can ship pages one at a time without affecting the rest of the site.

---

## 12. Troubleshooting

### "CORS error: Origin … not allowed"
- Check the React dev server's port matches `Cors:AllowedOrigins` in [appsettings.json](src/MooFamily.Cms.Web/appsettings.json).
- Restart the CMS after editing.

### "401 Unauthorized" locally
- `DeliveryApi:PublicAccess` should be `true` in [appsettings.Development.json](src/MooFamily.Cms.Web/appsettings.Development.json). Restart the CMS if you just changed it.

### "404 Not Found" on `/content/item/{slug}`
- The slug is the URL segment, not the node name. `Cow Run` → `cow-run`. Get the exact slug from `route.path` in a list response.
- Make sure the content is **Published** (green dot in the backoffice), not Draft.

### "Connection refused"
- `dotnet run` is not running, or browser cached a stale tab. Hard-refresh (Ctrl+Shift+R) or open a new tab.

### Empty `properties` object in response
- Add `?expand=properties[$all]` to the URL. Without it, properties are not included.

### Images showing as null
- No media uploaded for that property yet. Open the backoffice → edit the node → pick a media item from the Media library → Save & Publish.

### New content types don't appear in API responses
- Add their aliases to `Umbraco:CMS:DeliveryApi:AllowedContentTypeAliases` in [appsettings.json](src/MooFamily.Cms.Web/appsettings.json). Restart Umbraco.

### Filter syntax not working
- `filter=contentType:game` (colon, not equals).
- Multiple filters chain with `&`: `&filter=newsCategory:Events`.
- Date comparisons: `&filter=newsPublishedDate>2024-01-01`.

---

## 13. Appendix: content type alias quick reference

| Doc Type | Alias | Has Children | Where it lives in tree |
|---|---|---|---|
| Home | `home` | yes | Root |
| Settings | `settings` | no | Root |
| Standard Page | `standardPage` | no | Under Home |
| Games Folder | `gamesFolder` | yes (games) | Under Home |
| Stories Folder | `storiesFolder` | yes (stories) | Under Home |
| News Folder | `newsFolder` | yes (newsArticles) | Under Home |
| Characters Folder | `charactersFolder` | yes (characters) | Under Home |
| Team Folder | `teamFolder` | yes (teamMembers) | Under Home |
| Game | `game` | no | Under Games |
| Story | `story` | no | Under Stories |
| News Article | `newsArticle` | no | Under News |
| Character | `character` | no | Under Characters |
| Team Member | `teamMember` | no | Under Team |

**Element types (used inside Block Lists):** `headingBlock`, `richTextBlock`, `imageBlock`, `youtubeBlock`, `playStoreBlock`, `ctaBlock`, `heroBanner`, `statBlock`, `featureCard`, `timelineItem`, `accordionItem`, `newsletterSignup`, `logoStrip`, `logoStripItem`, `bulletList`, `videoBlock`.

---

**End of document.** When the CMS moves to AWS (Phase 4–6) the only React-side change is the env var `VITE_UMBRACO_API_BASE_URL` and adding the `VITE_UMBRACO_API_KEY`. Everything else stays.
