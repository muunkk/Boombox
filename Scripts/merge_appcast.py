#!/usr/bin/env python3
"""Merge a single-version Sparkle appcast item into the persistent appcast.

Usage: merge_appcast.py <generated-appcast.xml> <persistent-appcast.xml> [max_items]

`generate_appcast` is run over a directory containing ONLY the current release's
DMG, so the generated appcast holds exactly one <item> with the correct per-version
GitHub download URL and EdDSA signature (and no cross-version delta items). This
script extracts that item and merges it into the persistent, committed appcast:

  • replaces any existing item with the same <sparkle:version> (idempotent re-release)
  • keeps the newest `max_items` items (default 10), newest first
  • rebuilds the channel deterministically, preserving each item's own enclosure URL

Doing the merge per-version is what avoids the `--download-url-prefix` foot-gun where
one prefix rewrites every release's URL to the current tag (404-ing older versions).
"""
import os
import re
import sys

ITEM_RE = re.compile(r"<item>.*?</item>", re.S)
VERSION_RE = re.compile(r"<sparkle:version>\s*([^<\s]+)\s*</sparkle:version>")


def build_version(item: str) -> int:
    """Return the integer CFBundleVersion in an item, or -1 if absent/non-numeric."""
    match = VERSION_RE.search(item)
    if match and match.group(1).isdigit():
        return int(match.group(1))
    return -1


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit("Usage: merge_appcast.py <generated-appcast.xml> <persistent-appcast.xml> [max_items]")
    gen_path, persist_path = sys.argv[1], sys.argv[2]
    max_items = int(sys.argv[3]) if len(sys.argv) > 3 else 10

    with open(gen_path, encoding="utf-8") as handle:
        generated = handle.read()
    gen_items = ITEM_RE.findall(generated)
    if len(gen_items) != 1:
        sys.exit("ERROR: expected exactly one <item> in %s, found %d" % (gen_path, len(gen_items)))
    new_item = gen_items[0]
    new_version = build_version(new_item)

    existing_items: list[str] = []
    if os.path.exists(persist_path):
        with open(persist_path, encoding="utf-8") as handle:
            existing_items = ITEM_RE.findall(handle.read())

    # Drop any existing item with the same build version, then add the new one.
    items = [item for item in existing_items if build_version(item) != new_version]
    items.append(new_item)
    items.sort(key=build_version, reverse=True)
    items = items[:max_items]

    body = "\n".join("    " + item for item in items)
    out = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<rss version="2.0" '
        'xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/">\n'
        "  <channel>\n"
        "    <title>Boombox</title>\n"
        "    <description>Most recent updates to Boombox</description>\n"
        "    <language>en</language>\n"
        "%s\n"
        "  </channel>\n"
        "</rss>\n"
    ) % body
    with open(persist_path, "w", encoding="utf-8") as handle:
        handle.write(out)
    print("merged build %s; appcast now lists %d version(s)" % (new_version, len(items)))


if __name__ == "__main__":
    main()
