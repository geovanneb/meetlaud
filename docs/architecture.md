# Architecture

## Overview

Clean Architecture in a monorepo with local SPM packages. Dependencies always point inward. The app target is thin: composition only.

```
             ┌──────────────── App (composition, DI) ───────────────┐
             │                                                      │
   Features (SwiftUI + @Observable)              Adapters (Infrastructure)
   Home, Library, Recording, Detail, Ask...      Audio, Persistence, ASR,
             │                                   Diarization, LLM, ModelDelivery
             │                                                      │
             └───────────────►   Domain   ◄──────────────────────────┘
                          (entities, use cases, ports)
```

The central rule: **Domain knows nothing**. Features and adapters know Domain, never each other. The app connects both ends.

## Repository layout

```
meetlaud/
├── App/                     # iOS target: entry point, composition, Info.plist, entitlements
├── Extensions/
│   ├── WidgetsExtension/    # Widgets, Live Activity, Controls
├── Packages/
│   ├── Core/
│   │   ├── Domain/          # Entities, use cases, ports
│   │   ├── AppIntentsKit/   # Intents shared with extensions
│   │   └── SharedKit/       # Local logger, utilities, formats
│   ├── Infrastructure/
│   │   ├── Persistence/     # GRDB, migrations, FTS5, repositories
│   │   ├── AudioCapture/    # AVAudioEngine, session, segments
│   │   ├── AudioPlayback/
│   │   ├── AudioEditing/    # Import and merge finished files
│   │   ├── ModelDelivery/   # The ONLY module allowed to use the network
│   │   ├── ModelBenchmarks/ # Speed tests per role, through engine ports
│   │   ├── DeviceMonitoring/ # Memory, thermal, power, and disk signals
│   │   ├── ASRApple/        # SpeechAnalyzer
│   │   ├── ASRWhisperKit/
│   │   ├── ASRParakeet/     # FluidAudio
│   │   ├── DiarizationFluid/
│   │   ├── LLMFoundation/   # Foundation Models
│   │   ├── LLMMLX/          # MLX Swift
│   │   ├── Embeddings/
│   │   └── SystemBridges/   # EventKit, Spotlight, Notifications, Reminders
│   ├── Features/
│   │   ├── FeatureHome/  FeatureLibrary/  FeatureRecording/
│   │   ├── FeatureDetail/  FeatureAsk/  FeatureTools/
│   │   ├── FeatureSettings/  FeatureOnboarding/  FeatureModels/
│   ├── UI/
│   │   ├── DesignSystem/    # Tokens and components
│   │   └── Localization/    # String Catalog
│   └── Testing/
│       └── TestSupport/     # Fakes, builders, test audio
├── Evals/                   # Evaluation harness (Mac CLI)
├── Config/                  # xcconfig, Product.xcconfig
├── Tools/                   # Architecture and privacy rules
├── project.yml              # XcodeGen
└── docs/
```

All targets are declared in one manifest, `Packages/Package.swift`. The dependency graph in that file is the architecture ([D-025](decisions.md)).

Why each engine is a separate target: heavy dependencies stay isolated, incremental builds stay fast, and an engine can be replaced without touching anything else.

## Main ports

```swift
public protocol AudioCaptureEngine: Sendable {
    func start(_ config: CaptureConfig) async throws -> CaptureSession
    func pause() async throws
    func resume() async throws
    func stop() async throws -> CaptureResult
    var events: AsyncStream<CaptureEvent> { get }   // level, interruption, route, disk
}

public protocol TranscriptionEngine: Sendable {
    var descriptor: EngineDescriptor { get }
    func transcribe(_ source: AudioSource, options: TranscriptionOptions)
        -> AsyncThrowingStream<TranscriptionEvent, Error>
}

public protocol DiarizationEngine: Sendable {
    func diarize(_ source: AudioSource) async throws -> DiarizationResult
}

public protocol SpeakerEmbeddingEngine: Sendable {
    func embedding(for audio: AudioSlice) async throws -> VoiceEmbedding
}

public protocol LanguageModelEngine: Sendable {
    var capabilities: LLMCapabilities { get }   // context, streaming, background
    func generate(_ request: LLMRequest) -> AsyncThrowingStream<LLMDelta, Error>
}

public protocol TextEmbeddingEngine: Sendable {
    func embed(_ texts: [String]) async throws -> [[Float]]
}

public protocol ModelCatalog: Sendable { ... }
public protocol ModelInstaller: Sendable { ... }
public protocol ModelBenchmark: Sendable { ... }
public protocol DeviceMonitor: Sendable { ... }
```

The model system (roles, recommendation, speed test, and Device Advisor) is specified in [Model management](model-management.md).

**Contract rule:** every adapter passes the same test suite for its port. Replacing Whisper with Parakeet changes nothing above the port.

`EngineDescriptor` and `LLMCapabilities` declare what an engine can do: languages, word timestamps, context size, and background support. The UI and use cases decide from these values, never from the engine name.

## Feature pattern

Light MVVM with `@Observable`. No third-party architecture framework, to lower the cost of contributing.

