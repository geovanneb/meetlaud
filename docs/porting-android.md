# Bringing Meetlaud to Android

Meetlaud is native on purpose: recording reliability, background rules, and on-device AI all depend on what each platform offers. So Android has its own native app, not a cross-platform port.

## What was planned, and what was decided

The first plan was three repositories: one per app, plus a shared specification. The owner chose one repository instead (D-084): `ios/` and `android/` side by side, so one pull request can change both apps, and generated text and shared contracts cannot drift.

The Android app now lives in `android/`. How it is built, how it stays identical to iOS, and what is left to port are in [The Android app](android.md). The engines it runs are in D-085.

## What both apps share

| Contract | Where it lives |
|---|---|
| Interface text in en, ja, pt-BR, and es | The iOS String Catalogs, converted at build time by `Tools/android-strings` |
| Domain rules, summary prompts, and templates | `ios/Packages/Core/Domain`, ported line by line to `android/domain`, checked by `Tools/parity` |
| Database schema and encodings | The GRDB migrations on iOS, mirrored in `android/app/.../infra/persistence/Schema.kt` |
| Encrypted library export | `ios/Packages/Infrastructure/Archive`, mirrored byte for byte in `infra/archive` |
| Connector protocol, with crypto test vectors | [Connectors](connectors.md) |
| Model catalogs | One per platform, with the same ids where the model is the same |
| Privacy rules | `ios/Tools/check-privacy` and `Tools/check-android` |

## Rules both apps share

- No account, no analytics, no server of ours.
- One module may use the network, for model downloads. Connectors reach only a computer the person paired, on the local network.
- Recording never loses data.
- All interface text in four languages from day one.
