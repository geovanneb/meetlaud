# Model management

Models are the most delicate moment of the first-run experience. The user faces gigabytes of downloads, technical names, and hardware they know nothing about. This system must make that feel like one tap, while still giving power users full control.

## Goals

1. **One tap is enough.** A user who knows nothing about models taps once and gets the best setup for their device.
2. **Never blocked.** The app stays usable while anything downloads.
3. **Measured, not guessed.** Users can test speed on their own hardware.
4. **Always a current recommendation.** The app keeps watching the device and points to the best option.
5. **Full control.** Every model can be chosen, tested, compared, paused, and deleted, per function.
6. **Deleting a model never deletes a meeting.**

## Model roles

Each function has its own model, chosen independently.

| Role | What the user sees | Technical function | Required for |
|---|---|---|---|
| Transcription | "Turns speech into text" | ASR | Transcript |
| Speaker separation | "Tells who spoke when" | Diarization | Speaker labels |
| Voice print | "Recognizes saved people" | Speaker embedding | People |
| Chat & summary | "Writes summaries and answers questions" | LLM | Summary, Ask, Auto Polish |
| Search | "Finds meaning across meetings" | Text embedding | Ask across the library |

Details:

- **VAD ships inside the app.** Silero VAD is small and MIT licensed, so users never see it. It also powers the device probe below.
- **Summary can differ from chat.** By default they share one model. An advanced toggle allows one for each.
- **A model can serve two roles.** For example, a diarization pipeline may include the speaker embedding. The catalog declares `roles: [...]`, the UI shows it under both, with "Shared with Speaker separation", and it downloads only once.
- **Apple models live in the same list**, tagged "Managed by iOS": SpeechTranscriber and Foundation Models. Foundation Models cannot be deleted from the app. SpeechTranscriber languages can be released through `AssetInventory`.

Initial candidates are in [On-device AI](on-device-ai.md). The final catalog depends on the spikes.

## Automatic by default

Each role has a selection mode:

- **Automatic (default).** The app picks the best installed model for the language and the moment. Example: Whisper for Japanese and Parakeet for Spanish, with no user decision.
- **Pinned.** The user picks a specific model, and the app respects it.

**Priority** is a single simple setting: Speed, Balanced, or Quality. It influences recommendations, without any technical choice.

## User journey

### First run

```
┌───────────────────────────────┐
│ Set up on-device AI           │
│                               │
│ Recommended for your iPhone   │
│ 16 Pro                        │
│                               │
│ ✓ Transcription               │
│ ✓ Speakers and voice prints   │
│ ✓ Chat and summaries          │
│ ✓ Search                      │
│                               │
│ 2.4 GB · about 6 min on Wi-Fi │
│ You have 41 GB free           │
│                               │
│ [      Download all       ]   │
│         Customize             │
│         Not now               │
└───────────────────────────────┘
```

- One button. No model names on this screen.
- "Customize" opens the AI models hub.
- "Not now" still works: Apple's engines cover transcription where supported.
- The screen closes as soon as the download starts. A small indicator stays in Home, and users can record right away.
- When finished, each model prepares itself, runs a short self-test, and becomes active.
- Starting with Transcription first is automatic: the smallest useful role downloads first, so value arrives early.

### AI models hub (Settings > AI models)

```
┌───────────────────────────────┐
│ ‹      AI models              │
│ ┌───────────────────────────┐ │
│ │ iPhone 16 Pro             │ │
│ │ ● Right now: Great        │ │
│ │ 8 GB · 41 GB free · Cool  │ │
│ │ 1 suggestion          ›   │ │
│ └───────────────────────────┘ │
│ Priority  [Speed|Balanced|Quality]│
│                               │
│ Transcription      Automatic ›│
│ Whisper turbo · ~6 min/hour   │
│ Speaker separation  Automatic ›│
│ Pyannote · ~2 min/hour        │
│ Voice print        Automatic ›│
│ WeSpeaker · Shared            │
│ Chat & summary     Automatic ›│
│ Not installed ▸ Get           │
│ Search             Automatic ›│
│ iOS built-in                  │
│                               │
│ Storage  3.1 GB of models    ›│
│ Downloads  1 in progress     ›│
│ Test this iPhone             ›│
└───────────────────────────────┘
```

### Role screen

