# Bringing Meetlaud to Android

Meetlaud is native on purpose: recording reliability, background rules, and on-device AI all depend on what each platform offers. So Android gets its own native app, not a cross-platform port. This page explains how the two apps stay one product.

## How the repositories are organized

| Repository | What it holds | Status |
|---|---|---|
| `meetlaud-ios` (this one) | The iPhone and iPad app, in Swift | Active |
| `meetlaud-android` | The Android app, in Kotlin and Jetpack Compose | Planned |
| `meetlaud-spec` | What both apps must agree on: formats, protocols, prompts, strings, and test fixtures | Created when Android work starts |

Why separate repositories instead of one monorepo:

- **Different toolchains.** Xcode and Gradle, different CI runners, different release cycles. One repository would make every pull request wait on both.
- **Different contributors.** Most people know one platform well. A focused repository is easier to enter.
- **Proven pattern.** Mature open-source apps with native clients on both platforms, such as Signal and Element, keep one repository per platform.

What keeps them one product is `meetlaud-spec`, versioned with semantic versions. Each app pins a spec version, and a change to the spec is reviewed by maintainers of both apps.

## What moves to the shared spec

Until `meetlaud-spec` exists, these live here. Each one is already platform-neutral, or close to it.

| Contract | Where it lives today | Why it must be shared |
|---|---|---|
| Model catalog (ids, sources, hashes, memory needs, licenses) | `Packages/Infrastructure/ModelDelivery/Sources/Resources/models.json`, built by `Tools/generate-model-catalog` | Same models, same pinned versions, same license review |
| Interface text in en, ja, pt-BR, and es | `Packages/UI/Localization/Sources/Resources/Localizable.xcstrings` (JSON) | One translation effort. A script converts it to Android `strings.xml` |
| Summary templates and prompts | `Packages/Core/Domain/Sources/SummaryPrompts.swift` and `BuiltInTemplates.swift` | Same summary on both phones for the same meeting |
| Connector protocol, with crypto test vectors | [Connectors](connectors.md) | Any computer that pairs with one app pairs with the other |
| Encrypted library export | `Packages/Infrastructure/Archive` | Someone who changes phones takes their meetings along |
| Evaluation sets and quality rubric | [Testing](testing.md), [On-device AI](on-device-ai.md) | Quality is measured the same way |
| Privacy rules | `Tools/check-privacy`, [Privacy](PRIVACY.md) | The promise is identical on both platforms |

The move is simple: copy the file into the spec repository, give it a version, and have each app read it from there at build time.

## A likely Android stack

These are starting points for the Android maintainers to confirm with their own spikes, as the iOS app did ([Research](research/)).

| Need | iOS uses | Android candidates |
|---|---|---|
| Interface | SwiftUI | Jetpack Compose, Material 3 |
| Reliable background recording | Audio background mode, Live Activity | Foreground service with a persistent notification |
| Transcription | WhisperKit (Core ML), Apple Speech | whisper.cpp, sherpa-onnx |
| Speaker separation and voice prints | FluidAudio (pyannote, Core ML) | sherpa-onnx speaker diarization (ONNX) |
| Summaries and chat | MLX Swift with Qwen 3.5 2B | llama.cpp, MediaPipe LLM Inference |
| Database and search | GRDB, SQLite FTS5 | Room, SQLite FTS5 |
| Long jobs | Background tasks | WorkManager |

## Rules both apps share

- No account, no analytics, no server of ours.
- One module may use the network, for model downloads. Connectors reach only a computer the person paired, on the local network.
- Recording never loses data.
- All interface text in four languages from day one.
