# Platform icons

Source assets for `game.gamePlatformLinks` → `platformIcon`.

`wwwroot/media/` is gitignored (binaries live in S3), so the canonical copies live here
and `scripts/backfill-game-platforms.ps1` uploads them.

| Platform | File | Media type | Media node key |
|---|---|---|---|
| Steam | `steam.png` *(generated)* | `Image` | `57e28fe0-2635-4992-b913-f15c18434f00` |
| Epic Games | `epic-games.svg` | `umbracoMediaVectorGraphics` | `a98c8460-30e7-48aa-b34a-1a97929d3d20` |
| Apple App Store | `apple-app-store.svg` | `umbracoMediaVectorGraphics` | `d18a1e40-93cf-4428-a48e-a2d6f40b34b8` |
| Google Play | `google-play.svg` | `umbracoMediaVectorGraphics` | `31c7d1e7-00a5-4cac-adff-3ec5972dac55` |
| Browser | `browser.svg` | `umbracoMediaVectorGraphics` | `3b839eb0-f467-49ae-8f8d-936a0312f4e6` |
| PC | `pc.svg` | `umbracoMediaVectorGraphics` | `8d590b04-398e-4b2f-8621-7a7d6377f795` |

Keys are deterministic — `MD5("moofamily-media:media:<Node Name>")` with the version and variant
bits forced. Re-running the backfill is idempotent.

## Why this script's GUID function differs from `backfill-media.ps1`

`backfill-media.ps1` forces the version nibble into `$bytes[6]`, but `[Guid]::new(byte[])` reads
bytes 6–7 as a **little-endian** Int16 — so `$bytes[6]` is the *low* byte of Data3 and the version
nibble actually comes from `$bytes[7]`. The keys it produces therefore carry an arbitrary version
(the existing `Cow Run Cover` is v5, `Universe Where Kids Learn Hero` is v1).

That is not cosmetic. Umbraco's `IMediaPathScheme` **rejects** v7 media keys:

> The registered implementation of IMediaPathScheme cannot be used with media keys using
> version 7 GUIDs due to an increased risk of collisions in the generated file paths.

Two of these six icons originally hashed to v7 (Steam and Apple App Store). The media items
failed to import and every `platformIcon` pointing at them came back empty — the Apple badge was
missing from Moo Crush and Moo Tag. `backfill-game-platforms.ps1` therefore sets `$bytes[7]`, which
genuinely yields v4.

`backfill-media.ps1` is deliberately left alone: changing it would alter all 28 existing media keys
and invalidate every MediaPicker value already committed to content. If you add media with that
script, check the version nibble of the resulting key and rename the node if it lands on v7.

## Steam — needs one manual step

The Steam asset from design is **not a vector**: it is a 659×659 base64 PNG wrapped in an
`<svg>` element (~110–530 KB). Umbraco's ImageSharp middleware does not process SVG, so
`?width=48` would be ignored and the full payload would ship on every game card.

So Steam is stored as a normal `Image` media item instead, and the icon set is mixed
(1 raster + 5 vector). The `Icon Media Picker (Image or SVG)` DataType accepts both.

**To generate it:** drop the original design export at

    scripts/assets/platform-icons/steam-source.svg

then run

    pwsh scripts/backfill-game-platforms.ps1 -RasteriseOnly

which extracts the embedded PNG, resizes it to 64×64 and writes `steam.png`.
`steam-source.svg` is gitignored — only the generated `steam.png` is committed.

If you can source a genuine vector Steam mark, prefer that: drop it in as `steam.svg`,
delete `steam.png`, and change the Steam row in `$IconMap` to `MediaType = 'svg'`.
Tracked in `CONTENT_AUDIT_PUNCHLIST.md`.

## Browser / PC

`browser.svg` and `pc.svg` are neutral placeholder glyphs drawn to match the stroke weight
of the supplied brand icons. Design has not supplied brand assets for these two platforms —
also tracked in the punchlist. Replace the files and re-run the backfill; the media keys
do not change.

## Colour

The Apple, Browser and PC glyphs are `fill="white"` / `stroke="white"`, matching the Figma
game cards where icons sit on dark cover art. They will be invisible on a light background —
the frontend should render them on the card image or apply a filter.
