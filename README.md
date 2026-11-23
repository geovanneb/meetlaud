<p align="center"><img src="docs/assets/logo.png" width="120" alt="Meetlaud logo"></p>

<h1 align="center">Meetlaud</h1>

<p align="center"><strong>Your meetings, remembered. On your phone, not in someone else's cloud.</strong></p>

<p align="center">
English · <a href="README.ja.md">日本語</a> · <a href="README.pt-BR.md">Português</a> · <a href="README.es.md">Español</a>
</p>

<p align="center">
<img alt="License: Apache-2.0" src="https://img.shields.io/badge/license-Apache--2.0-blue">
<img alt="Platform: iOS and iPadOS 26+" src="https://img.shields.io/badge/iOS%20%7C%20iPadOS-26%2B-black">
<img alt="Platform: Android 10+" src="https://img.shields.io/badge/Android-10%2B-3ddc84">
<img alt="Swift 6 and Kotlin 2" src="https://img.shields.io/badge/Swift%206%20%7C%20Kotlin%202-orange">
<img alt="Works offline" src="https://img.shields.io/badge/AI-100%25%20on%20device-2ea44f">
</p>

<p align="center">
<a href="https://play.google.com/store/apps/details?id=com.meetlaud.app"><img alt="Get it on Google Play" src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png" height="80"></a>
</p>

Meetlaud records your meetings, transcribes them, tells you who said what, writes the summary, and answers your questions about them. All of it runs on your phone: iPhone, iPad, or Android.

- **Nothing to buy.** No recorder, no clip-on device. The phone in your pocket already has a great microphone and a chip built for AI.
- **Nothing to pay every month.** No subscription and no limit on minutes. Record a 3-hour workshop as often as you like.
- **Nowhere for your data to go.** No account and no server. Your recordings never leave the device unless you send them yourself.
- **Nothing to take on faith.** The code is open. Anyone can read it and check every promise on this page.

<p align="center">
<picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/01-home-dark.png"><img src="docs/screenshots/01-home-light.png" width="180" alt="Home: your meetings and what is coming up"></picture>
<picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/02-transcript-dark.png"><img src="docs/screenshots/02-transcript-light.png" width="180" alt="Transcript with each speaker named"></picture>
<picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/03-summary-dark.png"><img src="docs/screenshots/03-summary-light.png" width="180" alt="Summary with key points, decisions, and action items, each linked to the moment it was said"></picture>
<picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/04-ask-dark.png"><img src="docs/screenshots/04-ask-light.png" width="180" alt="Ask a question and get an answer with its sources"></picture>
</p>

<p align="center"><sub>Screenshots use fictional meetings and people. They show the iPhone app; the Android app has the same screens.</sub></p>

