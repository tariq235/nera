# One entry point for humans and CI. `make help` lists targets.
SHELL := /bin/bash
# The pinned tools from `make bootstrap` (scripts/ci/install-tools.sh) come first, so local runs match CI.
export PATH := $(CURDIR)/build/tools/bin:$(PATH)
DERIVED := build/DerivedData
MAC_DEST := platform=macOS
IOS_DEST = platform=iOS Simulator,id=$(shell ./scripts/ci/pick-ios-simulator.sh)

.PHONY: help bootstrap project build build-ios test test-unit test-ui smoke format lint guards security docs checklists gate architecture conformance size clean

help: ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Install the pinned dev tools (SwiftLint, XcodeGen, gitleaks, …) and prepare the project
	./scripts/bootstrap.sh

project: ## Fetch + verify the pinned CEF, then generate Nera.xcodeproj from project.yml
	./scripts/engine/prepare-cef.sh
	xcodegen generate --quiet

build: project ## Build the macOS app (Debug)
	xcodebuild -project Nera.xcodeproj -scheme Nera -destination '$(MAC_DEST)' -derivedDataPath $(DERIVED) build -quiet

build-ios: project ## Build the iOS/iPadOS app for the simulator
	xcodebuild -project Nera.xcodeproj -scheme NeraMobile -destination '$(IOS_DEST)' -derivedDataPath $(DERIVED) CODE_SIGNING_ALLOWED=NO build -quiet

test-unit: ## Run NeraKit unit + engine tests (fast, no UI)
	cd Packages/NeraKit && swift test --parallel

test-ui: project ## Run macOS end-to-end UI smoke tests
	xcodebuild -project Nera.xcodeproj -scheme Nera -destination '$(MAC_DEST)' -derivedDataPath $(DERIVED) NERA_APP_BUNDLE_ID=dev.nera.browser.test test -quiet

test: test-unit test-ui ## Everything

smoke: ## Full pre-merge gate: unit tests, macOS build+UI tests, iOS build, security checks
	./scripts/smoke.sh

SWIFT_DIRS := Packages/NeraKit/Sources Packages/NeraKit/Tests Apps UITests

format: ## Format all Swift code in place (swift format)
	swift format format --in-place --recursive --parallel $(SWIFT_DIRS)

lint: ## swift format (strict), SwiftLint (strict), warnings-as-errors build
	swift format lint --strict --recursive --parallel $(SWIFT_DIRS)
	swiftlint lint --strict --quiet
	cd Packages/NeraKit && swift build --build-tests -Xswiftc -warnings-as-errors

guards: ## Secrets, licenses, clean room, Arc naming, dependency vulnerabilities
	./scripts/ci/check-secrets.sh
	python3 -I scripts/ci/check-licenses.py
	python3 -I scripts/ci/check-clean-room.py --rules clean-room
	python3 -I scripts/ci/check-clean-room.py --rules naming
	python3 -I scripts/ci/check-a11y-labels.py
	python3 -I scripts/ci/check-log-redaction.py
	./scripts/ci/check-dependencies.sh

size: ## App size budgets (build Release apps first: make smoke builds them)
	python3 -I scripts/ci/check-binary-size.py macos build/DerivedData/Build/Products/Release/Nera.app
	python3 -I scripts/ci/check-binary-size.py ios build/DerivedData/Build/Products/Release-iphonesimulator/Nera.app

security: architecture ## Entitlement, network-inventory and architecture policy checks
	./scripts/ci/check-entitlements.sh
	./scripts/ci/check-network-inventory.sh

checklists: ## Validate checklists and print status
	python3 -I scripts/ci/check-checklists.py

gate: ## Fail unless the release gate is met
	python3 -I scripts/ci/check-checklists.py --gate foundation

docs: checklists ## Docs checks: checklists, links/anchors, public API docs, DocC (zero warnings)
	python3 -I scripts/ci/check-doc-links.py
	python3 -I scripts/ci/check-public-docs.py
	./scripts/ci/check-docc.sh

architecture: ## Layering, engine independence, forbidden APIs and MPL-2.0 headers
	python3 -I scripts/ci/check-architecture.py
	python3 -I scripts/ci/check-mpl-headers.py

conformance: project ## Run engine conformance on real Chromium + WebKit (in the app) and regenerate checklist 005's matrix
	xcodebuild -project Nera.xcodeproj -scheme Nera -destination '$(MAC_DEST)' -derivedDataPath $(DERIVED) NERA_APP_BUNDLE_ID=dev.nera.browser.test build -quiet
	./scripts/ci/engine-self-test.sh $(DERIVED)/Build/Products/Debug/Nera.app
	python3 -I scripts/ci/render-engine-matrix.py


clean: ## Remove build output
	rm -rf build Nera.xcodeproj Packages/NeraKit/.build
