#!/usr/bin/env python3
"""
update-appcast.py — Insert a new release item into appcast.xml.

Usage:
    python3 scripts/update-appcast.py \
        --version 0.1.0 \
        --build 1 \
        --url https://github.com/.../Knok-0.1.0.dmg \
        --signature <EdDSA-base64> \
        --size 12345678
"""

import argparse
import re
from datetime import datetime, timezone
from pathlib import Path

APPCAST_PATH = Path(__file__).parent.parent / "appcast.xml"

ITEM_TEMPLATE = """\
    <item>
      <title>Version {version}</title>
      <pubDate>{pub_date}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <enclosure
        url="{url}"
        sparkle:edSignature="{signature}"
        length="{size}"
        type="application/octet-stream"
      />
    </item>"""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--signature", required=True)
    parser.add_argument("--size", required=True, type=int)
    args = parser.parse_args()

    pub_date = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S %z")

    new_item = ITEM_TEMPLATE.format(
        version=args.version,
        build=args.build,
        url=args.url,
        signature=args.signature,
        size=args.size,
        pub_date=pub_date,
    )

    content = APPCAST_PATH.read_text()

    # Insert before closing </channel> tag
    if "</channel>" not in content:
        raise ValueError("appcast.xml is malformed — missing </channel>")

    updated = content.replace("</channel>", f"{new_item}\n  </channel>")
    APPCAST_PATH.write_text(updated)

    print(f"appcast.xml updated with v{args.version} (build {args.build})")


if __name__ == "__main__":
    main()
