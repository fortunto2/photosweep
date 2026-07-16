# PhotoSweep — iOS media-library cleaner. Canonical command interface.
# project.yml is the source of truth; the .xcodeproj is generated.

SCHEME    := PhotoSweep
PROJECT   := PhotoSweep.xcodeproj
SIM       := platform=iOS Simulator,name=iPhone 17 Pro
BUNDLE_ID := co.superduperai.photosweep
XCODE     := DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# Xcode 26 SWBBuildService deadlock self-heal: a background watcher that kills ONLY
# the stuck SDK macro-probe (`clang … -E -dM`) when it hangs >4s (healthy probe
# finishes <1s, so it's never touched). SWBBuildService then gets EOF and proceeds.
# Torn down on recipe exit via trap. Makes build/sim/test immune to the hang.
GUARD_ON = ( while true; do P=$$(pgrep -f "clang.*-E -dM -isysroot" | head -1); \
  [ -n "$$P" ] && { sleep 4; ps -p $$P >/dev/null 2>&1 && pkill -9 -f "clang.*-E -dM -isysroot"; }; \
  sleep 1; done ) & GUARD_PID=$$!; trap "kill $$GUARD_PID 2>/dev/null" EXIT INT TERM;

.PHONY: help generate open build sim test lint format clean archive integration

help: ## list targets
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | sort | \
	  awk 'BEGIN{FS=":.*## "}{printf "  \033[36m%-12s\033[0m %s\n",$$1,$$2}'

generate: ## regenerate the Xcode project from project.yml
	xcodegen generate

open: generate ## open the project in Xcode
	open $(PROJECT)

build: generate ## compile for the iOS Simulator (no signing) — catches real errors
	@$(GUARD_ON) \
	$(XCODE) xcodebuild -project $(PROJECT) -scheme $(SCHEME) -sdk iphonesimulator \
	  -configuration Debug CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -40

sim: generate ## build + run on the iOS Simulator
	@$(GUARD_ON) \
	$(XCODE) xcodebuild -project $(PROJECT) -scheme $(SCHEME) -sdk iphonesimulator \
	  -destination '$(SIM)' -configuration Debug CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -40

test: generate ## run unit tests on the simulator
	@$(GUARD_ON) \
	$(XCODE) xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	  -destination '$(SIM)' test 2>&1 | tail -60

integration: test ## deterministic pipeline check (pure logic covered by unit tests)

lint: ## run SwiftLint
	@which swiftlint >/dev/null 2>&1 && swiftlint || echo "swiftlint not installed: brew install swiftlint"

format: ## run swift-format in place
	@which swift-format >/dev/null 2>&1 && swift-format -i -r Sources Tests || echo "swift-format not installed"

archive: generate ## build a signed archive for App Store distribution
	@$(GUARD_ON) \
	$(XCODE) xcodebuild -project $(PROJECT) -scheme $(SCHEME) -sdk iphoneos \
	  -configuration Release -archivePath build/$(SCHEME).xcarchive archive

clean: ## remove generated project + build artifacts
	rm -rf $(PROJECT) build build-sim DerivedData
