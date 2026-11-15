# Documentation

| Document | What it covers |
|---|---|
| [Product vision](product-vision.md) | Why Meetlaud exists, who it is for, principles, and honest limits |
| [Privacy](PRIVACY.md) | What leaves the device and what does not, in plain words ([日本語](PRIVACY.ja.md) · [Português](PRIVACY.pt-BR.md) · [Español](PRIVACY.es.md)) |
| [Architecture](architecture.md) | Modules, layers, data, the processing pipeline, and performance targets |
| [On-device AI](on-device-ai.md) | Models, device tiers, summaries, and chat |
| [Model management](model-management.md) | Model roles, downloads, speed tests, and the Device Advisor |
| [UX design](ux-design.md) | Navigation, screens, and flows |
| [Connectors](connectors.md) | How to plug other apps in, and the Get Things Done protocol |
| [Testing](testing.md) | Tests, CI, and the automated quality rules |
| [Decisions](decisions.md) | Why things are the way they are, and the known risks |
| [The Android app](android.md) | How the Android app is built, kept identical to iOS, and tested |
| [Releasing](releasing.md) | How both apps are released together, and what each release contains |
| [Bringing Meetlaud to Android](porting-android.md) | Why one repository holds both apps, and what they share |
| [Research](research/) | Measurements on real devices: language models, voice prints, recording resilience, search, and the license audit |

Architecture, On-device AI, Model management, and UX design describe the iOS app, which every feature starts from. [The Android app](android.md) maps each part to its Android counterpart, and [Decisions](decisions.md) records where they differ (D-084, D-085).

Start with the [Architecture](architecture.md) if you want to change code, and with [CONTRIBUTING.md](../CONTRIBUTING.md) before your first pull request.
