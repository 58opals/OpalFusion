# Opal Fusion

Opal Fusion is the CashFusion protocol and runtime package for the Opal Bitcoin Cash stack. It exists so coordinator connectivity, covert transport, round-state handling, commitments, blind-signature flow, and blame handling can live in one focused Swift package instead of leaking into app-layer packages, crypto helpers, or product code.

## Canonical Spec

The canonical public-safe implementation spec lives at [docs/cashfusion-implementation-spec.md](./docs/cashfusion-implementation-spec.md).

Use that document as the source of truth for:

- the normative Electron Cash interoperability baseline
- CashFusion round lifecycle and transport expectations
- host integration seams
- phased implementation direction

This README stays intentionally brief and points back to the canonical spec instead of duplicating protocol detail.

## Stack Position

- Above `OpalCrypto`, which owns reusable Bitcoin Cash cryptographic primitives.
- Below `OpalBase`, which owns app-facing wallet, policy, and orchestration behavior.
- Separate from `SwiftFulcrum`, which owns Fulcrum transport responsibilities.
- Separate from product layers such as Opal Wallet.

## Boundaries

- Own CashFusion protocol/runtime boundaries, including coordinator-facing flow, round-state modeling, host integration seams, and interop-specific transport details.
- Do not own wallet UI, product-shell behavior, or end-user policy surfaces.
- Do not own generic Bitcoin Cash app orchestration that belongs in `OpalBase`.
- Do not own generic cryptography that belongs in `OpalCrypto`.
- Do not own Fulcrum transport responsibilities that belong in `SwiftFulcrum`.

## Current Maturity

Opal Fusion now has broad typed protocol and domain modeling, pinned transport/timing baseline values, an internal round engine, live primary/covert runtime and transport adapters, `OpalCrypto`-backed execution materialization for real commitments, transaction-template validation, signature submission, and blame material, plus a gated real Electron Cash `4.4.3` interoperability smoke validator for local coordinator-backed proofing. A conservative public activation layer is now available through `OpalFusion.Client.Session`, while the runtime, transport, framing, protobuf, and execution internals remain intentionally hidden. The current pilot-supported live path is intentionally limited to compressed-key standard P2PKH participant inputs and matching Schnorr P2PKH unlocking scripts for local finalized inputs. The public pilot lane is `develop`; `main` remains intentionally behind it until the current P2PKH-only path is proven repeatedly against a real coordinator.

## Current Public Surface

- `OpalFusion.Client.Configuration`, `OpalFusion.Client.State`, `OpalFusion.Client.Error`, `OpalFusion.Client.Session`, and `OpalFusion.Client.StateObserver`
- `OpalFusion.Round.Identifier`, `OpalFusion.Round.Phase`, and `OpalFusion.Round.State`
- `OpalFusion.Transport.CovertChannelConfiguration` and `OpalFusion.Transport.TorSocks5Configuration`
- `OpalFusion.Host.ParticipantInput`, `OpalFusion.Host.ParticipantOutput`, and `OpalFusion.Host.ParticipantReservation`
- `OpalFusion.Host.ParticipantReservationSource`, `OpalFusion.Host.TransactionAssembler`, and `OpalFusion.Host.EventObserver`
- public model namespaces for `OpalFusion.Commitment`, `OpalFusion.BlindSignature`, and `OpalFusion.Blame`

## Requirements

- Swift tools version: `6.2`
- Platforms: `macOS 26`
- Current live transport support, including the Tor SOCKS5 covert path, is macOS-only in this package.

## Quick Start

Build the package:

```bash
swift build
```

The package now exposes a conservative public session wrapper over the internal runtime:

```swift
import OpalFusion

let covertChannel = OpalFusion.Transport.CovertChannelConfiguration(
    entryPath: "/fusion",
    maxPayloadBytes: 32_768,
    requestTimeoutMilliseconds: 15_000
)

let configuration = OpalFusion.Client.Configuration(
    coordinatorHost: "fusion.example.org",
    coordinatorPort: 8787,
    covertChannel: covertChannel
)

let joinPools = OpalFusion.ProtocolModel.JoinPools(
    tiers: [10_000],
    tags: []
)

let session = OpalFusion.Client.Session(
    configuration: configuration,
    joinPools: joinPools,
    participantReservationSource: participantReservationSource,
    transactionAssembler: transactionAssembler,
    stateObserver: stateObserver
)

await session.start()
let snapshot = await session.snapshot()
```

Current live-path expectations:

- Each reserved input must include the compressed public key that matches its standard P2PKH locking script.
- The host-finalized transaction must preserve a standard Schnorr P2PKH unlocking script for each local input.
- Broader BCH script-type support is intentionally deferred; unsupported forms currently surface through the coarse `.notImplemented` client error.

Real Electron Cash proofing:

- The gated smoke now uses a session-level success rule: intermediate blame or restart rounds are acceptable as long as one round in the session completes successfully before timeout.
- Treat `develop` as the public pilot lane for this proofing work; `main` remains blocked on repeated coordinator-backed confidence, not missing runtime architecture.
- Export the required `OPALFUSION_EC_*` variables for your funded test reservation, then run `./scripts/run-electron-cash-interop-smoke.sh`.
- Run `./scripts/run-electron-cash-interop-smoke.sh 3` for the current pilot-confidence target of three consecutive successful session-level proofs.

This keeps the public surface small while leaving the runtime, transport, framing, protobuf, and execution machinery internal.
