#!/usr/bin/env python3
"""Seed the News section to match the Figma designs.

Three things:

  1. Backfills ``newsTags`` on the six existing articles so every card badge in the listing
     design has a value behind it.
  2. Creates the three articles the Figma shows but the CMS does not have — the
     "Guide to Understanding Children Development Stages" detail page (with its five
     ``newsBodySection`` blocks and inline image) plus the two "Latest Articles" entries.
  3. Appends the six new categories to the listing's filter chips.

Idempotent: re-running rewrites the same values rather than duplicating them.

Content is NOT imported on boot (uSync ImportAtStartup=Settings), so after running this you
must import the Content handler from the backoffice uSync dashboard.

    python scripts/seed-news-figma.py [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
USYNC = REPO / "src" / "MooFamily.Cms.Web" / "uSync" / "v17"
NEWS_DIR = USYNC / "Content" / "Home" / "News"
NEWS_FOLDER = USYNC / "Content" / "Home" / "News.config"

NEWS_PARENT_KEY = "f1a00012-0000-0000-0000-000000000012"
ARTICLE_TYPE = "newsArticle"

# Element type keys
SECTION_TYPE = "f4a00033-0000-0000-0000-000000000033"
BULLET_TYPE = "f3a00019-0000-0000-0000-000000000019"
IMAGE_TYPE = "b6ca10b0-b095-4db6-b95f-d82e9b01bd08"
CHIP_TYPE = "f4a00021-0000-0000-0000-000000000021"

BAR_RED = "e4572e"
BAR_OLIVE = "b5a642"

# ------------------------------------------------------------------ tag backfill
# Chosen so the card badges in the listing design have real values behind them.
EXISTING_TAGS = {
    "UniverseWhereKidsLearn.config": ["Education", "Early Education"],
    "MultiplayerExperiences.config": ["Socials", "Activities"],
    "StoriesThatTeach.config": ["Education", "Creative Kids"],
    "NewAdventures.config": ["Activities", "Kindergarten Events"],
    "LearningWithLittleJack.config": ["Education", "Music"],
    "PlayInCompetitiveTournaments.config": ["Activities", "Socials"],
}

# ------------------------------------------------------------------ new categories
NEW_CHIPS = [
    "Early Learning",
    "Parenting Tips",
    "Creative Arts",
    "Science Exploration",
    "School Events",
    "Teacher Features",
]

# ------------------------------------------------------------------ body sections
#
# Headings, bar colours and the first two sections' copy come straight from the Figma.
# Sections 3-5 repeat section 2's placeholder text in the design; real copy is written here
# instead of shipping the duplicate. Flagged in CONTENT_AUDIT_PUNCHLIST.md for final copy.
SECTIONS = [
    (
        "The Core Idea",
        "Children don't learn best through instructions — they learn through experiences.\n"
        "In Cow Paradise, learning happens through:",
        ["Playing games", "Watching stories", "Interacting with characters"],
        BAR_RED,
    ),
    (
        "Learning Through Gameplay",
        "Every game inside Cow Paradise is structured around simple but meaningful outcomes:",
        [
            "Decision-making through challenges",
            "Focus and timing through gameplay mechanics",
            "Problem-solving through levels and obstacles",
        ],
        BAR_OLIVE,
    ),
    (
        "Learning Through Stories",
        "Every Moo Family episode is built around a moment a child can recognise from their own week:",
        [
            "Naming a feeling before reacting to it",
            "Seeing a mistake repaired rather than hidden",
            "Watching patience pay off across a whole episode",
        ],
        BAR_OLIVE,
    ),
    (
        "Characters That Teach Without Teaching",
        "The Moo Family never lecture. Each character models one habit consistently enough "
        "that children pick it up on their own:",
        [
            "Little Jack asks for help when he is stuck",
            "Ellie tries again after something goes wrong",
            "Lulu makes room for whoever is left out",
        ],
        BAR_OLIVE,
    ),
    (
        "One Connected World",
        "Because games, stories and characters share a single world, a lesson met in one place "
        "is reinforced somewhere else:",
        [
            "A character from a story turns up in a game",
            "A skill practised in a game reappears in an episode",
            "Progress carries across the whole universe",
        ],
        BAR_OLIVE,
    ),
]

INLINE_IMAGE_MEDIA = "ed000002-0000-0000-0000-000000000002"  # Smart Learning Kids
INLINE_IMAGE_ALT = "A young calf resting by the shore, looking out at the islands"

# ------------------------------------------------------------------ new articles

ARTICLES = [
    {
        "file": "ChildrenDevelopmentStages.config",
        "key": "f1a00046-0000-0000-0000-000000000046",
        "name": "Guide to Understanding Children Development Stages",
        "title": "Guide to Understanding Children Development Stages",
        "excerpt": "How Cow Paradise blends games, stories and characters into one world where every "
                   "interaction moves a child forward.",
        "body": "<p>Cow Paradise is designed as a connected world where games, stories, and characters "
                "work together to help children learn naturally. Instead of separating entertainment "
                "and education, the platform blends both into a single experience where every "
                "interaction contributes to growth.</p>",
        "hero": "c8401acf-10d7-1841-afd2-7d7ae50ee67c",  # Universe Where Kids Learn Hero
        "date": "2024-07-08T00:00:00",
        "category": "Early Learning",
        "tags": ["Education", "Parenting", "Early Education"],
        "sort": 6,
        "related": [
            "f1a00047-0000-0000-0000-000000000047",
            "f1a00048-0000-0000-0000-000000000048",
        ],
        "sections": True,
    },
    {
        "file": "TeachShapesAndColors.config",
        "key": "f1a00047-0000-0000-0000-000000000047",
        "name": "Innovative Ways to Teach Shapes and Colors to Your Children at Home",
        "title": "Innovative Ways to Teach Shapes and Colors to Your Children at Home",
        "excerpt": "Simple, screen-light activities that turn everyday objects around the house into "
                   "a first lesson in shape and colour.",
        "body": "<p>Shapes and colours are the first vocabulary a child has for describing the world, "
                "and they are learned fastest away from a worksheet.</p>"
                "<p>These activities need nothing you do not already own, and each one takes about "
                "ten minutes.</p>",
        "hero": "0cf3ebbb-bc50-b442-8645-0dd01870001b",  # Learning With Little Jack Hero
        "date": "2024-05-15T00:00:00",
        "category": "Creative Arts",
        "tags": ["Education", "Creative Kids", "Activities"],
        "sort": 7,
        "related": [],
        "sections": False,
    },
    {
        "file": "EducationalBooksPreschoolers.config",
        "key": "f1a00048-0000-0000-0000-000000000048",
        "name": "Top 5 Educational Books for Preschoolers in 2024: From Music to Math",
        "title": "Top 5 Educational Books for Preschoolers in 2024: From Music to Math",
        "excerpt": "Five titles that hold a preschooler's attention and quietly build early numeracy, "
                   "rhythm and vocabulary.",
        "body": "<p>A good preschool book earns a second reading. These five did, in living rooms and "
                "classrooms alike, across the past year.</p>"
                "<p>Each pick is grouped by the skill it builds, so you can match a book to whatever "
                "your child is working on right now.</p>",
        "hero": "78e32be3-12ff-a441-8501-2082eba70ef6",  # Stories That Teach Hero
        "date": "2024-06-21T00:00:00",
        "category": "Parenting Tips",
        "tags": ["Education", "Music", "Parenting"],
        "sort": 8,
        "related": [],
        "sections": False,
    },
]

ARTICLE_TEMPLATE = """<?xml version="1.0" encoding="utf-8"?>
<Content Key="{key}" Alias="newsArticle" Level="3">
  <Info>
    <Parent Key="{parent}">News</Parent>
    <Path>/Home/News/{name}</Path>
    <Trashed Locked="False">False</Trashed>
    <ContentType>newsArticle</ContentType>
    <CreateDate>2026-08-12T00:00:00</CreateDate>
    <NodeName Default="{name}" />
    <SortOrder>{sort}</SortOrder>
    <Published Default="true" />
    <Schedule />
    <Template Key="00000000-0000-0000-0000-000000000000" />
  </Info>
  <Properties>
    <newsTitle>
      <Value><![CDATA[{title}]]></Value>
    </newsTitle>
    <newsExcerpt>
      <Value><![CDATA[{excerpt}]]></Value>
    </newsExcerpt>
    <newsBody>
      <Value><![CDATA[{body}]]></Value>
    </newsBody>
    <newsHeroImage>
      <Value><![CDATA[{hero}]]></Value>
    </newsHeroImage>
    <newsPublishedDate>
      <Value><![CDATA[{date}]]></Value>
    </newsPublishedDate>
    <newsCategory>
      <Value><![CDATA[{category}]]></Value>
    </newsCategory>
    <newsTags>
      <Value><![CDATA[{tags}]]></Value>
    </newsTags>
    <newsRelatedArticles>
      <Value><![CDATA[{related}]]></Value>
    </newsRelatedArticles>
    <newsBodyBlocks>
      <Value><![CDATA[{blocks}]]></Value>
    </newsBodyBlocks>
  </Properties>
