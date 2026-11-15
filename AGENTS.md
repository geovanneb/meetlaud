# Instructions for AI coding agents

This file is for AI agents (Claude Code, Codex, Copilot, and others) working on this
repository. The same rules for people are in [CONTRIBUTING.md](CONTRIBUTING.md), which
is the source of truth when the two differ.

**Read in this order:** this file, then `CONTRIBUTING.md`, then `AGENTS.local.md` or
`CLAUDE.local.md` if one exists. Those two are personal notes for one clone (a fork,
a signing team, how that person works). Git ignores them; never commit them.

## The project in one paragraph

Meetlaud is a native, open-source, 100% offline mobile app that records, transcribes, summarizes, and chats about
meetings. It ships as two native apps from this one repository (D-084): `ios/` in Swift and SwiftUI for iPhone and
iPad, and `android/` in Kotlin and Jetpack Compose. Android mirrors iOS screen for screen and feature for feature.

- `ios/App/` is the composition root, `ios/Extensions/` the widgets, Live Activity, and controls,
  `ios/Packages/Core/` the pure Swift `Domain` and its ports, `ios/Packages/Features/` one package per screen area,
  `ios/Packages/Infrastructure/` the adapters (capture, Whisper, diarization, MLX, database, downloads), and
  `ios/Packages/Connectors/` the optional connectors.
- `android/domain/` is a line-by-line port of the iOS `Domain`, `android/app/` holds the design system, features, and
  adapters in packages named like the iOS modules, and `android/engines/` the JNI bridges to whisper.cpp and llama.cpp.
- `Tools/` holds the shared checks and generators, and `docs/` the architecture, decisions, and research.
  [The Android app](docs/android.md) explains how the two stay identical.

## Both platforms, always

Meetlaud is one product. A person on Android and a person on iPhone get the same features, the same screens, and the
same behavior. So:

- **A new feature is built for both platforms**, in the same pull request or in a pair of pull requests that link each
  other and merge together. Design it on iOS first, then port it with the same names, layout, text keys, and tests.
  Shared logic goes into both `Domain`s, and `Tools/parity` must keep passing.
- **A bug is reproduced on both platforms** before it is fixed. Say in the PR where it happens.
  - If it happens on both, the two fixes go together, in one pull request.
  - If it happens on one only, say why the other is not affected (for example, the code is platform-specific).
- **A screen change updates `ParityScreens`** on both sides (`ios/AppUITests/ParityScreens.swift` and
  `android/app/src/androidTest/.../ParityScreens.kt`, same steps and identifiers), and `make parity-screens` shows the
  pair side by side.
- **Text** is added once, to the iOS String Catalogs. Android generates its strings from them at build time.
- If you can build only one platform, say so in the PR. A maintainer finishes the other before merging, and the PR
  stays a draft until then.

## Before implementing

1. Read the issue you are working on, and `ROADMAP.md` for where it fits.
2. Check the current decisions in `docs/decisions.md`. Do not reopen a decision without asking.
3. Plan the change for both platforms (see "Both platforms, always").
4. When done, add a line to `CHANGELOG.md` under "Unreleased", and update any doc the change affects.
5. Never add screenshots, text, or assets from other products, or real people's data.

## Non-negotiable rules

These hold on both platforms. `make check` enforces most of them for both apps.

- **No networking outside `ModelDelivery`** (`infra.modeldelivery` on Android), except `ConnectorGTD`, on the local network only, to a computer the person paired (D-072). No analytics, no telemetry, no remote crash reporter, no third-party SDK that opens a connection.
- **No accounts and no login.**
- **Recording never loses data.** Any change to capture must pass the interruption and recovery tests.
- **`Domain` is pure.** On iOS it does not import SwiftUI, AVFoundation, GRDB, CoreML, MLX, or any adapter. On Android `android/domain` imports only Kotlin and kotlinx.
- **Features do not import features.** They communicate through `Domain` and the router.
- **Every engine sits behind a port.** No feature knows about WhisperKit, FluidAudio, MLX, whisper.cpp, llama.cpp, or ONNX Runtime.
- **Only one heavy model loaded at a time.** The `ModelArbiter` decides.
- **All UI text lives in the String Catalog**, in four languages: en (fallback), ja, pt-BR, es. Android reads the same catalogs.
- **Native components first.** A custom component needs a justification and must support VoiceOver and TalkBack, Dynamic Type and font scaling, and Reduce Motion.

## Branches and pull requests

The maintainer **squash-merges**, so the original commits of a merged PR are not on
`main`. A branch that still carries them can show already-merged changes or conflict.

- **Start every PR from the latest `main`** (`git fetch upstream`,
  `git checkout -b <type>/<short-name> upstream/main`), even while other PRs are open.
  In the maintainer's clone, `origin` is this repository, so use `origin/main`.
  Do not start a branch from another unmerged branch just for convenience.