```
┌───────────────────────────────┐
│ ‹      Transcription          │
│ Mode: Automatic           ⌄   │
│                               │
│ INSTALLED                     │
│ Whisper turbo      ★ Best fit │
│ 626 MB · Measured: 9x         │
│ 1 hour in about 6 min         │
│                               │
│ AVAILABLE                     │
│ Parakeet v3         Good fit  │
│ 494 MB · Estimated: 20-30x    │
│ en es pt, no Japanese    ↓ Get│
│ Whisper small       Good fit  │
│ 250 MB · Estimated: 8-12x ↓ Get│
│                               │
│ Show all models               │
└───────────────────────────────┘
```

Sizes and speeds above are illustrative.

### Model detail

Size on disk, memory needed, languages, license, source, version, plus:

- **Speed:** estimated or measured, in plain words ("1 hour in about 6 minutes").
- **Quality:** from our evaluation, per language, in simple levels.
- **Fit on this device,** with the reason in one line.
- **Actions:** Get, Pause, Test speed, Try on my audio, Use this model, Delete.
- **Used by:** recordings or voice prints that depend on it.

## Install states

```
available ─► queued ─► downloading ◄─► paused
                           │
                           ├─► waitingForWiFi
                           ▼
                       verifying ─► preparing ─► selfTest ─► ready
                           │             │           │
                           └─────────────┴───────────┴─► failed (retry)
ready ─► updateAvailable
```

## Download rules

- **Space check first.** Needs model size + preparation overhead + a safety margin. If it does not fit, it offers to free space.
- **Wi-Fi only by default.** Cellular asks once per download, with the size.
- **Background `URLSession`.** Continues when the app closes.
- **Resumable, per file.** Multi-file models resume where they stopped.
- **Atomic install.** Temporary folder, verify SHA-256, then move. A partial model is never visible to engines.
- **Real ETA** from observed throughput, not a fixed guess.
- **Queue order:** user request first, then smallest useful role.
- **Local notification** when ready, only if the user allows notifications.
- **Every connection** is logged in Network activity.

## Recording always wins

- Downloads may continue during a recording, because they only use the network.
- Preparing, self-tests, and speed tests **never** start during a recording, and an active test stops the moment recording starts.
- A speed test cannot block Record.

## Speed test

Available per model, per role, or for the whole device ("Test this iPhone").

### What it measures

| Role | Test | Result in plain words |
|---|---|---|
| Transcription | Bundled clip, per language selected | "1 hour in about 6 minutes" |
| Speaker separation | Bundled multi-speaker clip | "1 hour in about 2 minutes" |
| Voice print | Fixed short speech samples | "Ready in under a second per person" |
| Chat & summary | Fixed prompt, time to first token, tokens per second | "Summary of 1 hour in about 2 minutes" |
| Search | Fixed text batch | "Indexes 1 hour in about 10 seconds" |

Always recorded: peak memory, load time, thermal state before and after, power state, OS version, and app version.

### Two modes

- **Quick test (about 30 seconds).** Peak speed.
- **Sustained test (about 3 minutes).** Phones throttle under heat, so a short burst flatters them. This one reflects a real 1-hour job, and offers a heads-up that the phone may warm up.

### Rules

- Foreground only, cancelable, with a progress bar.
- Only starts in a suitable state. If the device is already hot, on Low Power Mode, or under 20% battery unplugged, it explains and suggests waiting.
- Runs one model at a time through `ModelArbiter`.
- Results are saved locally, with history.
- **Speed is measured on the device. Quality is not.** Quality comes from our evaluation, and the UI keeps the two apart.
- A result can be copied as text and pasted into a GitHub issue, by user choice. Nothing is sent automatically. This is how the community can contribute benchmarks without telemetry.

### Estimated versus measured

The app must show speed before download, when no model exists to test. Every value is labeled **Estimated** or **Measured**.

1. Maintainers measure each model on reference devices. Results ship in the catalog.
2. A **device probe** of about 3 seconds runs the bundled VAD on the Neural Engine and a small Metal workload on the GPU. It arrives in F4 with the VAD ([D-038](decisions.md)). Until then, estimates use the reference device directly.
3. The estimate scales reference results from the closest device by the probe ratio, shown as a range.
4. After a test or a real job, the measured value replaces the estimate.

## Device Advisor

A local service that continuously answers: **what is the best option for this device, now?**