> **Status: 1.0 on Android.** Meetlaud for Android is on [Google Play](https://play.google.com/store/apps/details?id=com.meetlaud.app). The iPhone and iPad app is not on the App Store yet. You can build it yourself ([how](#build-it-yourself)) or install the unsigned build from the [Releases](../../releases) page. A public TestFlight and the App Store come next.

## Why Meetlaud

Most AI note-takers ask you to buy a device, pay a monthly plan, and send your audio to servers you will never see. For a sales call, a board meeting, a patient visit, or a job interview, that is a lot to accept.

Phones are now fast enough to do this work themselves. Meetlaud uses open AI models that run directly on the phone: on the iPhone's Neural Engine and GPU, and on the Android phone's processor. Once a model is downloaded, it works in airplane mode.

| | Meetlaud |
|---|---|
| Hardware | The iPhone, iPad, or Android phone you already own |
| Price | Free and open source |
| Recording limit | None |
| Where the AI runs | On your device |
| Account | None. There is nothing to sign up for |
| Works offline | Yes, after the models are downloaded |
| Source code | Open, Apache-2.0 |

## What it does

**Record**
- One tap to record. On iPhone, also from a widget, the Lock Screen, Control Center, the Action Button, or Shortcuts.
- Keeps recording with the screen locked or the app in the background, with a Live Activity on iPhone and a notification with controls on Android.
- Survives crashes and interruptions: a recording cut short by a call or a crash is recovered.
- Mark moments, add notes, and take photos while you record.
- Import audio files you already have.

**Understand**
- **Transcription** with Whisper (or Apple Speech on iPhone), tested in English, Japanese, Portuguese, and Spanish. Tap any line to hear it.
- **Speaker detection**: the transcript shows who spoke when. Name a voice once, and Meetlaud can suggest that person in the next meeting. Voice prints are optional and stay on the device.
- **Summaries** from templates (meeting, interview, lecture, call, and more), or one you write. Every key point, decision, and action item links to the moment it was said, so you can check it.
- **Ask**: question one meeting, a folder, or your whole library. Answers cite their sources.
- Action items go to Reminders on iPhone, or to any tasks app on Android. Mind maps, custom vocabulary for names and jargon, and a clean reading mode without "um" and "uh".

**Stay in control**
- Folders, search across every transcript, a calendar view of meetings and recordings.
- App lock with Face ID, a fingerprint, or your screen lock, and password-protected export of your whole library. A library exported on one platform opens on the other.
- **AI models screen:** choose the model for each job, see what fits your device, and run a speed test on your own audio.
- **Network activity screen:** lists every connection the app makes, to download models or to the computer you paired. On a fresh install it says "Nothing has left this device". You can clear the history.
- Interface in English, Japanese, Portuguese, and Spanish, with VoiceOver and TalkBack, and larger text.

<p align="center">
<picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/05-recording-dark.png"><img src="docs/screenshots/05-recording-light.png" width="180" alt="Recording screen with moment, photo, and note buttons"></picture>
<picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/06-network-dark.png"><img src="docs/screenshots/06-network-light.png" width="180" alt="Network activity: nothing has left this device"></picture>
</p>

## Privacy you can check

Meetlaud makes exactly two kinds of connection, and both are listed in **Settings > Network activity**:

1. **AI model downloads that you start.** They come from Hugging Face, at pinned versions with checked hashes. No meeting content is sent.
2. **Optional: your own computer.** If you pair a desktop app on your own network, new meetings go straight to it, encrypted. Today this works with [Get Things Done](https://github.com/geovanneb/get-things-done), an open-source work memory for AI tools that runs on your computer. Nothing passes through the internet.

There is no analytics, no crash-reporting service, no advertising, and no account. The build enforces this: `make check` fails if any code outside the download module and the connector to your computer opens a network connection. Details in [Privacy](docs/PRIVACY.md).

## Requirements

| | Records and transcribes | Summaries and Ask |
|---|---|---|
| iPhone or iPad on iOS / iPadOS 26 | Yes | Needs about 8 GB of memory (for example iPhone 15 Pro or later, or an iPad with an M chip) |
| Android 10 or later, 64-bit | Yes | Needs about 4 GB of memory. Entry-level phones work, slowly: a summary of a 10-minute meeting took 24 minutes on a 4 GB phone |

Models are downloaded once, over Wi-Fi by default: about 0.2 to 0.7 GB for transcription and 1.3 to 1.6 GB for summaries. On iPhone, Apple Speech and search need no download; Android downloads a 0.6 GB search model.

## Build it yourself

```sh
git clone <this repository>
cd meetlaud
```

**iPhone and iPad.** You need a Mac with Xcode 26 and [Homebrew](https://brew.sh).

```sh
make bootstrap        # installs the tools and generates the Xcode project
open ios/Meetlaud.xcodeproj
```

Run the `Meetlaud` scheme on a simulator. To run on your own iPhone, add your team ID and a bundle identifier of your own to `ios/Config/Local.xcconfig` (see [CONTRIBUTING.md](CONTRIBUTING.md)).

**Android.** You need JDK 17 and the Android SDK with the NDK, on macOS, Linux, or Windows.

```sh
make android-install  # builds the app and installs it on the phone connected over USB
```

Or open `android/` in Android Studio. Details in [The Android app](docs/android.md).

## How it works

Two native apps from one repository: Swift 6 and SwiftUI in `ios/`, Kotlin and Jetpack Compose in `android/`. Both follow the same rules: the domain layer is pure, every AI engine sits behind a port, and only one large model is in memory at a time. The Android domain is a line-by-line port of the iOS one, and the build checks that both give the same answers. The interface text comes from one set of String Catalogs.

| Job | iPhone and iPad | Android | Model license |
|---|---|---|---|
| Transcription | [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) (Core ML), Apple Speech | [whisper.cpp](https://github.com/ggml-org/whisper.cpp) | MIT (Whisper) |
| Speaker detection and voice prints | [FluidAudio](https://github.com/FluidInference/FluidAudio) (pyannote Community-1) | [ONNX Runtime](https://github.com/microsoft/onnxruntime) (pyannote and WeSpeaker) | MIT, CC-BY-4.0 |
| Summaries and Ask | [MLX Swift](https://github.com/ml-explore/mlx-swift) with Qwen 3.5 2B | [llama.cpp](https://github.com/ggml-org/llama.cpp) with Qwen 3.5 2B | Apache-2.0 |
| Search | Apple on-device embeddings, SQLite FTS5 via [GRDB](https://github.com/groue/GRDB.swift) | Qwen3 Embedding with llama.cpp, SQLite FTS5 | Apache-2.0 |

Read more: [Architecture](docs/architecture.md) · [The Android app](docs/android.md) · [On-device AI](docs/on-device-ai.md) · [Model management](docs/model-management.md) · [Connectors](docs/connectors.md) · [All docs](docs/README.md)

## Contributing

Contributions are welcome, from a typo to a new language model. Start with [CONTRIBUTING.md](CONTRIBUTING.md). Good places to begin:

- **Translations:** native review of Japanese, Portuguese, and Spanish.
- **Testing on real devices:** older iPhones, iPads, Android phones from many makers, long meetings, noisy rooms.
- **Summary templates** for your profession.
- **Both platforms:** every feature and fix lands on iPhone and Android together. If you know one platform, you can still help: port a change to it, or check a bug there.

See the [roadmap](ROADMAP.md) for what comes next. Found a privacy or security issue? Please follow [SECURITY.md](SECURITY.md) instead of opening a public issue.

## Good to know

- **AI can be wrong.** Summaries and answers link to their sources so you can check them. Do not rely on them for medical, legal, or financial decisions without checking.
- **Ask before you record.** Laws on recording conversations differ by country and state, and some require everyone's consent. That is your responsibility, and the app reminds you before your first recording.
- **Phone calls:** iOS and Android do not let apps record calls. You can import recordings made by the phone itself.

## License and trademarks

The code is licensed under [Apache-2.0](LICENSE). Models and libraries keep their own licenses, listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

The Apache license covers the code, not the Meetlaud name or logo. You are welcome to fork the project. Please give your version a different name and icon so people can tell them apart.

Meetlaud is an independent project. It is not affiliated with, endorsed by, or sponsored by any maker of recording devices or note-taking services. iPhone, iPad, and Apple are trademarks of Apple Inc. Android and Google Play are trademarks of Google LLC. All other trademarks belong to their owners.
