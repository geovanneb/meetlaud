# Testing and quality gates

Goal: let the project grow, with human and agent contributors, without breaking its promises. Every important rule becomes an automated check. A rule that exists only in a document eventually stops being followed.

## Test pyramid

| Layer | Tool | Runs on | What it guarantees |
|---|---|---|---|
| Unit | Swift Testing | Every PR | Use cases, formatters, domain rules |
| Port contract | Swift Testing | Every PR | Every adapter meets the same suite |
| Persistence | GRDB in memory and on file | Every PR | Migrations from any older version to current |
| Snapshot | swift-snapshot-testing (test only) | Every PR, from F1 | Design System in 4 languages, Light and Dark, Dynamic Type |
| UI | XCUITest | Every PR for now, split into smoke and nightly as it grows | Main flows with fake engines, and each language reaching the screen |
| Accessibility | `performAccessibilityAudit` | Every PR | Labels, contrast, clipped text, Dynamic Type, tap targets. Exceptions need a written reason |
| Performance | XCTest Metrics | Nightly | Targets from the Architecture doc |
| Real device | `RealDeviceCaptureTests` + the SP-4 manual list | Before each release, and on any capture change | Real microphone, recording killed mid-way, background |
| AI evaluation | `ios/Evals/` | On demand and before changing a model | Transcription, diarization, summary, and RAG quality |

## PR quality gates

Nothing merges without passing:

1. Builds in Swift 6 with strict concurrency and warnings as errors, and the Android app builds with no lint error.
2. SwiftFormat, SwiftLint, and Android lint.
3. Unit, contract, migration, and snapshot tests, on both platforms, and the parity answers: the Android `Domain` gives the iOS `Domain`'s answers (`Tools/parity`).
4. Android instrumented tests on an emulator.
5. **Architecture rules**, on both platforms (Android: `Tools/check-android`).
6. **Privacy rules**, on both platforms.
7. **Localization rules**, on both platforms.
8. App and binary size within the limit.

## Architecture rules (`ios/Tools/check-architecture`)

Read from a graph declared in the repository.

| Rule | Fails when |
|---|---|
| Domain is pure | `Domain` imports anything beyond `Foundation` |
| Features are isolated | A feature imports another feature or an adapter |
| Adapters are isolated | An adapter imports another adapter without a declared exception |
| DesignSystem is a leaf | It imports Domain or a feature |
| Engines behind ports | `import WhisperKit`, `FluidAudio`, or `MLX` outside the adapter package |

The SPM dependency graph already blocks much of this at compile time. The script covers the rest.

## Privacy rules (`ios/Tools/check-privacy`)

These turn the promise into something verifiable.

| Rule | How |
|---|---|
| Network only in `ModelDelivery` | Search for `URLSession`, `NWConnection`, `CFNetwork`, `WKWebView`, `SFSafariViewController`, and `URLRequest` outside the allowlist |
| Dependencies without networking | Package allowlist, with hashes pinned in `Package.resolved` |
| Auto-download off | Adapters only receive local folders. Contract test with the network blocked |
| No PCC | `PrivateCloudComputeLanguageModel` is forbidden |
| No analytics | Denylist of known SDKs |
| Fixed entitlements | Changing `.entitlements` or `PrivacyInfo.xcprivacy` needs reviewer approval |
| Domain list | The catalog only accepts declared hosts |

In addition, an integration test runs the full flow (record, transcribe, summarize, ask) with the network blocked and logs any connection attempt.

## Localization rules (`ios/Tools/check-l10n`)

- No UI string outside the String Catalog.
- Every key translated into en, ja, pt-BR, and es.
- Plurals and formatting through ICU.
- A pseudolocale with 40% longer text, to find layout clipping.

## Fakes and test data

`TestSupport` provides:

- `FakeCaptureEngine`: fires interruptions, route changes, and full disk at the time the test asks.
- `FakeTranscriptionEngine` and `FakeLLM`: fixed responses, with programmable failures and delays.
- An injectable `Clock`.
- A sample library with configurable volume, for performance tests and Previews.