- **Branch names:** `feat/`, `fix/`, `docs/`, `test/`, `refactor/`, `chore/`, followed by
  a short description in kebab case.
- **One logical change per PR**, reviewable and mergeable on its own.
- **Don't add to the same spot in a file as another open PR.** The usual hot spots here:
  - `CHANGELOG.md`: add your line under the heading it belongs to, not always at the end
    of "Unreleased".
  - `docs/decisions.md`: decision IDs (`D-0xx`) are shared. Before taking the next
    number, check `main` and the open PRs (`gh pr list`). If two PRs take the same
    number, the one merged second renumbers.
  - String Catalogs (`*.xcstrings`): keys are sorted. Let Xcode or the existing order
    place new keys; never reformat or re-sort the whole file.
  - `ios/project.yml`, `android/settings.gradle.kts`, and `android/gradle/libs.versions.toml`: add entries next to
    the related ones.
- **When the change needs an unmerged PR** (its code or its behavior): prefer waiting
  until that PR is merged. Otherwise branch from it, record the parent's tip
  (`git rev-parse <parent-branch>`), open the PR as a **draft** and write
  "Depends on #N, please merge that first." After #N is merged:
  `git rebase --onto upstream/main <recorded-parent-tip> <your-branch>`, compare with
  `git range-diff`, run the checks, push with `--force-with-lease`, remove the
  "Depends on" line, and mark the PR ready only when CI passed on that push and GitHub
  shows no conflicts. In a chain, move the next PR onto the rewritten one straight away
  and keep it a draft.
- If the maintainer changed the parent before merging it, check your change against what
  actually landed, not against the old parent.
- **When an open PR conflicts with `main`:** on your own branch, rebase onto the latest
  `main` and push with `--force-with-lease`. On someone else's branch (a contributor's
  fork, with "Allow edits by maintainers"), merge `main` into it instead and push a
  normal commit, so their history is not rewritten. Either way, keep both sides' intent
  when resolving, then run `make check` (and `make test` when code changed) before pushing.
- PR titles follow [Conventional Commits](https://www.conventionalcommits.org)
  (`feat(models): …`, `fix: …`); they become the commit on `main`. Fill in
  `.github/pull_request_template.md`.
- Never push to `main` directly, and never force-push a branch you did not create
  unless its owner asked.

## Before you open or update a PR

- `make ci` must pass: both apps' checks, lint, unit tests, and builds. Without a Mac, run at least `make check` and
  `make android-test`, and say in the PR which steps you could not run.
- CI on a pull request runs only the iOS UI smoke set, never every UI test (D-082), and the Android instrumented tests
  on an emulator. When you change a screen, run its UI tests locally on both platforms:
  `make test-ui XCODEFLAGS="-only-testing:MeetlaudUITests/<Class>"` and `Tools/android-ui-tests <class>`.
- In iOS UI tests, tap with `tapWhenReady()`, not `tap()`. On a slow CI machine a drawer, menu, or sheet that just
  opened is not there yet, and a plain tap fails.
- Android unit tests run on the JVM, whose regular expressions and text APIs differ from Android's. Code that parses
  text needs a test in `android/app/src/androidTest` too (see `DomainTextOnDevice`).
- Use fictional data only. Never put real recordings, real people, or company names into code, tests, screenshots,
  commits, or PR text.
- Every new dependency needs its license, and its models' licenses, checked and recorded in `THIRD_PARTY_NOTICES.md`
  and in `ios/Tools/privacy-allowlist.json` or `android/privacy-allowlist.json`.
- Changes to capture, background work, or models need a run on a real iPhone (`RealDeviceCaptureTests`) and a real
  Android phone (record with the screen off, transcribe, separate voices). If you cannot do that, say so in the PR.

## Conventions

- All documentation, code, identifiers, and commits are in English.
- Swift 6 with strict concurrency. No `@unchecked Sendable` without a comment explaining why.
- Kotlin 2 with coroutines. A Swift `actor` becomes a single-thread lane (`actorLane()`), as the existing ports do.
- Tests use Swift Testing on iOS and JUnit on Android. Fakes live in `TestSupport` on iOS.
- The product name lives only in `ios/Config/Product.xcconfig` and the String Catalog.

## Commands

From the repository root:

```
make bootstrap        # install the iOS tools and generate the Xcode project
make check            # architecture, privacy, and localization rules of both apps, no build needed
make lint             # the rules above, plus formatting and Android lint
make test             # unit tests of both apps
make ci               # everything CI runs, except the Android instrumented tests
make test-ui          # iOS UI tests and accessibility audit
make test-ui-smoke    # the iOS UI smoke set that pull requests run
make android-test-ui  # Android instrumented tests on a phone or emulator
make parity-screens   # both apps' parity screenshots, side by side
```

Releases: see [Releasing](docs/releasing.md).
