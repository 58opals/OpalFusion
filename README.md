# Opal Fusion

Opal Fusion is the BCH CashFusion protocol and runtime package in the Opal stack. It exists so CashFusion-specific coordinator connectivity, covert transport, round-state handling, commitments, blind-signature flow, and blame logic can live in one focused Swift package instead of leaking into app-layer packages, crypto helpers, or product code.

## Audience

Use Opal Fusion when you are building Swift BCH infrastructure that needs a dedicated CashFusion layer with explicit host integration seams. The primary downstream consumer is `OpalBase`, which can expose CashFusion support to wallet or service products without pulling protocol internals into app-layer code.

## Stack Position

- Above `OpalCrypto`, which owns reusable BCH cryptographic primitives.
- Below `OpalBase`, which owns app-facing wallet, policy, and orchestration behavior.
- Separate from `SwiftFulcrum`, which owns Fulcrum transport responsibilities.
- Separate from product layers such as Opal Wallet.

## Boundaries And Non-Goals

- Own CashFusion protocol and runtime boundaries, including coordinator-facing flow, round-state modeling, host integration seams, and future interop-specific transport details.
- Do not own wallet UI, product-shell behavior, or end-user policy surfaces.
- Do not own generic BCH app orchestration that belongs in `OpalBase`.
- Do not own generic cryptography that belongs in `OpalCrypto`.
- Do not own Fulcrum transport responsibilities that belong in `SwiftFulcrum`.
- Do not create a dependency cycle back into `OpalBase`.

## Current Maturity

Opal Fusion is currently a boundary-first scaffold. The package defines the public namespace and the main host, transport, client, and round-state seams, but full coordinator interoperability, live round orchestration, protocol message modeling, and `OpalCrypto`-backed cryptographic execution are not implemented yet.

## Requirements

- Swift tools version: `6.2`
- Platforms:
  - `macOS 26`
  - `iOS 26`
  - `watchOS 26`
  - `tvOS 26`
  - `visionOS 26`

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

## Key Responsibilities

- Coordinator-facing CashFusion runtime flow and round progression.
- Covert-channel and optional Tor SOCKS5 configuration needed for CashFusion interoperability.
- Host-side boundaries for reserved inputs, transaction finalization, and event observation.
- Dedicated namespaces for commitments, blind signatures, and blame handling as the protocol surface fills in.

## Current Public Surface

- `OpalFusion.Client.Configuration`, `OpalFusion.Client.State`, and `OpalFusion.Client.Error` describe coordinator configuration, coarse client state, and current scaffold errors.
- `OpalFusion.Round.Identifier`, `OpalFusion.Round.Phase`, and `OpalFusion.Round.State` model round identity and progress snapshots.
- `OpalFusion.Transport.CovertChannelConfiguration` and `OpalFusion.Transport.TorSocks5Configuration` define the current transport configuration surface.
- `OpalFusion.Host.ParticipantInputProvider`, `OpalFusion.Host.TransactionAssembler`, and `OpalFusion.Host.EventObserver` define the host integration boundary, supported by `ParticipantInput`, `TransactionFinalizationProposal`, `FinalizedTransaction`, and `Event`.
- `OpalFusion.Commitment`, `OpalFusion.BlindSignature`, and `OpalFusion.Blame` are reserved namespaces for the dedicated protocol surfaces that will expand here rather than in downstream packages.

## Integration Expectations

- Upstream: `OpalCrypto` is the intended home for reusable BCH cryptographic primitives once concrete CashFusion execution wiring lands here.
- Downstream: `OpalBase` should consume Opal Fusion through the host boundary so CashFusion support can appear as an app-layer capability without a package cycle.
- Product layers: Opal Wallet and other BCH products should depend on CashFusion through `OpalBase`, not by embedding product policy or UI behavior in this package.
- Networking: keep Fulcrum-specific responsibilities in `SwiftFulcrum`; Opal Fusion should stay focused on CashFusion-specific coordinator and runtime concerns.

## Current Focus

The current repo-owned direction is to prove the first real public-server CashFusion interop slice while keeping the host boundary narrow and reusable enough for `OpalBase` to integrate cleanly.
