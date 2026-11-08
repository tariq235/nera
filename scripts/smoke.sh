#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Pre-merge gate. Same steps run in CI (.github/workflows/ci.yml). Fails fast on the first broken step.
set -euo pipefail
cd "$(dirname "$0")/.."

step() { printf '\n\033[1;34m▶ %s\033[0m\n' "$*"; }

step "Generate Xcode project"
./scripts/engine/prepare-cef.sh && xcodegen generate --quiet

step "Format, lint, warnings-as-errors"
make -s lint

step "Architecture, docs, checklists, DocC"
python3 -I scripts/ci/check-architecture.py
python3 -I scripts/ci/check-mpl-headers.py
make -s docs

step "Guards: secrets, licenses, clean room, Arc naming, dependencies"
make -s guards

step "Unit, engine and conformance tests (NeraKit)"
(cd Packages/NeraKit && swift test --parallel)
python3 -I scripts/ci/render-engine-matrix.py --check

step "macOS build (Release, hardened runtime)"
xcodebuild -project Nera.xcodeproj -scheme Nera -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData build -quiet

step "Security policy checks"
./scripts/ci/check-entitlements.sh build/DerivedData/Build/Products/Release/Nera.app
./scripts/ci/check-network-inventory.sh

step "macOS end-to-end UI smoke tests"
xcodebuild -project Nera.xcodeproj -scheme Nera -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData NERA_APP_BUNDLE_ID=dev.nera.browser.test test -quiet

step "iOS/iPadOS simulator build (Release)"
SIM_ID="$(./scripts/ci/pick-ios-simulator.sh)"
xcodebuild -project Nera.xcodeproj -scheme NeraMobile -configuration Release -destination "platform=iOS Simulator,id=$SIM_ID" \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO ARCHS=arm64 DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES \
  build -quiet  # measured like the shipped app: Apple silicon only, symbols stripped

step "App size budgets"
make -s size

printf '\n\033[1;32m✔ Smoke passed\033[0m\n'
