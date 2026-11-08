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
| AI evaluation | `Evals/` | On demand and before changing a model | Transcription, diarization, summary, and RAG quality |

## PR quality gates

Nothing merges without passing:

1. Builds in Swift 6 with strict concurrency and warnings as errors.
2. SwiftFormat and SwiftLint.
3. Unit, contract, migration, and snapshot tests.
4. **Architecture rules.**
5. **Privacy rules.**
6. **Localization rules.**
7. App and binary size within the limit.

## Architecture rules (`Tools/check-architecture`)

Read from a graph declared in the repository.

| Rule | Fails when |
|---|---|
| Domain is pure | `Domain` imports anything beyond `Foundation` |
| Features are isolated | A feature imports another feature or an adapter |
| Adapters are isolated | An adapter imports another adapter without a declared exception |
| DesignSystem is a leaf | It imports Domain or a feature |
| Engines behind ports | `import WhisperKit`, `FluidAudio`, or `MLX` outside the adapter package |

The SPM dependency graph already blocks much of this at compile time. The script covers the rest.

## Privacy rules (`Tools/check-privacy`)

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

## Localization rules (`Tools/check-l10n`)

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

## Evaluation harness (`Evals/`)

A Mac CLI using the same domain logic, plus a benchmark app for real devices.

| Area | Metrics | Dataset |
|---|---|---|
| Transcription | WER, CER (ja), RTF, memory | Our own meetings with consent, in 4 languages, real room and distance |
| Diarization | DER, speaker count | Same set + VoxConverse |
| Voice print | EER, false positives | Volunteers, with consent |
| Summary | Fidelity, decision coverage, format | Human reference + rubric |
| RAG | Recall@5, answers with correct citations, refusal with no source | 100 questions per language |

- Evaluation audio does not enter the public repository without participant consent.
- Results live in `Evals/results/` and block regressions above the limit when a model changes.
- The model catalog only changes with an evaluation report in the PR.
- `check-catalog` fails if a model lacks a license, pinned revision, SHA-256, languages, quality values, or reference benchmarks.
- `RecommendationEngine` has table-driven tests covering device, language, priority, and history combinations.

## CI/CD

GitHub Actions with macOS runners.

```
pull_request  ─► lint ─► architecture ─► privacy ─► l10n ─► build ─► test ─► snapshot
nightly       ─► full XCUITest ─► accessibility ─► performance
release tag   ─► reproducible build ─► TestFlight ─► notes ─► checklist
```

- The project is generated by XcodeGen (`project.yml`), avoiding `.pbxproj` conflicts in open source.
- Xcode and tool versions are pinned.
- **Verifiable build:** publish a hash and instructions so anyone can compare, as far as the App Store allows.

## Open source

- `LICENSE` (Apache-2.0), `THIRD_PARTY_NOTICES.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`.
- Issue and PR templates with a checklist.
- `CLAUDE.md` with rules for agents.
- Every relevant decision goes into `docs/decisions.md`.
- Conventional Commits and a generated changelog.
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
