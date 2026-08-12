#!/usr/bin/env python3
"""Validate every JSON payload embedded in uSync content/media configs.

Block List, MediaPicker3 and dropdown values are all stored as JSON inside CDATA. A single
malformed payload breaks the uSync import with an unhelpful error, so this sweeps the whole
tree before committing. A previous bug (commit dc43b93) shipped non-hex GUIDs in block keys,
so keys are checked too.

    python scripts/validate-usync-json.py
"""

from __future__ import annotations

import json
import re
import sys
import uuid
from pathlib import Path

USYNC = Path(__file__).resolve().parent.parent / "src" / "MooFamily.Cms.Web" / "uSync" / "v17"

# <alias><Value><![CDATA[ ... ]]></Value></alias>
CDATA = re.compile(r"<(?P<alias>[A-Za-z][\w.]*)>\s*<Value>\s*<!\[CDATA\[(?P<body>.*?)\]\]>", re.S)
GUID_KEYS = ("key", "contentKey", "mediaKey", "contentTypeKey", "settingsKey")


def walk_guids(node, found: list[tuple[str, str]]) -> None:
    if isinstance(node, dict):
        for k, v in node.items():
            if k in GUID_KEYS and isinstance(v, str) and v:
                found.append((k, v))
            else:
                walk_guids(v, found)
    elif isinstance(node, list):
        for item in node:
            walk_guids(item, found)


def inspect(parsed, label: str, problems: list[str]) -> None:
    """Validate one JSON payload, then recurse into any nested Block List it contains.

    Block List values nested inside another Block List are stored as a JSON *string*
    containing JSON, so they are not reached by parsing the outer payload alone.
    """
    guids: list[tuple[str, str]] = []
    walk_guids(parsed, guids)

    for field, value in guids:
        try:
            uuid.UUID(value)
        except ValueError:
            problems.append(f"{label}: {field} is not a valid GUID — {value!r}")

    # Block List payloads must keep contentData, layout and expose in agreement,
    # otherwise blocks silently vanish from the Delivery API output.
    if isinstance(parsed, dict) and "contentData" in parsed:
        content_keys = {c.get("key") for c in parsed.get("contentData", [])}
        layout_keys = {
            item.get("contentKey")
            for layouts in parsed.get("layout", {}).values()
            for item in layouts
        }
        exposed = {e.get("contentKey") for e in parsed.get("expose", [])}

        if orphaned := layout_keys - content_keys:
            problems.append(f"{label}: layout references missing contentData — {sorted(orphaned)}")
        if unlaid := content_keys - layout_keys:
            problems.append(f"{label}: contentData not in layout — {sorted(unlaid)}")
        if parsed.get("expose") is not None and (unexposed := content_keys - exposed):
            problems.append(f"{label}: contentData not exposed — {sorted(unexposed)}")

        for block in parsed.get("contentData", []):
            for value in block.get("values", []):
                raw = value.get("value")
                if not isinstance(raw, str):
                    continue
                stripped = raw.strip()
                if not stripped or stripped[0] not in "[{":
                    continue
                try:
                    nested = json.loads(stripped)
                except json.JSONDecodeError as exc:
                    problems.append(
                        f"{label} > {value.get('alias')}: invalid nested JSON at char {exc.pos} — {exc.msg}"
                    )
                    continue
                inspect(nested, f"{label} > {value.get('alias')}", problems)


def check(path: Path) -> list[str]:
    problems: list[str] = []
    text = path.read_text(encoding="utf-8")

    for match in CDATA.finditer(text):
        body = match.group("body").strip()
        alias = match.group("alias")

        # Only JSON-looking payloads; plain strings, HTML and file paths are fine as-is.
        if not body or body[0] not in "[{":
            continue

        try:
            parsed = json.loads(body)
        except json.JSONDecodeError as exc:
            problems.append(f"{alias}: invalid JSON at char {exc.pos} — {exc.msg}")
            continue

        inspect(parsed, alias, problems)

    return problems


def main() -> int:
    files = sorted(USYNC.rglob("*.config"))
    failures = 0
    checked = 0

    for path in files:
        problems = check(path)
        checked += 1
        if problems:
            failures += 1
            rel = path.relative_to(USYNC)
            print(f"\n{rel}")
            for problem in problems:
                print(f"  - {problem}")

    print(f"\nChecked {checked} config file(s); {failures} with problems.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