</Content>
"""


def value(alias: str, editor: str, val: str) -> dict:
    return {"culture": None, "editorAlias": editor, "alias": alias, "value": val, "segment": None}


def block_list(content_data: list[dict]) -> dict:
    keys = [c["key"] for c in content_data]
    return {
        "contentData": content_data,
        "settingsData": [],
        "layout": {"Umbraco.BlockList": [{"contentKey": k} for k in keys]},
        "expose": [{"culture": None, "contentKey": k, "segment": None} for k in keys],
    }


def ordered_block_list(content_data: list[dict], order: list[str]) -> dict:
    """Same as block_list but with an explicit layout order (the Figma puts the inline
    image between sections two and three)."""
    payload = block_list(content_data)
    payload["layout"]["Umbraco.BlockList"] = [{"contentKey": k} for k in order]
    payload["expose"] = [{"culture": None, "contentKey": k, "segment": None} for k in order]
    return payload


def media_picker(entry_key: str, media_key: str, type_alias: str = "Image") -> str:
    return json.dumps(
        [{"key": entry_key, "mediaKey": media_key, "mediaTypeAlias": type_alias,
          "crops": [], "focalPoint": None}],
        separators=(",", ":"),
    )


def build_body_blocks(prefix: str) -> str:
    content_data: list[dict] = []
    section_keys: list[str] = []
    bullet_index = 0

    for section_index, (heading, intro, bullets, colour) in enumerate(SECTIONS, start=1):
        section_key = f"{prefix}-0001-0000-0000-{section_index:012d}"
        section_keys.append(section_key)

        bullet_blocks = []
        for text in bullets:
            bullet_index += 1
            bullet_blocks.append({
                "contentTypeKey": BULLET_TYPE,
                "key": f"{prefix}-0002-0000-0000-{bullet_index:012d}",
                "values": [
                    value("bulletText", "Umbraco.TextBox", text),
                    value("bulletIcon", "Umbraco.MediaPicker3", ""),
                ],
            })

        content_data.append({
            "contentTypeKey": SECTION_TYPE,
            "key": section_key,
            "values": [
                value("newsBodySectionHeading", "Umbraco.TextBox", heading),
                value("newsBodySectionIntro", "Umbraco.TextArea", intro),
                value("newsBodySectionBullets", "Umbraco.BlockList",
                      json.dumps(block_list(bullet_blocks), separators=(",", ":"))),
                value("newsBodySectionBarColor", "Umbraco.ColorPicker", colour),
            ],
        })

    image_key = f"{prefix}-0003-0000-0000-000000000001"
    content_data.append({
        "contentTypeKey": IMAGE_TYPE,
        "key": image_key,
        "values": [
            value("image", "Umbraco.MediaPicker3",
                  media_picker(f"{prefix}-0003-0001-0000-000000000001", INLINE_IMAGE_MEDIA)),
            value("altText", "Umbraco.TextBox", INLINE_IMAGE_ALT),
            value("caption", "Umbraco.TextBox", ""),
            value("alignment", "Umbraco.DropDown.Flexible", ""),
        ],
    })

    # Figma order: section 1, section 2, image, sections 3-5.
    order = section_keys[:2] + [image_key] + section_keys[2:]

    return json.dumps(ordered_block_list(content_data, order), separators=(",", ":"))


def udi(guid: str) -> str:
    return "umb://document/" + guid.replace("-", "")


def upsert_property(text: str, alias: str, payload: str, after: str) -> str:
    """Replace <alias> if present, otherwise insert it after the </after> tag."""
    block = f"    <{alias}>\n      <Value><![CDATA[{payload}]]></Value>\n    </{alias}>\n"
    open_tag, close_tag = f"<{alias}>", f"</{alias}>"

    start = text.find(open_tag)
    if start >= 0:
        end = text.find(close_tag, start)
        if end < 0:
            raise ValueError(f"unbalanced <{alias}>")
        line_start = text.rfind("\n", 0, start) + 1
        return text[:line_start] + block + text[end + len(close_tag):].lstrip("\r\n")

    anchor = text.find(f"</{after}>")
    if anchor < 0:
        raise ValueError(f"anchor </{after}> not found")
    insert_at = text.find("\n", anchor) + 1
    return text[:insert_at] + block + text[insert_at:]


def backfill_tags(dry_run: bool) -> int:
    changed = 0
    for filename, tags in EXISTING_TAGS.items():
        path = NEWS_DIR / filename
        if not path.exists():
            print(f"  ! missing {filename}")
            continue
        text = path.read_text(encoding="utf-8")
        payload = json.dumps(tags, separators=(",", ":"))
        patched = upsert_property(text, "newsTags", payload, after="newsCategory")
        if patched != text:
            changed += 1
            if not dry_run:
                path.write_text(patched, encoding="utf-8", newline="")
        print(f"  {'[dry] ' if dry_run else ''}{filename}: {tags}")
    return changed


def write_articles(dry_run: bool) -> int:
    written = 0
    for article in ARTICLES:
        blocks = build_body_blocks("fc0000" + article["key"][6:8]) if article["sections"] else ""
        xml = ARTICLE_TEMPLATE.format(
            key=article["key"],
            parent=NEWS_PARENT_KEY,
            name=article["name"],
            sort=article["sort"],
            title=article["title"],
            excerpt=article["excerpt"],
            body=article["body"],
            hero=media_picker(article["key"][:8] + "-0000-0001-0000-000000000001", article["hero"]),
            date=article["date"],
            category=json.dumps([article["category"]], separators=(",", ":")),
            tags=json.dumps(article["tags"], separators=(",", ":")),
            related=",".join(udi(g) for g in article["related"]),
            blocks=blocks,
        )
        path = NEWS_DIR / article["file"]
        print(f"  {'[dry] ' if dry_run else ''}{article['file']}  sort={article['sort']}  "
              f"category={article['category']}  blocks={'yes' if blocks else 'no'}")
        if not dry_run:
            path.write_text(xml, encoding="utf-8", newline="")
        written += 1
    return written


def append_chips(dry_run: bool) -> int:
    text = NEWS_FOLDER.read_text(encoding="utf-8")
    match = re.search(r"<blocks>.*?CDATA\[(.*?)\]\]>", text, re.S)
    if not match:
        raise ValueError("no <blocks> value on News.config")

    outer = json.loads(match.group(1))
    grid = next(c for c in outer["contentData"] if c["contentTypeKey"] == "f4a00004-0000-0000-0000-000000000004")
    filters_value = next(v for v in grid["values"] if v["alias"] == "entityGridFilters")
    chips = json.loads(filters_value["value"])

    existing = {
        next(v["value"] for v in c["values"] if v["alias"] == "filterChipValue")
        for c in chips["contentData"]
    }

    added = 0
    for offset, label in enumerate(NEW_CHIPS, start=7):
        if label in existing:
            continue
        key = f"ac{offset:06d}-0000-0000-0000-{offset:012d}"
        chips["contentData"].append({
            "contentTypeKey": CHIP_TYPE,
            "key": key,
            "values": [
                value("filterChipLabel", "Umbraco.TextBox", label),
                value("filterChipValue", "Umbraco.TextBox", label),
            ],
        })
        chips["layout"]["Umbraco.BlockList"].append({"contentKey": key})
        chips["expose"].append({"culture": None, "contentKey": key, "segment": None})
        added += 1
        print(f"  {'[dry] ' if dry_run else ''}chip: {label}  ({key})")

    if added and not dry_run:
        filters_value["value"] = json.dumps(chips, separators=(",", ":"))
        patched = text[:match.start(1)] + json.dumps(outer, separators=(",", ":")) + text[match.end(1):]
        NEWS_FOLDER.write_text(patched, encoding="utf-8", newline="")

    return added


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    print("Backfilling tags on existing articles")
    tagged = backfill_tags(args.dry_run)

    print("\nWriting Figma articles")
    written = write_articles(args.dry_run)

    print("\nAppending filter chips")
    chips = append_chips(args.dry_run)

    print(f"\n{tagged} tagged, {written} written, {chips} chip(s) added.")
    print("Content does NOT import on boot — run Settings > uSync > Import (Content handler).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