### Two questions, two time scales

| | Recommended setup | Right now |
|---|---|---|
| Question | Which models should be installed? | Is this a good moment for heavy work? |
| Changes | Rarely | Minute by minute |
| Example | "Qwen 4B fits your iPhone better" | "Your iPhone is warm. This may take 3x longer" |
| Output | Suggestion in AI models | Status and note before a job |

### Signals

| Signal | Source | Used for |
|---|---|---|
| Physical memory | `ProcessInfo.physicalMemory` | Hard limits |
| Available memory | `os_proc_available_memory` | Whether a model loads now |
| Free space | `volumeAvailableCapacityForImportantUsage` | Install, cleanup |
| Thermal state | `thermalState` and its notification | Right now, sustained speed |
| Power | Low Power Mode, battery level, charging | Right now |
| Apple Intelligence | `SystemLanguageModel.default.availability` | Foundation Models option |
| Background GPU | `BGTaskScheduler.shared.supportedResources` | What can run in the background |
| Spoken languages | Preferences and real history | Per-language pick |
| Real job results | Own history | Replaces estimates |
| Failures | Jobs interrupted by a memory kill | Marks a model as unstable here |
| OS and app version | System | Triggers a new evaluation |

iOS exposes no public Neural Engine or GPU load, so "continuous" means reacting to these signals.

### Battery-safe by design

The monitor must not drain what it observes.

- **Event driven:** thermal, power, and memory notifications, no constant polling.
- Light sampling happens only while a job runs or the AI models screen is open.
- Advisor runs again on launch, after each job, on OS or app updates, and on significant storage changes.

### Right now status

Shown in the hub and before heavy jobs.

| Status | Meaning | Example |
|---|---|---|
| Great | Everything available | Cool, charged |
| Good | Works, slightly slower | Warm or battery below 30% |
| Limited | Better to wait | Hot, Low Power Mode, low memory |
| Paused | Job stops and resumes alone | Critical thermal state |

Before a long job:

> **Summarize now?** About 3 minutes. Your iPhone is warm, so it may take longer. Keep the app open.  
> [Start] [Remind me when plugged in]

### Suggestions

| Trigger | Suggestion |
|---|---|
| Better fit found | "Parakeet JA is faster for your Japanese meetings" |
| Language not covered | "Your meetings are in Japanese, and this model does not support it" |
| Repeated memory kills | "This model is unstable on your iPhone. Try Qwen 2B" |
| Measured speed too low | "Transcription takes longer than the meeting. Try a faster model" |
| Low space | "Whisper small has not been used in 60 days. Free 250 MB?" |
| Apple Intelligence turned on | "A no-download option is now available" |
| New device after restore | "This iPhone can run a better setup" |
| Model update in a new app version | "Better version available, 40 MB" |

Rules:

- **The advisor only suggests.** It never downloads, deletes, or changes a pinned model without the user's action.
- Each suggestion explains why, in one line, with one action.
- Dismissal is remembered. It only returns if the situation materially changes.
- No pop-ups. Suggestions appear in the hub, with a small badge in Settings.
- Automatic mode may switch among **installed** models. That is its purpose, and the choice is visible on each transcript.

### Recommendation engine

A pure function in Domain, deterministic and covered by table-driven tests.

```swift
public struct RecommendationEngine {
    public func recommend(
        role: ModelRole,
        catalog: [ModelDescriptor],
        device: DeviceProfile,
        languages: [Locale.Language],
        priority: Priority,
        history: [ModelRunStat]
    ) -> [ModelFit]   // sorted, each with a label and a reason
}
```

1. **Hard filters:** OS, memory budget, language, known instability.
2. **Requirements:** transcription must sustain at least 3x real time, and chat must reach a usable speed.
3. **Score:** per-language quality, weighted by the Priority setting, with measured values preferred over estimates.
4. **Label and reason.**

| Label | Meaning | Action |
|---|---|---|
| ★ Best fit | Top result | Get |
| Good fit | Works well | Get |
| May be slow | Works, below the target | Get, with a note |
| Not recommended | Likely unstable here | Get anyway, with a warning |
| Not supported | Cannot run | Hidden under "Show all", disabled |

## Storage and deletion

- **Storage screen:** total, per role, last used, and "Free up space" suggestions.
- Models are always excluded from iOS backup.
- A model in use by a running job cannot be deleted. The app offers to cancel or wait.
- The confirmation states the consequence.