This makes it possible to test in milliseconds what would take an hour on a real device.

## Recording resilience script

Run on a real iPhone before each release.

- [ ] Record 3 hours with the screen locked
- [ ] Receive a call and decline, then answer and resume
- [ ] Alarm, timer, Siri
- [ ] Connect and disconnect AirPods during recording
- [ ] Open an app that uses the microphone
- [ ] Force quit from the app switcher
- [ ] Device shuts down from dead battery
- [ ] Fill the disk
- [ ] Low Power Mode and overheating
- [ ] App update with a recording pending recovery

## Evaluation harness (`ios/Evals/`)

A Mac CLI using the same domain logic, plus a benchmark app for real devices.

The first one is `ios/Evals/SummaryEval`: the app's own summary code and model, over invented meetings in four languages, for every built-in template and output language. Run it with `make eval-summary` before changing a summary prompt or the language model.

| Area | Metrics | Dataset |
|---|---|---|
| Transcription | WER, CER (ja), RTF, memory | Our own meetings with consent, in 4 languages, real room and distance |
| Diarization | DER, speaker count | Same set + VoxConverse |
| Voice print | EER, false positives | Volunteers, with consent |
| Summary | Fidelity, decision coverage, format | Human reference + rubric |
| RAG | Recall@5, answers with correct citations, refusal with no source | 100 questions per language |

- Evaluation audio does not enter the public repository without participant consent.
- Results live in `ios/Evals/results/` and block regressions above the limit when a model changes.
- The model catalog only changes with an evaluation report in the PR.
- `check-catalog` fails if a model lacks a license, pinned revision, SHA-256, languages, quality values, or reference benchmarks.
- `RecommendationEngine` has table-driven tests covering device, language, priority, and history combinations.

## CI/CD

GitHub Actions: macOS runners for iOS and Linux runners for Android, in two tiers. A pull request should get an answer in about 15 minutes, and `main` still runs every test.

```
gates (Linux, seconds) ─┬─► iOS lint + unit tests                        ─┐
   both apps' checks,   ├─► iOS UI tests: smoke          (pull requests)  │
   decides the tier     ├─► iOS UI tests: four groups    (main, nightly)  ├─► "Build and test (iOS)"
                        ├─► Android lint, unit tests, build               │    (the required check,
                        └─► Android instrumented tests, on an emulator   ─┘     for both platforms)
```

| Event | What runs |
|---|---|
| Pull request that only changes documentation (`*.md`, `docs/`, issue templates) | The gates only, about 1 minute |
| Pull request that changes code | iOS lint, unit tests, and the UI smoke set on three macOS machines; Android lint, unit tests, build, and instrumented tests on two Linux machines. A change to one app only runs that app's jobs |
| Push to `main`, every night at 03:00 JST, and a manual run | Every UI test, in four groups |

