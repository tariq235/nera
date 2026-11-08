#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""Enforce Nera's architecture rules (docs/standards/architecture-principles.md).

1. Layering: a target may depend only on lower layers (plus a few declared same-layer edges).
2. Engine independence (AP-1): engine adapters are depended on only by the apps and their own tests;
   WebKit/CEF APIs appear only inside their adapter; no `#if canImport(WebKit)` elsewhere.
3. Test-only modules never ship.
4. Framework allowlist per target (e.g. L0 = Foundation only, so it stays portable to Linux).
5. Forbidden APIs: certificate-trust overrides (SR-002) and sandbox-weakening Chromium switches (SR-020).
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PKG = ROOT / "Packages" / "NeraKit"

LAYER = {
    "BrowserCore": 0, "SecurityPolicy": 0, "Storage": 0, "Networking": 0, "Diagnostics": 0, "BrowserData": 0,
    "EngineKit": 1, "WebKitEngine": 1, "ChromiumEngine": 1,
    "PageLifecycle": 2, "Import": 2, "Downloads": 2, "Permissions": 2, "Update": 2, "Extensions": 2, "Passkeys": 2, "SafeBrowsing": 2,
    "DesignSystem": 3, "Sidebar": 3, "CommandBar": 3,
    "BrowserShell": 4,
}
TEST_ONLY = {"TestSupport", "EngineTestSupport", "EngineConformance"}
ENGINE_ADAPTERS = {"WebKitEngine", "ChromiumEngine"}
SAME_LAYER_OK = {
    ("Storage", "BrowserCore"),
    ("WebKitEngine", "EngineKit"), ("ChromiumEngine", "EngineKit"),
    ("Sidebar", "DesignSystem"), ("CommandBar", "DesignSystem"),
}
UI = {"Foundation", "Observation", "SwiftUI", "AppKit", "UIKit", "UniformTypeIdentifiers", "ServiceManagement"}
FRAMEWORKS = {
    "BrowserCore": {"Foundation", "Observation"},
    "BrowserData": {"Foundation", "SQLite3", "CommonCrypto", "CryptoKit", "Security"},
    "EngineTestSupport": {"Foundation", "Observation"},
    "SecurityPolicy": {"Foundation"},
    "Storage": {"Foundation", "SQLite3"},
    "Networking": {"Foundation"},
    "Diagnostics": {"Foundation", "os"},
    "EngineKit": {"Foundation", "Observation", "AppKit", "UIKit"},
    "WebKitEngine": {"Foundation", "Observation", "AppKit", "UIKit", "WebKit", "Security", "ImageIO"},
    "ChromiumEngine": {"Foundation", "Observation", "AppKit", "UIKit"},
    "PageLifecycle": {"Foundation", "Observation", "Dispatch"},
    "Import": {"Foundation", "SQLite3", "CryptoKit", "CommonCrypto", "Security"},
    "Downloads": {"Foundation"},
    "Permissions": {"Foundation"},
    "Update": {"Foundation", "CryptoKit", "Security"},  # Security: code-signature check of updates (UpdateInstaller)
    "Extensions": {"Foundation", "CryptoKit", "Security"},
    "Passkeys": {"Foundation", "AppKit", "AuthenticationServices"},
    "SafeBrowsing": {"Foundation", "CryptoKit"},
    "DesignSystem": UI, "Sidebar": UI, "CommandBar": UI, "BrowserShell": UI,
    "TestSupport": {"Foundation", "Observation"},
    "EngineConformance": {"Foundation", "Network", "Security"},
}
APP_IMPORTS = {"SwiftUI", "AppKit", "UIKit", "Foundation", "os", "BrowserShell", "WebKitEngine", "ChromiumEngine", "EngineConformance", "Passkeys"}

IMPORT = re.compile(r"^\s*(?:@testable\s+|public\s+|internal\s+|package\s+)?import\s+(\w+)", re.M)
FORBIDDEN = [
    (re.compile(r"URLCredential\(\s*trust:"), "SR-002: never override server-trust evaluation"),
    (re.compile(r"--(no-sandbox|disable-web-security|ignore-certificate-errors|disable-site-isolation-trials|allow-running-insecure-content|remote-debugging-port)\b"),
     "SR-020: sandbox/security-weakening Chromium switch"),
    (re.compile(r"\bopenFile\(|\.openFile\b"), "SEC-044: Nera never opens downloaded files by itself"),
]
CEF_INCLUDE = re.compile(r'#\s*(include|import)\s+["<]include/(cef_|internal/cef|views/cef|wrapper/cef)')
ENGINE_LEAKS = [
    (re.compile(r"#if\s+canImport\((WebKit|ChromiumEngine|WebKitEngine)\)"), "AP-1: use EngineCapabilities, not engine #if"),
    (re.compile(r"\bWK[A-Z][A-Za-z]+\b"), "AP-1: WebKit type outside the WebKit adapter"),
    (re.compile(r"\bCef[A-Z][A-Za-z]+\b"), "AP-1: CEF type outside the Chromium adapter"),
]


