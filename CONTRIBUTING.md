# Contributing to Meetlaud

Thank you for helping. Meetlaud exists to prove that meeting notes with AI do not need a device to buy, a subscription, or someone else's server. Every contribution that keeps that promise is welcome, from a typo to a new model.

You can write issues and discussions in English, Japanese, Portuguese, or Spanish. Code, commits, and technical docs are in English.

## Ways to help

| You are... | You could... |
|---|---|
| A user | Report a bug, suggest a feature, or test on your own iPhone or iPad |
| A native speaker of ja, pt-BR, or es | Review the interface text and the translated READMEs |
| A professional | Write a summary template for your field (sales, medicine, law, research...) |
| An iOS developer | Pick an issue labeled `good first issue` or `help wanted` |
| An ML engineer | Evaluate a new on-device model, or improve the summary prompts |
| An Android developer | Help start the Android app ([plan](docs/porting-android.md)) |

For anything larger than a small fix, please open an issue first, so that we can agree on the approach before you spend time on it.

## The promise, in rules

These rules protect what makes Meetlaud worth using. The build checks most of them, so you will know fast if something breaks one.

1. **Recording never loses data.** Any change to capture must pass the interruption and recovery tests, on a real device.
2. **No network outside `ModelDelivery`**, except `ConnectorGTD`, which reaches only a computer the person paired on their local network. No analytics, telemetry, crash reporters, or SDKs that open connections. `Tools/check-privacy` enforces this.
3. **No accounts and no login.**
4. **`Domain` is pure Swift.** It imports no UI, audio, database, or AI framework.
5. **Features do not import features.** They talk through `Domain` and the router. `Tools/check-architecture` enforces this.
6. **Every AI engine sits behind a port.** No feature knows about WhisperKit, FluidAudio, or MLX.
7. **Only one large model in memory at a time.** The `ModelArbiter` decides.
8. **All interface text lives in the String Catalog**, in English, Japanese, Portuguese (Brazil), and Spanish. `Tools/check-l10n` enforces this.
9. **Native components first.** A custom component needs a reason, and must support VoiceOver, Dynamic Type, and Reduce Motion.

The reasons behind these and other choices are in the [decision log](docs/decisions.md). To change a closed decision, open an issue first.

## Set up

You need a Mac with Xcode 26 and [Homebrew](https://brew.sh).

```sh
make bootstrap          # installs XcodeGen, SwiftLint, SwiftFormat, and generates the project
open Meetlaud.xcodeproj
```

The Xcode project is generated from `project.yml` and is not committed. Run `make generate` after adding files.

To run on a real device, create `Config/Local.xcconfig` (git ignores it):

```
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

In the simulator, the app runs with scripted engines and sample data, so you can work on every screen without downloading models. Useful launch arguments: `--fake-capture --seed-library` for the test library, and `--showcase` for the fictional meetings in the screenshots.

## Where things are

```
App/                  App entry point and composition root (the only place that knows every module)
Extensions/           Widgets, Live Activity, and controls
Packages/
  Core/               Domain (pure Swift rules and ports), routing, connector interfaces
  Features/           One package per screen area: Home, Detail, Ask, Library, Models, Settings...
  Infrastructure/     Adapters: audio capture, Whisper, Apple Speech, diarization, MLX, database, downloads
  Connectors/         Optional connectors, such as Get Things Done
  UI/                 Design system, localization, app shell
  Testing/            Fakes shared by unit and UI tests
AppUITests/           UI tests, accessibility audits, and real-device tests
Tools/                The checks behind `make check`
docs/                 Architecture, design, privacy, decisions, and research
```

Start with [Architecture](docs/architecture.md) for the big picture.

## Before you open a pull request

```sh
make ci
```

| Command | What it does | Needs a build |
|---|---|---|
| `make check` | Architecture, privacy, and localization rules | No |
| `make lint` | The rules above, plus SwiftFormat and SwiftLint | No |
| `make build` | Builds the app | Yes |
| `make test` | Unit tests (Swift Testing) | Yes |
| `make test-ui` | UI tests and the accessibility audit | Yes |
| `make format` | Formats the code | No |
| `make screenshots` | Regenerates the README pictures in light and dark | Yes |

Then:

- **Tests:** new behavior comes with tests. Use Swift Testing, and put shared fakes in `TestSupport`.
- **Text:** add every new string to the String Catalog in all four languages. A machine translation is fine as a start. Say so in the PR, and a native speaker will review it.
- **Real devices:** changes to capture, background work, or models need a run on a real iPhone (`RealDeviceCaptureTests`). These tests leave test recordings in the app.
- **New dependency:** check the license of the package and of any model it brings, then update `THIRD_PARTY_NOTICES.md` and `Tools/privacy-allowlist.json`, and explain the choice in the PR.
- **Changelog:** add a line to `CHANGELOG.md` under "Unreleased" for anything a person would notice.

## Commits and pull requests

- Use [Conventional Commits](https://www.conventionalcommits.org): `feat:`, `fix:`, `docs:`, `test:`, `refactor:`.
- Keep pull requests small and focused on one change. Fill in the template.
- Screenshots or short videos help a lot for anything visual. Use fictional data only.

## Things we will not merge

- Screenshots, designs, text, or assets copied from other products.
- Real people's recordings, names, or personal data in tests, fixtures, or screenshots.
- Anything that sends meeting content off the device without the person's explicit action.
- Code generated by AI that the author has not read and understood. AI tools are welcome: the project's rules for coding agents are in [CLAUDE.md](CLAUDE.md), and you are responsible for what you submit.

## License

By contributing, you agree that your contribution is licensed under the [Apache License 2.0](LICENSE), as section 5 of that license describes.

## Code of conduct

Everyone in this project follows the [Code of Conduct](CODE_OF_CONDUCT.md).