- **The tier.** `Tools/ci-scope` reads the changed files and decides. An empty or unreadable diff runs the macOS jobs. A pull request never runs every UI test, even when it changes the UI tests or the build: that took over 30 minutes. To run a class before you push, use `make test-ui XCODEFLAGS="-only-testing:MeetlaudUITests/<Class>"`.
- **The smoke set.** `ios/Tools/ui-smoke-tests.txt` lists about one UI test per area: navigation, recording, summary, Ask, search, models, network activity, speakers, settings, and the lock. Run it locally with `make test-ui-smoke`. CI runs it on two machines, each with every second test of the list (`PART=1 PARTS=2`), because launching the app for each test is most of that job's time. Keep it under about 15 tests; a test listed there must exist (`Tools/tests/test_ci.py` checks).
- **Why not every UI test on every pull request.** They are about 60 minutes of machine time on GitHub's 3-core Macs, and GitHub often queues macOS jobs. With six macOS jobs per run, a pull request waited about 30 minutes, even for a typo. A UI regression that the smoke set misses fails on `main` or overnight, and is fixed there.
- **The simulator.** `ios/Tools/ci-simulator` picks the iPhone 17 Pro, or any iPhone the runner image has, and boots it while the caches restore. A missing simulator once failed a whole job.
- **Audits look twice.** When Apple's audit reports a problem, `auditAccessibility` waits a second and audits again, and only the second pass fails the test. A summary still sliding into place was once reported as clipped text; a real problem is still there a second later.
- **Taps wait.** A drawer or menu that just opened can still be moving in on a CI machine. Tap with `tapWhenReady()`, not `tap()`: it waits for the element, and costs nothing when it is already there.
- **Why split.** In one job, CI took about 43 minutes, 28 of them UI tests launching the app one after another. The UI tests now run in four groups on four machines at once. The last group skips the classes named in the others, so a new test class runs without touching the workflow. When a group grows much slower than the others, move a class out of it.
- **Caches.** Packages (`build/spm`) and build products are cached, so MLX, WhisperKit, and FluidAudio are not compiled again on every run. `main` saves caches, and pull requests start from them. A change to `Package.resolved`, to Xcode, or to the cached folders starts a fresh cache: then a build takes about 17 minutes instead of 5. A pull request that finds no cache saves its own, so only its first run pays for that. A restored cache needs no help to build incrementally: on a fresh checkout it was measured at 21 seconds against 123 for a cold build, and content-based file times and Xcode's inode setting changed nothing.
- **No separate build step.** The UI tests build the app, so a compile error still fails CI.
- **Only GitHub's own actions** (`actions/*`). The repository allows no others, and a workflow that uses one fails before any job starts (`startup_failure`), with no check reported. Write a script in `Tools/` instead, as `Tools/android-emulator` does for the emulator.
- **Android on an emulator.** `Tools/android-emulator` boots one (it sets `ANDROID_AVD_HOME`, since the SDK's tools do not agree on where devices live without it), and `Tools/android-ui-tests` runs every instrumented test except the engine tests, which download models: the database, the domain's text handling under Android's own regex engine, and the parity screens. The emulator is x86_64, which runs the app's ARM64 code by translation. The same script runs on a phone (`make android-test-ui`).
- **Required check.** The `main` ruleset requires "Build and test (iOS)". It keeps that name, but it is a small final job that passes only when every job of both platforms passes, so splitting jobs never needs a ruleset change.
- **Failures.** A failed job uploads its `.xcresult` as an artifact for 7 days, with the failing assertion and screenshots.
- Locally, `make test` and `make test-ui` work as before. `XCODEFLAGS` passes extra flags, such as `-only-testing:MeetlaudUITests/SummaryTests`.

- The project is generated by XcodeGen (`ios/project.yml`), avoiding `.pbxproj` conflicts in open source.
- Xcode and tool versions are pinned.
- **Releases** build both apps from a tag, with checksums and build provenance for every file. See [Releasing](releasing.md).

## Open source

- `LICENSE` (Apache-2.0), `THIRD_PARTY_NOTICES.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`.
- Issue and PR templates with a checklist.
- `AGENTS.md` with rules for agents (`CLAUDE.md` points to it).
- Every relevant decision goes into `docs/decisions.md`.
- Conventional Commits, and a changelog whose version section becomes the release notes.
- No CLA, unless needed later.

## Definition of Done

A story is done only when:

- Acceptance criteria are covered by tests.
- It works in 4 languages, Light and Dark, with VoiceOver and Dynamic Type.
- All states are handled: empty, loading, error, no permission, no model.
- It works in airplane mode.
- It was tested on a real iPhone, if it touches capture, background, or models.
- Performance targets hold.
- `CHANGELOG.md` is updated for anything a person would notice.

## Reproducible offline speech evaluation

`make eval-transcription` generates fictional speech on macOS and runs the app's actual
Whisper Small adapter, audio conditioning, window reader, and cleanup. Model setup is
explicit; inference runs with network operations denied. It reports WER/CER, window
coverage, silence hallucinations, and processing time. See
[TranscriptionEval](../ios/Evals/TranscriptionEval/README.md) for prerequisites and metric
limitations, and the [quality review](reviews/offline-quality.md) for remaining release
gates. Generated audio and raw transcripts stay in ignored `build/`.
