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

.PHONY: help generate open build sim test lint format clean archive ipa ship-dry integration

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

# Export signs through the App Store Connect API key, so no Xcode account is needed and a
# store profile missing the current Apple Distribution cert is regenerated. System PATH:
# Homebrew rsync breaks IDEDistributionCreateIPAStep.
ASC_KEY_ID   ?= 6DC4HY7SA3
ASC_KEY_PATH ?= $(HOME)/.appstoreconnect/private_keys/AuthKey_$(ASC_KEY_ID).p8
ASC_ISSUER   ?= $(shell asc auth issuer-id 2>/dev/null)
APP_ID       := 6794369239

ipa: archive ## archive + export an App Store .ipa to build/export/ (upload is a separate, explicit step)
	env PATH="/usr/bin:/bin:/usr/sbin:/sbin" $(XCODE) xcodebuild -exportArchive \
	  -archivePath build/$(SCHEME).xcarchive -exportOptionsPlist .asc/export-options-app-store.plist \
	  -exportPath build/export -allowProvisioningUpdates \
	  -authenticationKeyPath "$(ASC_KEY_PATH)" -authenticationKeyID $(ASC_KEY_ID) -authenticationKeyIssuerID $(ASC_ISSUER)
	@ls -la build/export/*.ipa

ship-dry: ipa ## dry run of uploading + submitting the version in project.yml (changes nothing)
	asc publish appstore --app $(APP_ID) --ipa build/export/PhotoSweep.ipa \
	  --version $$(grep MARKETING_VERSION project.yml | grep -o '[0-9.]*') --metadata-dir docs/release/metadata --submit --wait --dry-run --output table

clean: ## remove generated project + build artifacts
	rm -rf $(PROJECT) build build-sim DerivedData
