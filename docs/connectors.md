# Connectors

A connector hands meeting material to another app. Connectors are plug-ins: each one is its own target, and the app knows them only through the `Connector` protocol.

## How the pieces fit

| Piece | Where | Knows about |
|---|---|---|
| `Connectors` | `Packages/Core/Connectors` | Foundation only |
| A connector, such as `ConnectorGTD` | `Packages/Connectors/<Name>` | `Connectors` and Foundation only |
| Connectors tab | `FeatureTools` | `ConnectorRegistry`, never a specific connector |
| Registration | `App/Sources/AppContainer.swift` | The list of connectors in this build |

`Tools/check-architecture` enforces this table. A connector cannot import `Domain`, a feature, or the database, so it only ever sees the `ConnectorPackage` it is given.

## Add a connector

1. Create `Packages/Connectors/ConnectorName/Sources`, with one type that implements `Connector`.
2. Put its icon in the target's `Resources` folder, and return it as `.image(url)` from `Bundle.module`, or use `.symbol(name)`.
3. Add the target to `Packages/Package.swift`, and to `Tools/architecture.json` with only `Foundation` and `Connectors`.
4. Add it to the `ConnectorRegistry` in `AppContainer`, and link it in `project.yml`.
5. Record its license in `THIRD_PARTY_NOTICES.md`.

Nothing else changes. The tab lists it under its category. A new category or transport needs a case in the manifest and a title in `ConnectorsTab`.

## Rules

- A connector runs only from a person's explicit action, one meeting at a time.
- `availability` stays `.comingSoon` until sending works. The registry refuses to send to one that is not available.
- Opening a connection is not allowed yet. `Tools/check-privacy` applies to connectors like any other code, and allowing local Wi-Fi needs its own decision first (D-067).

## Syncing with Get Things Done

Decided in D-072. The wire format is in `docs/device-inbox.md` in Get Things Done. `ConnectorGTD` is the only connector allowed to use the network, and only local addresses.

**What moves:** meeting audio, and transcripts and photos if the person turns them on in the connector's own screen. Only finished meetings recorded after pairing, only from the iPhone to the computer.

**Who starts:** always the iPhone. It owns the data and knows what is pending, and iOS cannot keep a server running in the background. The computer never asks for anything.

**Pairing, once:** Get Things Done shows a QR code holding its public key and a one-time secret. Meetlaud scans it, and each side proves it saw the code. Nothing else pairs them.

**Finding the computer:** it announces itself with Bonjour, which works on a hotspot and on a shared network. The addresses in the code are the fallback.

**Safety:** both sides derive one key. Everything is sealed with it, and each seal is bound to its place, so joining the network, or posing as the computer, shows nothing. The computer's main server stays on `127.0.0.1`. A small separate inbox listens only while turned on.

**Delivery:** `ConnectorSync` keeps what is pending. The iPhone offers a meeting, the computer answers what it holds, and uploads resume. Sending twice changes nothing. Files land in the Get Things Done meeting queue.

**When it runs:**

| Moment | How | State |
|---|---|---|
| App active, computer appears or a meeting finishes | Bonjour, then upload | Built |
| App suspended | Nothing runs. It catches up the next time the app is active | Limitation |
| Computer joins the hotspot while the app is suspended | iOS sends no event for this. Needs a Bluetooth wake from the computer | Not built: spike SP-9 |

**Open questions for SP-9:** whether Bonjour reaches an app on the iPhone that hosts the hotspot, and how reliably a Bluetooth signal wakes a suspended app. iOS will not wake an app the person force-quit.
