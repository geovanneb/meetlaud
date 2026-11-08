# Meetlaud: project rules

A native, open-source, 100% offline iOS/iPadOS app that records, transcribes, summarizes, and chats about meetings.

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

## Conventions

- All documentation, code, identifiers, and commits are in English.
- Swift 6 with strict concurrency. No `@unchecked Sendable` without a comment explaining why.
- Tests use Swift Testing. Fakes live in `TestSupport`.
- The product name lives only in `Config/Product.xcconfig` and the String Catalog.
- Every new dependency requires checking the license of the package and of its models, and recording it in `THIRD_PARTY_NOTICES.md`.

## Commands

```
make bootstrap   # install tools and generate the project
make check       # architecture, privacy, and localization rules, no build needed
make lint        # the rules above, plus formatting
make test        # unit tests
make test-ui     # UI tests and accessibility audit
make ci          # everything
```
