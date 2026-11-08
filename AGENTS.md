# Instructions for AI coding agents

This file is for AI agents (Claude Code, Codex, Copilot, and others) working on this
repository. The same rules for people are in [CONTRIBUTING.md](CONTRIBUTING.md), which
is the source of truth when the two differ.

**Read in this order:** this file, then `CONTRIBUTING.md`, then `AGENTS.local.md` or
`CLAUDE.local.md` if one exists. Those two are personal notes for one clone (a fork,
a signing team, how that person works). Git ignores them; never commit them.

## The project in one paragraph

Meetlaud is a native, open-source, 100% offline iOS/iPadOS app that records, transcribes,
summarizes, and chats about meetings. `App/` is the composition root, `Extensions/` the
widgets, Live Activity, and controls, `Packages/Core/` the pure Swift `Domain` and its
ports, `Packages/Features/` one package per screen area, `Packages/Infrastructure/` the
adapters (capture, Whisper, diarization, MLX, database, downloads), `Packages/Connectors/`
the optional connectors, `Tools/` the checks behind `make check`, and `docs/` the
architecture, decisions, and research.

## Before implementing

1. Read the issue you are working on, and `ROADMAP.md` for where it fits.
2. Check the current decisions in `docs/decisions.md`. Do not reopen a decision without asking.
3. When done, add a line to `CHANGELOG.md` under "Unreleased", and update any doc the change affects.
4. Never add screenshots, text, or assets from other products, or real people's data.

## Non-negotiable rules

- **No networking outside `ModelDelivery`**, except `ConnectorGTD`, on the local network only, to a computer the person paired (D-072). No analytics, no telemetry, no remote crash reporter, no third-party SDK that opens a connection.
- **No accounts and no login.**
- **Recording never loses data.** Any change to capture must pass the interruption and recovery tests.
- **`Domain` is pure Swift.** It does not import SwiftUI, AVFoundation, GRDB, CoreML, MLX, or any adapter.
- **Features do not import features.** They communicate through `Domain` and the router.
- **Every engine sits behind a port.** No feature knows about WhisperKit, FluidAudio, or MLX.
- **Only one heavy model loaded at a time.** The `ModelArbiter` decides.
- **All UI text lives in the String Catalog**, in four languages: en (fallback), ja, pt-BR, es.
- **Native components first.** A custom component needs a justification and must support VoiceOver, Dynamic Type, and Reduce Motion.

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
  - `project.yml`: add targets and settings next to the related ones.
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
  when resolving, then run `make check` (and `make test` when Swift changed) before pushing.
- PR titles follow [Conventional Commits](https://www.conventionalcommits.org)
  (`feat(models): …`, `fix: …`); they become the commit on `main`. Fill in
  `.github/pull_request_template.md`.
- Never push to `main` directly, and never force-push a branch you did not create
  unless its owner asked.

## Before you open or update a PR

- `make ci` must pass. Without a Mac build, at least `make check` must pass, and say in
  the PR which steps you could not run.
- CI on a pull request runs only the UI smoke set, unless the PR touches the UI tests, CI,
  or the build (see `docs/testing.md`). When you change a screen, run its UI test class
  locally (`make test-ui XCODEFLAGS="-only-testing:MeetlaudUITests/<Class>"`).
- Use fictional data only. Never put real recordings, real people, or company names into
  code, tests, screenshots, commits, or PR text.
- Every new dependency needs its license, and its models' licenses, checked and recorded
  in `THIRD_PARTY_NOTICES.md` and `Tools/privacy-allowlist.json`.
- Changes to capture, background work, or models need a run on a real iPhone
  (`RealDeviceCaptureTests`). If you cannot do that, say so in the PR.

## Conventions

- All documentation, code, identifiers, and commits are in English.
- Swift 6 with strict concurrency. No `@unchecked Sendable` without a comment explaining why.
- Tests use Swift Testing. Fakes live in `TestSupport`.
- The product name lives only in `Config/Product.xcconfig` and the String Catalog.

## Commands

```
make bootstrap   # install tools and generate the project
make check       # architecture, privacy, and localization rules, no build needed
make lint        # the rules above, plus formatting
make test        # unit tests
make test-ui     # UI tests and accessibility audit
make test-ui-smoke  # the UI smoke set that pull requests run (Tools/ui-smoke-tests.txt)
make ci          # everything
```
