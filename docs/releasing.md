# Releasing

A release ships both apps at once, with the same version number and the same notes. Pushing a tag does the rest:
`.github/workflows/release.yml` builds, signs, checks, and publishes the GitHub release.

## What a release contains

| File | For whom |
|---|---|
| `Meetlaud-1.2.0.aab` | Google Play (upload it in the Play Console) |
| `Meetlaud-1.2.0.apk` | People who install on Android directly. Signed with the same key |
| `Meetlaud-1.2.0-unsigned.ipa` | People who sideload on iPhone with their own Apple account (AltStore, Sideloadly). It needs their signature before it installs |
| TestFlight build | iPhone testers. Sent to App Store Connect when it is set up, not attached to the release |
| `SHA256SUMS` | Anyone checking a download: `shasum -a 256 -c SHA256SUMS` |

Every file also gets a build provenance attestation, so anyone can prove it was built by this workflow from the tag:
`gh attestation verify Meetlaud-1.2.0.apk -R geovanneb/meetlaud`.

## Steps

1. **Start from a green `main`.** CI passed on the last commit, on both platforms.
2. **Test on real devices.** At least one iPhone and one Android phone: record with the screen locked, transcribe, separate voices, summarize, ask. Note the devices in the pull request.
3. **Write the notes.** In `CHANGELOG.md`, rename `## [Unreleased]` to `## [1.2.0] - 2027-01-10` and start a new, empty `## [Unreleased]` above it. Merge that change through a pull request (`chore: release 1.2.0`).
4. **Tag `main`** with the version, prefixed with `v`, and push the tag:

   ```sh
   git switch main && git pull
   git tag -s v1.2.0 -m "Meetlaud 1.2.0"
   git push origin v1.2.0
   ```

5. **Watch the Release workflow.** It fails, and publishes nothing, when the notes are missing, a check fails, or the Android key is not set.
6. **Upload the `.aab` to Google Play** and promote the TestFlight build, once each store's review passes.

A tag with a hyphen, such as `v1.2.0-beta.1`, becomes a GitHub pre-release. Apple accepts only numbers, so TestFlight
receives it as `1.2.0` with a higher build number.

To check that everything still builds without publishing, run the workflow by hand (Actions > Release > Run workflow).

## Versions

The tag is the only place the version is written. The workflow passes it to both builds:

| | Version | Build number |
|---|---|---|
| Android | `versionName` from the tag | `versionCode` = 1000 + the workflow's run number |
| iOS | `MARKETING_VERSION` from the tag, without any pre-release part | `CURRENT_PROJECT_VERSION`, the same number |

The build number only grows, as both stores require. The versions in `ios/Config/Product.xcconfig` and
`android/app/build.gradle.kts` are only for local builds.

## Secrets

Set these in the repository's Settings > Secrets and variables > Actions. None of them is ever in the repository.

| Secret | What it is |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | The upload key's keystore, as `base64 < release.jks`. Required for a release |
| `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | Its passwords and alias |
| `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID` | An App Store Connect API key with the App Manager role. Optional: without them, TestFlight is skipped |
| `APP_STORE_CONNECT_KEY_BASE64` | That key's `.p8` file, as `base64 < AuthKey_XXXX.p8` |
| `APPLE_TEAM_ID` | The team that owns the app's bundle identifier |

iOS signs in the cloud with the API key, so no certificate or provisioning profile is stored anywhere. Keep a copy of
the Android keystore somewhere safe: with Play App Signing, a lost upload key can be reset, but it takes days.

## Locally

The same builds, on a Mac with both toolchains:

```sh
make android-release                          # android/app/build/outputs: unsigned without the MEETLAUD_KEYSTORE_* variables
make -C ios ipa-unsigned VERSION=1.2.0 BUILD=1  # ios/build/release/Meetlaud-unsigned.ipa
Tools/release-notes 1.2.0                       # the notes the release will use
```
