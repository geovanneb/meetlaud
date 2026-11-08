SIMULATOR ?= iPhone 17 Pro
## CI sets DESTINATION to a simulator id from Tools/ci-simulator.
DESTINATION ?= platform=iOS Simulator,name=$(SIMULATOR)
DERIVED := build
## Extra xcodebuild flags, empty locally. CI uses them for a shared package folder, result bundles, and to split
## the UI tests across machines, e.g. make test-ui XCODEFLAGS="-only-testing:MeetlaudUITests/SummaryTests".
XCODEFLAGS ?=
## A few UI tests per area, listed in Tools/ui-smoke-tests.txt. Pull requests run these; main runs every UI test.
SMOKE_TESTS := $(addprefix -only-testing:MeetlaudUITests/,$(shell cat Tools/ui-smoke-tests.txt))

.PHONY: bootstrap generate format lint check test-tools test test-ui test-ui-smoke build ci screenshots

bootstrap:
	brew bundle --file=Brewfile
	$(MAKE) generate

generate:
	xcodegen generate --quiet

format:
	swiftformat .

## Fast, no build needed. These are the rules that protect the promise.
check:
	python3 -m unittest discover -s Tools/tests -q
	Tools/check-architecture
	Tools/check-privacy
	Tools/check-l10n

lint: check
	swiftformat --lint .
	swiftlint --strict --quiet

build: generate
	xcodebuild -project Meetlaud.xcodeproj -scheme Meetlaud -destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED) -quiet $(XCODEFLAGS) build

test:
	cd Packages && xcodebuild -scheme MeetlaudKit-Package -destination '$(DESTINATION)' \
		-derivedDataPath ../$(DERIVED)/package -quiet $(XCODEFLAGS) test

test-ui: generate
	xcodebuild -project Meetlaud.xcodeproj -scheme Meetlaud -destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED) -quiet $(XCODEFLAGS) test

test-ui-smoke: generate
	xcodebuild -project Meetlaud.xcodeproj -scheme Meetlaud -destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED) -quiet $(XCODEFLAGS) $(SMOKE_TESTS) test

ci: lint build test test-ui

## README pictures from fictional meetings, in light and dark. Boot the simulator first.
SHOTS := $(CURDIR)/docs/screenshots
screenshots: generate
	xcrun simctl status_bar booted override --time "9:41" --batteryState charged --batteryLevel 100 \
		--wifiBars 3 --cellularMode active --cellularBars 4 --dataNetwork wifi
	for look in light dark; do \
		xcrun simctl ui booted appearance $$look; \
		TEST_RUNNER_SCREENSHOT_DIR=$(SHOTS) TEST_RUNNER_SCREENSHOT_APPEARANCE=$$look \
		xcodebuild -project Meetlaud.xcodeproj -scheme Meetlaud -destination '$(DESTINATION)' \
			-derivedDataPath $(DERIVED) -quiet test -only-testing:MeetlaudUITests/ScreenshotTests || exit 1; \
	done
	xcrun simctl ui booted appearance light
	xcrun simctl status_bar booted clear