```
FeatureDetail/
├── DetailView.swift          # Pure SwiftUI
├── DetailModel.swift         # @MainActor @Observable, calls use cases
├── Components/
└── Preview/                  # Previews with sample data
```

- Views contain no business rules.
- The model receives use cases through its `init`.
- Navigation goes through `AppRouter`, never by importing another feature.
- Use cases are small `struct`s, one action per type: `StartRecording`, `TranscribeRecording`, `GenerateSummary`.

## Concurrency

- Swift 6, strict mode.
- `@MainActor` only for UI.
- One `actor` per stateful resource: `RecordingCoordinator`, `JobScheduler`, `ModelArbiter`.
- Inference never runs on the cooperative pool without isolation. Each engine uses its own executor, so the UI does not feel it.
- `ModelArbiter`: one owner of heavy models at a time. A transcription queue holds it until it empties. Optional work, such as a speed test, gives way instead of waiting. A real crash proved why: a test unloaded the model under a running transcription ([D-035](decisions.md)).

## Audio capture: the heart of the app

Requirement: **nothing is lost**, even through a crash, dead battery, or interruption.

```
AVAudioSession (.playAndRecord, selected input)
      ▼
AVAudioEngine input tap  ──►  Level meter (waveform)
      ▼
Converter (24 kHz, 16-bit, mono)  ──►  Segment writer (60 seconds of raw samples)
                     ▼
              audio/part-000001.pcm, part-000002.pcm ...
                     ▼ fsync every 5 seconds
              On stop: encode into recording.m4a, then delete the segments
```

- **Raw segments, with no container.** AAC in CAF and M4A lost their audio after a SIGKILL, because their metadata is finalized on close ([SP-4](research/SP-4-capture-resilience.md)). Raw samples have no metadata to lose. A crash loses nothing that reached `write()`, and power loss loses up to 5 seconds.
- **Pause keeps the microphone open.** Samples are dropped, and the engine keeps running, so that iOS does not suspend the app and Resume works from the Lock Screen.
- **Interruptions:** calls, Siri, and alarms close the segment, record the pause, and resume on their own when the system allows it. If not possible, the Live Activity shows a Resume button.
- **Route changes:** removing AirPods or connecting Bluetooth closes the segment, reconfigures, and continues.
- **Low disk:** warning at 500 MB, safe stop and preservation at 100 MB.
- **Recovery:** on launch, `RecordingRecovery` finds incomplete sessions, consolidates them, and notifies the user.
- **Estimated size:** mono AAC at 64 kbps is about 29 MB per hour. Raw segments use about 170 MB per hour until the recording ends.
- **Background:** `UIBackgroundModes: audio`, started in the foreground. Measured on a real iPhone past the 30 seconds reported on a forum. The 3-hour run is pending in SP-4.
- `AudioRecordingIntent` requires an active Live Activity for the entire recording, or the recording stops. That makes the Live Activity mandatory in this flow.
- Playback uses `recording.m4a` after consolidation.

## Processing pipeline

Each step is a persisted job. This guarantees resumption after the app closes.

```
Recording ready
    └► Windows (16 kHz mono, 3 minutes, cut at the quietest moment)
         └► Transcription (each window saves its text and checkpoint in one transaction)
              └► (F4 onward)
                   └► Diarization
                        └► Speech + speaker alignment
                             └► Voice print identification
                                  └► Indexing (FTS5 + embeddings)
                                       └► Summary (if automatic)
```

### Job state

```
queued ─► running ─► done
   ▲         │
   │         ├─► paused (app closed, thermal, battery)
   └─────────┘
             └─► failed (with reason and suggested action)
```

- `JobScheduler` runs one at a time, prioritizing what the user just asked for.
- It respects `ProcessInfo.thermalState` and Low Power Mode: it slows down or pauses, with a notice.
- Long transcriptions use `BGContinuedProcessingTask` when the user leaves the app. The task must originate from a user action and the work must be resumable.
- **Background GPU:** always check `BGTaskScheduler.shared.supportedResources`. There are reports of `false` on iPhone 15 Pro and 16 Pro. Submitting Metal work in the background without a guarantee can crash the app (seen in whisper.cpp). Therefore, in the background we only use engines that run on the Neural Engine or CPU. MLX LLM jobs stay in the foreground, unless `LLMCapabilities` and the spike say otherwise.

## Data

### Storage

GRDB on SQLite ([D-004](decisions.md)): migration control, FTS5, predictable performance, and easy auditing.

```
Application Support/Meetlaud/
├── db/meetlaud.sqlite
├── recordings/{uuid}/
│   ├── audio/part-*.pcm      # temporary, only while recording
│   ├── recording.m4a
│   └── attachments/
└── models/{model-id}/        # always excluded from backup
```

### Schema

