#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""CycloneDX 1.5 SBOM for a Nera release (REL-008), from the dependency register
(scripts/ci/data/dependencies.json, the same source as THIRD_PARTY_NOTICES.md) plus the built artifact's hash.
Nera has no package-manager dependencies (check-dependencies.sh enforces it), so the register is complete.

  sbom.py --version 0.3.0 --artifact build/Nera.dmg > Nera-0.3.0.cdx.json
"""
import argparse
import hashlib
import json
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True)
    ap.add_argument("--artifact", type=Path)
    a = ap.parse_args()

    deps = json.loads((ROOT / "scripts/ci/data/dependencies.json").read_text())["dependencies"]
    nera = {"type": "application", "bom-ref": "nera", "name": "Nera", "version": a.version,
             "licenses": [{"license": {"name": "Proprietary"}}]}
    if a.artifact:
        nera["hashes"] = [{"alg": "SHA-256", "content": sha256(a.artifact)}]
    components = []
    for d in deps:
        ref = d["name"].lower().replace(" ", "-")
        components.append({
            "type": "framework", "bom-ref": ref, "name": d["name"], "version": d["version"],
            "licenses": [{"license": {"id": d["license"]}}],
            "externalReferences": [{"type": "distribution", "url": d["source"].split(" ")[0]}],
            "description": d["purpose"],
        })
    bom = {
        "bomFormat": "CycloneDX", "specVersion": "1.5", "serialNumber": f"urn:uuid:{uuid.uuid4()}", "version": 1,
        "metadata": {"timestamp": datetime.now(timezone.utc).isoformat(timespec="seconds"), "component": nera,
                     "tools": [{"name": "scripts/release/sbom.py"}]},
        "components": components,
        "dependencies": [{"ref": "nera", "dependsOn": [c["bom-ref"] for c in components]}],
    }
    json.dump(bom, sys.stdout, indent=2)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
