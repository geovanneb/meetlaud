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
APP_BUNDLE_IDENTIFIER = com.example.meetlaud
```

The project's own identifiers belong to the maintainer's team, so pick a bundle identifier of your own. The widget, App Group, test, and background task identifiers derive from it.

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
| `make test-ui-smoke` | The UI smoke set that pull requests run in CI | Yes |
| `make format` | Formats the code | No |
| `make screenshots` | Regenerates the README pictures in light and dark | Yes |

Then:

- **Tests:** new behavior comes with tests. Use Swift Testing, and put shared fakes in `TestSupport`.
- **Text:** add every new string to the String Catalog in all four languages. A machine translation is fine as a start. Say so in the PR, and a native speaker will review it.
- **Real devices:** changes to capture, background work, or models need a run on a real iPhone (`RealDeviceCaptureTests`). These tests leave test recordings in the app.
- **New dependency:** check the license of the package and of any model it brings, then update `THIRD_PARTY_NOTICES.md` and `Tools/privacy-allowlist.json`, and explain the choice in the PR.
- **Changelog:** add a line to `CHANGELOG.md` under "Unreleased" for anything a person would notice.

## How we work (GitHub Flow)

`main` is always releasable. All work happens on short-lived branches and lands through pull requests.

1. **Open or pick an issue** for anything bigger than a small fix.
2. **Fork the repo** and create a branch from the latest `main`, named `feat/`, `fix/`, `docs/`, `test/`, `refactor/`, or `chore/` plus a short description (for example `fix/widget-dark-mode`).
3. **Make your change**, with tests where it makes sense.
4. **Open a pull request** against `main`. Fill in the template and link the issue (`Closes #123`).
5. **CI must pass** and a maintainer reviews. A pull request runs lint, unit tests, and a UI smoke set, in about 10 minutes; a documentation-only one takes about a minute. Every UI test runs on `main` and every night ([details](docs/testing.md#cicd)). We squash-merge, so the PR title becomes the commit message on `main`.

## Keeping pull requests independent

We squash-merge: the commits on your branch become one new commit on `main`, and the original commits are not on `main`. A branch that still carries them can show changes that are already merged, or conflict. These habits keep each PR easy to merge.

### Set up your fork once

```sh
git remote -v          # origin = your fork
git remote add upstream https://github.com/geovanneb/meetlaud.git
```

`origin` is your fork (you push there). `upstream` is this repository (you start new branches from it).

### Start every PR from the latest main

Even while your other PRs are still open, start each new one from `upstream/main`, next to the others rather than on top of them:

```sh
git fetch upstream
git checkout -b feat/my-change upstream/main
```

- **One logical change per PR**, so it can be reviewed and merged on its own.
- **Don't add to the same spot as another open PR.** In this repository the usual places for conflicts are `CHANGELOG.md` (put your line under the heading it belongs to), the decision IDs in `docs/decisions.md` (check `main` and the open PRs before you take the next `D-0xx`), the String Catalogs (never re-sort or reformat the whole file), and `project.yml`. This lowers the risk; it does not remove it.

### When a change needs another PR that isn't merged yet

A depends on nothing; B needs A's code or behavior. Two options:

- **Wait (easiest).** Finish A, open its PR, and work on something else. When A is merged, fetch `upstream` and start B from the new `main`.
- **Build on A, and move B onto main after A is merged.**
  1. Create B from A's branch and **note the commit you started from**:

     ```sh
     git checkout -b feat/b feat/a
     git rev-parse feat/a      # write this down, for example in a comment on B's PR
     ```

  2. Open B as a **draft** and write in its description: **"Depends on #A, please merge that first."**
  3. When A is merged, replay only B's own commits onto the new `main`, using the commit you noted (not the branch name, which may have moved or been deleted):

     ```sh
     git fetch upstream
     git rebase --onto upstream/main <noted-commit> feat/b
     git range-diff <noted-commit>..origin/feat/b upstream/main..feat/b   # B's changes only?
     make ci
     git push --force-with-lease origin feat/b
     ```

     If the maintainer changed A before merging it, check B against what actually landed.
  4. Remove the "Depends on" line. When CI has passed on this push and GitHub shows no conflicts with `main`, mark B as ready for review.

**Chains (A, then B, then C).** When A is merged, move B onto `main` as above, and move C onto the new B straight away (`git rebase --onto feat/b <B's old tip> feat/c`, noting B's old tip first). C stays a draft until B is merged. Keep the old branches until every PR that depends on them has been moved.

### When your PR conflicts with main

Rebase your branch onto the latest `upstream/main`, resolve the conflicts keeping what both sides meant, run `make ci`, and push with `--force-with-lease`. If a maintainer fixes the conflicts for you, they merge `main` into your branch instead, so your history is not rewritten. Pull before you push again.

### Before you mark a PR as ready

- GitHub shows no conflicts with the current `main`.
- CI passed on your latest push. Marking a draft as ready does not run CI again, and a green check from an older push says nothing about today's `main`.
- The diff contains only this change, and any dependency on another PR is stated.

## Commit and PR titles

We use [Conventional Commits](https://www.conventionalcommits.org) for PR titles, because they become the commit on `main` and feed the release notes:

```
fix(capture): keep recording when a call interrupts
feat(models): show the setup's download progress
docs: explain how to sign with your own team
```

Common types: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, `ci`, `build`.

- Keep pull requests small and focused on one change. Fill in the template.
- Screenshots or short videos help a lot for anything visual. Use fictional data only.

## Things we will not merge

- Screenshots, designs, text, or assets copied from other products.
- Real people's recordings, names, or personal data in tests, fixtures, or screenshots.
- Anything that sends meeting content off the device without the person's explicit action.
- Code generated by AI that the author has not read and understood. AI tools are welcome: the project's rules for coding agents are in [AGENTS.md](AGENTS.md), and you are responsible for what you submit.

## License

By contributing, you agree that your contribution is licensed under the [Apache License 2.0](LICENSE), as section 5 of that license describes.

## Code of conduct

Everyone in this project follows the [Code of Conduct](CODE_OF_CONDUCT.md).
