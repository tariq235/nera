#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""A11Y-010: every icon-only button has a VoiceOver label (and, on macOS, a tooltip).

A `Button` whose label shows only an image (`Image(systemName:)`, `Image(nsImage:)`…) and no text must carry
`.accessibilityLabel(…)` or `.help(…)` (SwiftUI reads `.help` as the label too) in the modifiers right after it.
Buttons built on a labeled helper (`SidebarIconButton(symbol:help:)`) pass by construction.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCES = [ROOT / "Packages/NeraKit/Sources", ROOT / "Apps"]
BUTTON = re.compile(r"\bButton\s*(\(|\{)")
TEXTUAL = re.compile(r"\b(Text|Label|TextField)\s*\(|Button\(\s*\"|Button\(\s*[a-z]\w*\s*[,)]")
IMAGE = re.compile(r"\bImage\s*\(")
NAMED = re.compile(r"\.(accessibilityLabel|help)\s*\(")


def matching(text: str, start: int, open_ch: str, close_ch: str) -> int:
    depth = 0
    for i in range(start, len(text)):
        if text[i] == open_ch:
            depth += 1
        elif text[i] == close_ch:
            depth -= 1
            if depth == 0:
                return i
    return len(text)


def check(path: Path, errors: list[str]) -> None:
    text = path.read_text(errors="ignore")
    for m in BUTTON.finditer(text):
        head_end = m.end()
        # Button("Title") / Button(title) forms are textual.
        if TEXTUAL.match(text, m.start()):
            continue
        if m.group(1) == "(":
            close = matching(text, m.end() - 1, "(", ")")
            args = text[m.end() - 1 : close + 1]
            if re.search(r"\"", args.split("action")[0]) or "label:" not in args and "{" not in text[close : close + 3]:
                continue  # Button("…", action:) or Button(role:, action:) with a textual first argument
            body_start = text.find("{", close)
        else:
            body_start = m.end() - 1
        if body_start < 0:
            continue
        body_end = matching(text, body_start, "{", "}")
        label = text[body_start : body_end + 1]
        # `Button { action } label: { … }`: the label is the second closure.
        rest = text[body_end + 1 : body_end + 12]
        if rest.lstrip().startswith("label:"):
            second = text.find("{", body_end + 1)
            label_end = matching(text, second, "{", "}")
            label = text[second : label_end + 1]
            body_end = label_end
        if not IMAGE.search(label) or TEXTUAL.search(label):
            continue
        modifiers = text[body_end + 1 : body_end + 600]
        cut = re.search(r"\n\s*(?!\.|#|//)\S", modifiers)  # the chain ends at the first line not starting with "."
        modifiers = modifiers[: cut.start()] if cut else modifiers
        if NAMED.search(label) or NAMED.search(modifiers):
            continue
        line = text.count("\n", 0, m.start()) + 1
        errors.append(f"{path.relative_to(ROOT)}:{line}: icon-only button without .accessibilityLabel or .help")


def main() -> int:
    errors: list[str] = []
    files = [f for base in SOURCES for f in base.rglob("*.swift") if "/.build/" not in str(f)]
    for f in files:
        check(f, errors)
    for e in errors:
        print(f"✘ {e}")
    if errors:
        return 1
    print(f"✔ icon-only buttons are labeled ({len(files)} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