def code_only(text: str) -> str:
    """Strip // comments and string-free doc lines so prose mentioning WKWebView doesn't count."""
    return "\n".join(line.split("//", 1)[0] for line in text.splitlines())


def package_deps() -> dict[str, list[str]]:
    manifest = (PKG / "Package.swift").read_text()
    deps: dict[str, list[str]] = {}
    for m in re.finditer(r'\.(?:target|testTarget)\(\s*name:\s*"(\w+)"(.*?)\)\s*,?\s*\n', manifest, re.S):
        names = re.findall(r'"(\w+)"', re.search(r"dependencies:\s*\[(.*?)\]", m.group(2), re.S).group(1)) \
            if "dependencies:" in m.group(2) else []
        deps[m.group(1)] = names
    return deps


def main() -> int:
    errors: list[str] = []
    deps = package_deps()

    for target, ds in deps.items():
        is_test = target.endswith("Tests")
        for d in ds:
            if is_test:
                continue
            if d in TEST_ONLY and target not in TEST_ONLY:
                errors.append(f"{target} → {d}: test-only module in a shipping target")
            elif d in ENGINE_ADAPTERS:
                errors.append(f"{target} → {d}: only the app targets may depend on engine adapters (AP-1)")
            elif target in LAYER and d in LAYER:
                if LAYER[d] > LAYER[target] or (LAYER[d] == LAYER[target] and (target, d) not in SAME_LAYER_OK):
                    errors.append(f"{target} (L{LAYER[target]}) → {d} (L{LAYER[d]}): imports must point down")

    for src in sorted((PKG / "Sources").iterdir()):
        target = src.name
        allowed = FRAMEWORKS.get(target)
        if allowed is None:
            errors.append(f"Sources/{target}: unknown target; add it to check-architecture.py")
            continue
        for f in src.rglob("*.swift"):
            text = f.read_text()
            rel = f.relative_to(ROOT)
            for mod in IMPORT.findall(text):
                if mod in LAYER or mod in TEST_ONLY:
                    continue  # local modules: checked via Package.swift above
                if mod not in allowed:
                    errors.append(f"{rel}: `import {mod}` not allowed in {target} (allowed: {', '.join(sorted(allowed))})")
            # The one sanctioned trust override: Debug-only test anchors, marked on the line itself.
            code = code_only("\n".join(l for l in text.splitlines() if "test-trust: DEBUG only" not in l))
            for pattern, why in FORBIDDEN:
                if pattern.search(code):
                    errors.append(f"{rel}: {why}")
            if target != "WebKitEngine":
                for pattern, why in ENGINE_LEAKS[:2]:
                    if pattern.search(code):
                        errors.append(f"{rel}: {why}")
            if target != "ChromiumEngine":
                if ENGINE_LEAKS[2][0].search(code):
                    errors.append(f"{rel}: {ENGINE_LEAKS[2][1]}")

    for f in (ROOT / "Apps").rglob("*.swift"):
        for mod in IMPORT.findall(f.read_text()):
            if mod not in APP_IMPORTS:
                errors.append(f"{f.relative_to(ROOT)}: apps import only {', '.join(sorted(APP_IMPORTS))}, not {mod}")

    # SEC-063: Nera's own code reaches the network only through Networking's allowlisted client.
    net = re.compile(r"\b(URLSession(Configuration|DataTask)?|NWConnection|NWPathMonitor|NSURLConnection|CFStreamCreate\w*)\b")
    for base in ("Packages/NeraKit/Sources", "Apps"):
        for f in (ROOT / base).rglob("*.swift"):
            rel = str(f.relative_to(ROOT))
            # Networking itself, WebKit's own auth types, and the test-only local server (Debug self-test only).
            if rel.startswith(("Packages/NeraKit/Sources/Networking/", "Packages/NeraKit/Sources/WebKitEngine/",
                               "Packages/NeraKit/Sources/EngineConformance/LocalTestServer.swift")):
                continue
            if net.search(code_only(f.read_text())):
                errors.append(f"{rel}: networking outside the Networking module (use NeraHTTPClient; SEC-063)")

    # CEF (C/C++/Objective-C++) only in the app's Chromium bridge and helper (ADR-0010).
    cef_dirs = ("Apps/macOS/Chromium/", "Apps/macOS/ChromiumHelper/")
    for base in ("Apps", "Packages/NeraKit/Sources"):
        for f in (ROOT / base).rglob("*"):
            if f.suffix not in {".h", ".m", ".mm", ".c", ".cc", ".cpp"}:
                continue
            rel = str(f.relative_to(ROOT))
            if CEF_INCLUDE.search(f.read_text(errors="ignore")) and not rel.startswith(cef_dirs):
                errors.append(f"{rel}: CEF headers are only allowed in {', '.join(cef_dirs)} (ADR-0010)")

    for e in errors:
        print(f"✘ {e}", file=sys.stderr)
    if errors:
        return 1
    print(f"✔ architecture OK ({len(deps)} targets, layering + engine independence + forbidden APIs)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
