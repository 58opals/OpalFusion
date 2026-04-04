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

Opal Fusion now has broad typed protocol and domain modeling, pinned transport/timing baseline values, an internal round engine, and internal primary-channel framing/protobuf/runtime foundations in place. The package still does not implement live coordinator interoperability, real socket transport, covert runtime execution, or `OpalCrypto`-backed execution yet.

## Current Public Surface

- `OpalFusion.Client.Configuration`, `OpalFusion.Client.State`, and `OpalFusion.Client.Error`
- `OpalFusion.Round.Identifier`, `OpalFusion.Round.Phase`, and `OpalFusion.Round.State`
- `OpalFusion.Transport.CovertChannelConfiguration` and `OpalFusion.Transport.TorSocks5Configuration`
- `OpalFusion.Host.ParticipantInputProvider`, `OpalFusion.Host.TransactionAssembler`, and `OpalFusion.Host.EventObserver`
- reserved namespaces for `OpalFusion.Commitment`, `OpalFusion.BlindSignature`, and `OpalFusion.Blame`

## Requirements

- Swift tools version: `6.2`
- Platforms: `macOS 26`, `iOS 26`, `watchOS 26`, `tvOS 26`, `visionOS 26`

## Quick Start

Build the package:

```bash
swift build
```

The current scaffold is usable as a boundary package and type surface:

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

let round = OpalFusion.Round.State(
    identifier: .init(rawValue: "round-001"),
    phase: .connecting
)

let state = OpalFusion.Client.State(
    isConnected: false,
    round: round
)
```

This shows the current configuration and state-model surface. It does not start a live CashFusion session yet.
