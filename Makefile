SIMULATOR ?= iPhone 17 Pro
## CI sets DESTINATION to a simulator id from Tools/ci-simulator.
DESTINATION ?= platform=iOS Simulator,name=$(SIMULATOR)
DERIVED := build
## Extra xcodebuild flags, empty locally. CI uses them for a shared package folder, result bundles, and to split
## the UI tests across machines, e.g. make test-ui XCODEFLAGS="-only-testing:MeetlaudUITests/SummaryTests".
XCODEFLAGS ?=
## A few UI tests per area, listed in Tools/ui-smoke-tests.txt. Pull requests run these; main runs every UI test.
SMOKE_TESTS := $(addprefix -only-testing:MeetlaudUITests/,$(shell cat Tools/ui-smoke-tests.txt))

.PHONY: bootstrap generate format lint check test-tools test test-ui test-ui-smoke build ci screenshots eval-summary eval-transcription

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

## Summaries from the real model on this Mac, for every template and language. See Evals/SummaryEval/README.md.
## Takes about 30 minutes on an M4. Narrow it with EVAL_ARGS, e.g. EVAL_ARGS="pt ja builtin.discussion".
EVAL_MODEL ?= $(HOME)/.meetlaud-eval/qwen35-2b
EVAL_OUT ?= $(DERIVED)/eval/summary.jsonl
EVAL_ARGS ?= en,pt,ja,es auto,en,ja,pt,es all
eval-summary:
	python3 -I Evals/SummaryEval/fetch-model.py qwen35-2b $(EVAL_MODEL)
	cd Evals/SummaryEval && xcodebuild -scheme SummaryEval -destination 'platform=macOS' \
		-derivedDataPath ../../$(DERIVED)/eval -configuration Release -quiet build
	mkdir -p $(dir $(EVAL_OUT))
	$(DERIVED)/eval/Build/Products/Release/SummaryEval $(EVAL_MODEL) $(EVAL_OUT) $(EVAL_ARGS)
	python3 -I Evals/SummaryEval/score.py $(EVAL_OUT)

## Generated speech in four languages, through the real offline Whisper pipeline on this Mac.
ASR_EVAL_DIR ?= $(CURDIR)/build/transcription-eval
ASR_EVAL_MODEL ?= whisper-small
eval-transcription:
	python3 -I Evals/SummaryEval/fetch-model.py $(ASR_EVAL_MODEL) $(ASR_EVAL_DIR)/model
	python3 -I Evals/TranscriptionEval/generate.py $(ASR_EVAL_DIR)/fixtures
	cd Evals/TranscriptionEval && xcodebuild -scheme TranscriptionEval -destination 'platform=macOS,arch=arm64' \
		-derivedDataPath $(ASR_EVAL_DIR)/build -configuration Release -quiet build
	sandbox-exec -p '(version 1)(allow default)(deny network*)' \
		$(ASR_EVAL_DIR)/build/Build/Products/Release/TranscriptionEval $(ASR_EVAL_DIR)/model \
		$(ASR_EVAL_DIR)/fixtures/fixtures.json $(ASR_EVAL_DIR)/results.json $(ASR_EVAL_MODEL)
	python3 -I Evals/TranscriptionEval/score.py $(ASR_EVAL_DIR)/results.json
