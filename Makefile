## Meetlaud has two native apps: ios/ (Swift, Xcode) and android/ (Kotlin, Gradle).
## Android mirrors iOS feature for feature and screen for screen (D-084). See docs/android.md.
##
## From the root:
##   make check           the privacy, architecture, and localization rules of both apps, no build needed
##   make lint            check, plus formatting and Android lint
##   make test            unit tests of both apps
##   make ci              everything both apps run in CI, except the Android UI tests, which need a phone
## iOS only (forwarded to ios/Makefile, variables included):
##   make bootstrap build test-ui test-ui-smoke screenshots eval-summary eval-transcription
##   make ios-<target>    any other target of ios/Makefile
## Android only:
##   make android-build android-test android-test-ui android-install android-release
## Both:
##   make parity-screens   every parity screen on the booted simulator and the connected phone, side by side

IOS_ONLY := bootstrap generate format build test-ui test-ui-smoke screenshots eval-summary eval-transcription
## Gradle needs JDK 17. Found here when JAVA_HOME is not set.
export JAVA_HOME ?= $(shell /usr/libexec/java_home -v 17 2>/dev/null || brew --prefix openjdk@17 2>/dev/null)
GRADLE := cd android && ./gradlew --quiet

.PHONY: check lint test ci ios-check android-check android-build android-test android-test-ui android-install \
	android-lint android-release parity-screens $(IOS_ONLY)

check: ios-check android-check
	python3 -m unittest discover -s Tools/tests -q

ios-check:
	$(MAKE) -C ios check

android-check:
	Tools/check-android android

lint: check
	$(MAKE) -C ios lint
	$(MAKE) android-lint

test:
	$(MAKE) -C ios test
	$(MAKE) android-test

ci:
	$(MAKE) -C ios ci
	$(MAKE) android-lint android-test android-build

$(IOS_ONLY):
	$(MAKE) -C ios $@

ios-%:
	$(MAKE) -C ios $*

android-build:
	$(GRADLE) assembleDebug

android-lint:
	$(GRADLE) lint

android-test:
	$(GRADLE) testDebugUnitTest

## Runs on the phone connected over USB, or an emulator (adb devices must list one).
android-test-ui:
	Tools/android-ui-tests

android-install:
	$(GRADLE) installDebug

## The release bundle and APK. Signed when the MEETLAUD_KEYSTORE_* variables are set (see docs/releasing.md).
android-release:
	$(GRADLE) bundleRelease assembleRelease

## Both apps' parity screenshots, paired in build/parity/compare. See docs/android.md.
parity-screens:
	Tools/parity-screens build/parity
