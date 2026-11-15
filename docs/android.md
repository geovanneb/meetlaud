# The Android app

Meetlaud has two native apps in this repository: `ios/` in Swift and `android/` in Kotlin with Jetpack Compose. Android mirrors iOS feature for feature and screen for screen, with the same look (D-084). This page is for people who build or change the Android app.

## Rule one: iOS leads, Android follows

Every feature is designed on iOS first. Android then ports it with the same names, the same behavior, and the same layout. When you change one app, change the other in the same pull request, or open the follow-up right away.

What keeps the two apps from drifting:

| Shared | How |
|---|---|
| Text in four languages | Generated at build time from the iOS String Catalogs by `Tools/android-strings`. `L10n.Home.upcoming` is the same accessor on both platforms. Android-only text lives in `android/l10n/Platform.xcstrings` |
| Domain rules | `android/domain` is a line-by-line port of `ios/Packages/Core/Domain`. `Tools/parity/run` runs the Swift code on fixed cases and the Kotlin tests must give the same answers (`Tools/parity/golden.json`) |
| Database | The same SQLite schema, migrations, and value encodings as GRDB on iOS |
| Library export | The same encrypted file format, byte for byte. `SealedStreamTest` reads a file made by the iOS code |
| Icons and type | Lucide icons named after the SF Symbol they replace (`SfIcon("folder")`), from `Tools/android-icons`. Inter in place of SF Pro |
| Screens | `ParityScreens` exists in both apps' UI tests with the same steps and identifiers. `Tools/parity-screens` takes both sets of screenshots and `Tools/compare-screens` lays each pair side by side, in points |

## Layout

| Folder | What it holds | iOS counterpart |
|---|---|---|
| `android/domain` | Pure Kotlin: models, ports, coordinators | `ios/Packages/Core/Domain` |
| `android/app/.../designsystem` | Colors, type, spacing, and iOS-style components | `DesignSystem` |
| `android/app/.../feature/*` | One package per screen area | `ios/Packages/Features/*` |
| `android/app/.../infra/*` | Adapters: capture, audio, database, engines, model delivery, system | `ios/Packages/Infrastructure/*` |
| `android/engines/whisper`, `android/engines/llama` | JNI bridges to whisper.cpp and llama.cpp, built from pinned sources | WhisperKit, MLX |
| `android/app/.../Composition.kt`, `AppContainer.kt` | The composition root | `ios/App/Sources` |

`Tools/check-android` enforces the boundaries: `domain` imports no Android code, features do not import other features or adapters, only `infra.modeldelivery` may open a network connection, every dependency and permission is in `android/privacy-allowlist.json`, and no UI text is written in code.

## On-device AI (D-085)

| Job | Engine | Model |
|---|---|---|
| Transcription | whisper.cpp | Whisper Small (q8) or Turbo (q5) |
| Chat and summaries | llama.cpp | Qwen 3.5 2B (Q4_K_M) |
| Search | llama.cpp | Qwen3 Embedding 0.6B (Q8). iOS uses the system's models; Android has none |
| Speaker separation and voice prints | ONNX Runtime | pyannote segmentation 3.0 with WeSpeaker ResNet34-LM |

Everything runs on the CPU. Models come from `android/app/src/main/assets/models.json`, made by `Tools/generate-android-catalog` with pinned revisions, sizes, and SHA-256 hashes. `ModelDownloader` is the only code that reaches the network. It resumes with HTTP ranges, verifies every file, and keeps going with the screen off through a foreground service.

The memory figure for Qwen is 2000 MB on Android against 3500 MB on iOS: llama.cpp maps the weights from storage and needs no GPU copy. On the emulator, writing a summary peaked at 2.6 GB PSS, most of it file pages the system can drop.

## Commands

From the repository root:

```
make android-check      # boundaries, privacy, text, icons. No build
make android-build      # debug APK
make android-test       # unit tests, including the parity answers
make android-test-ui    # UI and instrumented tests on the phone or emulator
make android-install    # install on the connected phone
```

The engine tests download real models and run them, so they run on request:

```
cd android && ./gradlew connectedDebugAndroidTest \
  -Pandroid.injected.androidTest.leaveApksInstalledAfterRun=true \
  -Pandroid.testInstrumentationRunnerArguments.class=com.meetlaud.app.infra.engines.EngineTests
```

`DiarizationTest.separatesThreeVoices` runs the whole speaker pipeline on the computer, with the ONNX models in `DIARIZATION_MODELS` and a 16 kHz WAV in `DIARIZATION_AUDIO` (with a `truth.json` next to it). Use fictional speech only, such as the computer's own voices.

## Testing on a Xiaomi phone

MIUI adds two hurdles. It asks on the phone before each install over USB ("Install via USB"), so watch the screen
when tests start. And it blocks the UI tests from opening the app from the background until the debug app has the
"open windows in the background" permission: `Tools/parity-screens` grants it with `appops`, and by hand it is
`adb shell appops set com.meetlaud.app 10021 allow`.

Measured on a Redmi Note 11 (Snapdragon 680, 4 GB, no dot product instructions), for 10 minutes of a real recording:
transcription with Whisper Small took 13 minutes, speaker separation 6, and a summary with Qwen 3.5 2B 24. All ran
with the screen off. Phones from the last few years run ggml two to four times faster.

## Testing on the emulator

A phone is the reference, as `RealDeviceCaptureTests` is on iOS. Without one, an ARM64 emulator runs everything, with two known quirks:

- **DNS.** The emulator can fail to resolve the Hugging Face CDN. Downloads then pause, as they would offline. Copy the model files into the app's `files/Meetlaud/models/.staging/<id>/` folder with a `.wanted` file, and the app verifies and installs them at launch.
- **Apple silicon.** The emulator reports SME on M4 Macs without running it. ONNX Runtime's SME kernels are turned off for this reason (`mlas.disable_kleidiai`).

## What is not ported yet

Tracked here until done, so nobody mistakes Android for complete:

- Home Screen widgets, a Quick Settings tile, and app shortcuts, the counterparts of iOS widgets, Control Center, and the Action Button. Until then, Android hides the widget setting and the Action Button help topic.
- The Get Things Done connector (`ConnectorGTD`).
- Showing recordings in the system's search, the counterpart of Spotlight. Until then, Android hides that setting.

Where the iOS text names iPhone, iOS, or Face ID, Android shows its own text from `android/l10n/Platform.xcstrings`, through `PlatformText`. Add a key there, in the four languages, rather than showing an Apple word on Android.
- `ParityScreens` covers the shell and Home. Every other screen still needs its step in both apps.
- A real-device run of the capture interruption and recovery tests.
