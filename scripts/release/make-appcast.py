#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""Adds one release to a Sparkle-format appcast (REL-007, REL-012), or pulls one (REL-013). Items are kept newest
first; an existing item with the same build is replaced. The feed format matches what Packages/NeraKit/Sources/Update
parses.

  make-appcast.py --feed appcast.xml --build 42 --version 0.3.0 --channel beta \
      --url https://…/Nera-0.3.0.dmg --signature <b64> --length <bytes> [--min-os 15.0] [--rollout-days 1] [--critical]
  make-appcast.py --feed appcast.xml --remove 42     pull a bad update (docs/release-emergency.md); upload the feed
"""
import argparse
import email.utils
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)
S = f"{{{SPARKLE}}}"


def build_of(item: ET.Element) -> str | None:
    """The item's build, wherever the app's parser accepts it: the item's sparkle:version, or the enclosure's."""
    version = item.findtext(f"{S}version")
    if version is None and (enclosure := item.find("enclosure")) is not None:
        version = enclosure.get(f"{S}version")
    return version.strip() if version else None


def remove(feed: Path, build: int) -> int:
    tree = ET.parse(feed)
    channel = tree.getroot().find("channel")
    pulled = [i for i in channel.findall("item") if build_of(i) == str(build)]
    if not pulled:
        print(f"✘ build {build} isn't in {feed}", file=sys.stderr)
        return 1
    for item in pulled:
        channel.remove(item)
    ET.indent(tree)
    tree.write(feed, encoding="utf-8", xml_declaration=True)
    left = [build_of(i) for i in channel.findall("item")]
    print(f"✔ build {build} pulled from {feed}; builds still offered: {', '.join(b or '?' for b in left) or 'none'}. Upload it now.")
    return 0


def main() -> int:
    if "--remove" in sys.argv:
        ap = argparse.ArgumentParser()
        ap.add_argument("--feed", required=True, type=Path)
        ap.add_argument("--remove", required=True, type=int)
        r = ap.parse_args()
        return remove(r.feed, r.remove)
    ap = argparse.ArgumentParser()
    ap.add_argument("--feed", required=True, type=Path)
    ap.add_argument("--build", required=True, type=int)
    ap.add_argument("--version", required=True)
    ap.add_argument("--channel", choices=["stable", "beta", "nightly"], default="stable")
    ap.add_argument("--url", required=True)
    ap.add_argument("--signature", required=True)
    ap.add_argument("--length", required=True, type=int)
    ap.add_argument("--min-os", default="15.0")
    ap.add_argument("--rollout-days", type=float, default=0)
    ap.add_argument("--critical", action="store_true")
    a = ap.parse_args()

    if not a.url.startswith("https://"):
        print("✘ update URLs must be HTTPS", file=sys.stderr)
        return 1

    if a.feed.exists():
        tree = ET.parse(a.feed)
        rss = tree.getroot()
        channel = rss.find("channel")
    else:
        rss = ET.Element("rss", {"version": "2.0"})
        channel = ET.SubElement(rss, "channel")
        ET.SubElement(channel, "title").text = "Nera"
        tree = ET.ElementTree(rss)

    for old in channel.findall("item"):
        if build_of(old) == str(a.build):
            channel.remove(old)

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Nera {a.version}"
    ET.SubElement(item, "pubDate").text = email.utils.formatdate(usegmt=True)
    ET.SubElement(item, f"{S}version").text = str(a.build)
    ET.SubElement(item, f"{S}shortVersionString").text = a.version
    if a.channel != "stable":
        ET.SubElement(item, f"{S}channel").text = a.channel
    ET.SubElement(item, f"{S}minimumSystemVersion").text = a.min_os
    if a.rollout_days > 0 and not a.critical:
        ET.SubElement(item, f"{S}phasedRolloutInterval").text = str(int(a.rollout_days * 86400))
    if a.critical:
        ET.SubElement(item, f"{S}criticalUpdate")
    ET.SubElement(item, "enclosure", {
        "url": a.url, "length": str(a.length), "type": "application/octet-stream", f"{S}edSignature": a.signature,
    })

    first_item = next((i for i, child in enumerate(channel) if child.tag == "item"), len(channel))
    channel.insert(first_item, item)
    ET.indent(tree)
    tree.write(a.feed, encoding="utf-8", xml_declaration=True)
    print(f"✔ appcast: added {a.version} ({a.build}) on {a.channel}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