| Deleted | Consequence |
|---|---|
| Any model | Meetings, transcripts, and summaries stay intact |
| Active model | Falls back to the next installed one, or to Apple's option |
| Voice print model | Saved people stop matching until reinstalled. People and names stay |
| Search model | Ask across the library pauses until another model re-indexes |

## Changing models safely

- Jobs pin the model they started with, so changes never corrupt running work.
- Transcripts record the model used, and retranscribing keeps both versions.
- **Search model change:** re-indexes in the background.
- **Voice print model change:** vectors from different models cannot be compared, and audio of the voice is not stored in the print. While the source recordings exist, the app rebuilds voice prints from confirmed speakers. Otherwise it asks for a new confirmation in the next meeting.

## Try on my audio

The best way to judge quality. The user picks a recording, and the app transcribes 60 seconds with two models, side by side. The user chooses by reading the result.

Compare view: installed models in a role, with speed, memory, and quality per language in one table.

## Errors

Every failure explains itself and offers one action, in plain words.

| Failure | Message | Action |
|---|---|---|
| Lost connection | "Paused. It will continue when you are back online" | Automatic |
| No space | "1.2 GB more needed" | Free up space |
| Corrupted file | "Download was damaged" | Retry, automatic once |
| Server unavailable | "Source is not available right now" | Retry later |
| Preparation failed | "This model could not start on your iPhone" | Try suggested alternative |
| Self-test failed | Same, marks it as unstable | Try suggested alternative |
| No Wi-Fi | "Waiting for Wi-Fi" | Use cellular |

## Architecture

```
Domain
├── ModelDescriptor, ModelRole, ModelFit, DeviceProfile, DeviceCondition
├── RecommendationEngine        # pure function
└── Ports: ModelCatalog, ModelInstaller, ModelBenchmark, DeviceMonitor

Infrastructure
├── ModelDelivery               # the only network module
├── ModelBenchmarks             # one benchmark per role, via engine ports
└── DeviceMonitoring            # signals, no networking

Features
└── FeatureModels               # onboarding, hub, role, detail, storage, test
```

- `DeviceAdvisor` is an `actor` in the composition layer. It combines `DeviceMonitor`, history, and `RecommendationEngine`, and publishes an `AsyncStream<AdvisorState>`.
- `ModelArbiter` and `JobScheduler` read the same state, so UI and scheduling agree.
- Each new engine must provide catalog data and a `ModelBenchmark`. CI fails if a catalog model has no reference benchmark.

### New tables

| Table | Main fields |
|---|---|
| `role_selection` | role, mode, pinned_model_id |
| `benchmark_result` | id, model_id, mode, language, speed, peak_memory, load_time, thermal_start, thermal_end, power, os_version, created_at |
| `model_run_stat` | id, model_id, job_kind, audio_duration, wall_time, thermal_peak, outcome, created_at |
| `advisor_notice` | id, kind, subject, state, dismissed_at |

### Catalog entry

```json
{
  "id": "whisper-large-v3-turbo",
  "version": "2026.1",
  "roles": ["transcription"],
  "displayName": "Whisper turbo",
  "engine": "whisperkit",
  "license": "MIT",
  "source": { "host": "huggingface.co", "repo": "...", "revision": "<commit>" },
  "files": [{ "path": "...", "size": 0, "sha256": "..." }],
  "languages": ["en", "ja", "pt", "es"],
  "requirements": { "minOS": "26.0", "minMemoryMB": 0, "computeUnits": "ane" },
  "backgroundCapable": true,
  "quality": { "en": 0, "ja": 0, "pt": 0, "es": 0 },
  "reference": [{ "device": "iPhone16,1", "speedX": 0, "peakMemoryMB": 0 }]
}
```

Values are placeholders. Real numbers come from `Evals/`.

## Targets

| Metric | Target |
|---|---|
| Taps from opening to download started, recommended setup | 1 after the promise screen |
| Time for the app to be usable after that tap | Immediate |
| Device probe | < 3 s |
| Quick test per model | < 45 s |
| Estimate vs measured gap | Within ±30% |
| Failed download recovery | Automatic in most cases, no restart from zero |
| Battery cost of monitoring when idle | Not measurable |

These are design targets, to be validated in F3 and SP-8.