| Table | Main fields |
|---|---|
| `recording` | id, title, created_at, duration, state, source, folder_id, language, event_ref, deleted_at |
| `folder` | id, name, created_at |
| `marker` | id, recording_id, time, kind (flag, note, photo), text, attachment_path |
| `transcript` | id, recording_id, engine, model_id, language, created_at, is_active |
| `transcript_segment` | id, transcript_id, start, end, text, polished_text, speaker_id, confidence |
| `speaker` | id, recording_id, label, person_id, confirmed |
| `person` | id, name, created_at |
| `voiceprint` | id, person_id, embedding, model_id, quality, created_at |
| `summary` | id, recording_id, template_id, model_id, body, language, created_at |
| `template` | id, name, category, body, source, version |
| `conversation` | id, scope (recording or global), recording_id, title |
| `message` | id, conversation_id, role, body, citations |
| `chunk` | id, recording_id, segment_range, text, embedding, embedding_model |
| `memory` | id, text, source, created_at |
| `job` | id, kind, recording_id, state, progress, checkpoint, error |
| `installed_model` | id, version, role, size, sha256, installed_at |
| `network_log` | id, url, bytes, started_at, finished_at |
| `role_selection`, `benchmark_result`, `model_run_stat`, `advisor_notice` | See [Model management](model-management.md) |

- `transcript_segment` stores `speaker_id`, never a name. Renaming is a single write.
- Summaries use placeholders (`{{speaker:3}}`) internally, and the name is applied at display time. This is what allows names to propagate.
- Embeddings store their `model_id`. A voice print from one model cannot be compared with another: changing the model requires reprocessing or a new capture.

### Search

- **Today:** `LIKE` over titles and notes ([D-031](decisions.md)).
- **Transcripts:** FTS5 with the trigram tokenizer, which finds Japanese with no word segmentation, plus `LIKE` for queries under 3 characters ([D-037](decisions.md)).
- **Vector:** we start with vectors in BLOBs and brute-force similarity with Accelerate ([D-005](decisions.md)). At one person's scale, this is simple and sufficient, and it avoids compiling a custom SQLite. It sits behind a port, so it can become `sqlite-vec` if scale demands.
- **Hybrid:** combines FTS5 and vectors with Reciprocal Rank Fusion.

## Privacy and security

| Control | How |
|---|---|
| Network | Only `ModelDelivery` opens connections. Automated CI rule |
| Models | Downloaded with SHA-256 pinned in the app catalog. No executable code |
| Encryption at rest | iOS Data Protection |
| Backup | `isExcludedFromBackup` by default, with an option in Settings. Models always excluded |
| Voice prints | Per-person consent. Deletable at any time |
| Lock | Optional Face ID / passcode, with the screen hidden in the app switcher |
| Logs | Local, with no meeting content |
| App Store label | "Data Not Collected" |

**Data Protection level:** `.complete` blocks reads while the device is locked, which breaks background recording and transcription. Plan: `completeUntilFirstUserAuthentication` for data in use, validated in SP-4. This trade-off should be documented openly.

**Model catalog:** embedded in the binary, as JSON versioned with the app. The app never needs to contact a server of ours, and the only traffic is the download the user requested.

## Design System

`DesignSystem` holds only what the system does not provide:

- Tokens: semantic colors, spacing, radii, typography.
- Components: `DrawerContainer`, `PromptBar`, `RecordingPill`, `WaveformView`, `TranscriptRow`, `SpeakerChip`, `TemplateCard`, `PlayerBar`, `ModelRow`, `EmptyState`.
- Each component has a Preview, a snapshot test, and an accessibility check.

## Performance targets

These are design targets, not measurements. The harness verifies them on real devices.

| Metric | Target |
|---|---|
| Cold launch to interactive | < 400 ms on iPhone 15 |
| Record tap to capturing | < 300 ms |
| Library scrolling with 10,000 items | No perceptible drops at 120 Hz |
| Open a 3-hour transcript | < 200 ms to first screen |
| Tap a phrase to hearing audio | < 150 ms |
| Search across 1,000 hours of transcripts | < 100 ms (FTS5) |
| Battery for 1 hour of recording, screen off | < 3% |
| App memory with no model | < 80 MB |
| App size without models | < 30 MB |
| Transcription (balanced model) | At least 5x real time on iPhone 15 Pro |
| LLM first token | < 3 s with the model already loaded |

## Dependencies

| Dependency | Use | License |
|---|---|---|
| [GRDB](https://github.com/groue/GRDB.swift) | Database | MIT |
| [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) | ASR | MIT |
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | Parakeet, VAD, diarization, voice embeddings | Apache-2.0 |
| [MLX Swift](https://github.com/ml-explore/mlx-swift) | LLM | MIT |

Criteria for a new dependency: it solves something unreasonable to implement ourselves, has active maintenance, a compatible license, and opens no connections of its own.

Licenses were audited in [SP-6](research/SP-6-license-audit.md).

Warning: FluidAudio and WhisperKit download models from Hugging Face on their own. We **turn that off** and pass local folders, so all networking goes through `ModelDelivery`.

## Future path

- **macOS:** Domain and engines are portable. Features reuse almost everything.
- **Apple Watch:** `AppIntentsKit` already covers the controls.
- **Foundation Models on iOS 27:** the WWDC 2026 announcement describes a `LanguageModel` protocol with adapters for MLX and Core AI. Our `LanguageModelEngine` port absorbs this without changing anything else. It needs a newer SDK, as the installed Xcode 26.6 ships the iOS 26.5 SDK.
