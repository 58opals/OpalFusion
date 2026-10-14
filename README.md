# Opal Fusion

Opal Fusion is the collaborative-transaction protocol package for the Opal Bitcoin Cash stack. It contains the coordinator-based CashFusion compatibility engine and the non-live Mosaic protocol foundation. OpalBase and integrating applications retain wallet policy, funds, signing authority, persistence, broadcast, and user experience.

CashFusion is a pilot on `develop`, with `OpalFusion.Client.Session` as its live entry point. Mosaic provides deterministic protocol contracts, authenticated admission and replay, role-specific execution, mailbox bootstrap, and injected transport and recovery seams. Its generic mainnet runtime driver remains disabled, and `OpalFusion.Session` has no public constructor. Package tests do not establish a concrete Tor deployment, application durability, anonymity, or production readiness.

The frozen [mainnet-alpha profile](docs/mosaic-mainnet-alpha-profile.md), [transport bootstrap contract](docs/mosaic-private-alpha-transport-bootstrap.md), and [security model](docs/mosaic-security-model.md) describe Mosaic's capabilities, application obligations, and remaining proof requirements. The [parser evidence](docs/mosaic-g4-parser-mutation-evidence-2026-08-23.md) records bounded deterministic package coverage and its limits. CashFusion's remaining implementation and proof gates are in the [support statement](docs/cashfusion-native-support-statement.md).

## Source Of Truth

- [Opal Fusion Specification](docs/opal-fusion-specification.md): normative product hierarchy, shared facade, engine selection, fallback, and host boundaries.
- [Mosaic Protocol Specification](docs/mosaic-protocol-specification.md): draft peer-conducted protocol, roles, phases, manifest, transcript, transport contract, and release gates.
- [Mosaic Security Model](docs/mosaic-security-model.md): Mosaic threats, trust assumptions, safe claims, privacy limits, and review gates.
- [Mosaic G4 Parser-Mutation Evidence](docs/mosaic-g4-parser-mutation-evidence-2026-08-23.md): exact test-only revision, first-party mutation and positive-variant design, focused results, production-tree parity, package parser accounting, and non-proofs.
- [Mosaic G4 Parser-Root Registry](docs/mosaic-g4-parser-root-registry-2026-08-23.md): machine-checked 52-file low-level surface, nine-parent transport composite map, consumer boundary, and future-drift rule.
- [Mosaic Private-Alpha Transport Bootstrap.1](docs/mosaic-private-alpha-transport-bootstrap.md): package-owned authenticated mailbox distribution, wrapper/ACK recovery, replay, and concrete application obligations.
- [CashFusion Implementation Spec](docs/cashfusion-implementation-spec.md): normative Electron Cash `4.4.3` CashFusion behavior, round lifecycle, timing, and host seams.
- [CashFusion Official Protocol Matrix](docs/cashfusion-official-protocol-matrix.md): row-level implementation status and test evidence against the pinned Electron Cash baseline.
- [CashFusion Native Swift Support Statement](docs/cashfusion-native-support-statement.md): current public support claim, intentional exclusions, and remaining implementation and proof gates.
- [Integration Guide](docs/integration-guide.md): how app and OpalBase layers should wire OpalFusion.
- [Local Mosaic Integration](docs/mosaic-local-integration.md): one-owner lifecycle, delayed expiry, wallet recovery obligations and public-fixture commands.
- [Validation Guide](docs/validation.md): fast local loops, focused protocol/runtime filters, live-smoke caveats, and transcript replay direction.
- [Architecture Guide](docs/architecture.md): compact maintainer map of public API, runtime, transport, wire, execution, host, and diagnostics layers.

## Stack Position

- Above `OpalCrypto`, which owns reusable Bitcoin Cash cryptographic primitives.
- Below `OpalBase`, which owns app-facing wallet, policy, orchestration, persistence, and product-facing integration.
- Separate from `SwiftFulcrum`, which owns Fulcrum transport responsibilities.
- Separate from product layers such as Opal Wallet.

## Boundaries

- Own CashFusion and Mosaic protocol execution, engine-specific transport behavior, shared lifecycle contracts, privacy-safe diagnostics, and host integration seams.
- Keep the CashFusion fixed coordinator implementation outside this package; the eventual Mosaic engine may let a wallet process act as the ephemeral conductor for one attempt.
- Do not own wallet UI, product-shell behavior, end-user fusion policy, transaction broadcast, or wallet persistence.
- Do not own generic Bitcoin Cash app orchestration that belongs in `OpalBase`.
- Do not own reusable cryptography that belongs in `OpalCrypto`.
- Do not own Fulcrum transport responsibilities that belong in `SwiftFulcrum`.

## Requirements

- Swift tools version: `6.4`
- Platforms: `macOS 27`
- Xcode's Metal Toolchain component, required by the current OpalCrypto build plugin.
- Live CashFusion transport, including the Tor SOCKS5 covert path, is macOS-only. Mosaic transport remains injected and non-live; see [Architecture](docs/architecture.md) for the publisher, routing, lifecycle, and application-owned durability boundaries.

## Installation

For public review of the current pilot surface, use the public `develop` branch or a specific public revision:

```swift
dependencies: [
    .package(url: "https://github.com/58opals/OpalFusion.git", branch: "develop")
]
```

Do not treat `develop` as a SemVer release. The current pilot is intentionally narrow; the [support statement](docs/cashfusion-native-support-statement.md) owns the remaining implementation and proof gates that must close before a complete support claim.

The `OpalFusion` product preserves the existing umbrella import, including the Mosaic private-alpha SPI, and compiles both engines. A CashFusion-only consumer can select `.product(name: "CashFusionEngine", package: "OpalFusion")` and `import CashFusionEngine`; the same `OpalFusion.Client.Session` namespace is available without a Mosaic dependency. `MosaicEngine` is an independent, deferred product. The shared `OpalFusionCore` contains common host values and package-only BCH helpers. Source consumers must rebuild after this module split.

## 5-Minute CashFusion Pilot Integration

OpalFusion exposes a conservative public `OpalFusion.Client.Session` wrapper over the internal runtime. The app or OpalBase layer supplies coordinator configuration, join pools, participant reservation material, transaction finalization, and observers.

```swift
import OpalFusion

let covertChannel = OpalFusion.Transport.CovertChannelConfiguration(
    entryPath: "/fusion", // Legacy compatibility; ignored by framed covert sockets.
    maxPayloadBytes: 32_768,
    requestTimeoutMilliseconds: 15_000
)

let configuration = OpalFusion.Client.Configuration(
    coordinatorHost: "coordinator.example.invalid",
    coordinatorPort: 8787,
    coordinatorRequiresTLS: true,
    covertChannel: covertChannel
)

let joinPools = OpalFusion.ProtocolModel.JoinPools(
    tiers: [10_000],
    tags: []
)

let optionalGenesisHash: [UInt8]? = nil

let session = OpalFusion.Client.Session(
    configuration: configuration,
    genesisHash: optionalGenesisHash,
    joinPools: joinPools,
    hostParticipantReservationSource: hostParticipantReservationSource,
    hostTransactionAssembler: hostTransactionAssembler,
    eventObserver: eventObserver,
    stateObserver: stateObserver
)

await session.start()
let snapshot = await session.currentSnapshot
```

See [Integration Guide](docs/integration-guide.md) for host callback responsibilities, privacy boundaries, and supported participant material.

## Protocol-Neutral API Scaffold

The shared facade models engine selection and pre-reservation fallback. `OpalFusion.Session` has no public constructor or live runtime methods; the configuration below describes a planned mode, not an executable Mosaic session. `OpalFusion.Client.Session` remains the CashFusion entry point.

The frozen mainnet-alpha.4 profile has deterministic contributor/conductor execution and recovery contracts over injected seams. Its accepted off-commitment vector documents an accountability limitation; package tests do not establish component membership, anonymity, live Tor isolation, or production readiness. The [architecture guide](docs/architecture.md), [mainnet profile](docs/mosaic-mainnet-alpha-profile.md), and [security model](docs/mosaic-security-model.md) own the detailed execution boundaries and remaining application/deployment gates.

```swift
let cashFusion = OpalFusion.CashFusion.Configuration(
    coordinator: configuration,
    genesisHash: optionalGenesisHash,
    joinPools: joinPools
)

let mosaic = OpalFusion.Mosaic.Configuration()

let automatic = try OpalFusion.Session.AutomaticConfiguration(
    candidates: [.mosaic(mosaic), .cashFusion(cashFusion)],
    fallbackPolicy: .beforeReservationOnly
)

let plannedMode = OpalFusion.Session.Mode.automatic(automatic)
```

Candidate order is supplied by OpalBase. Cross-engine fallback is permitted only before any wallet reservation; a failed active round becomes a new session attempt rather than an in-place protocol switch.

## Current CashFusion Pilot Envelope

- The supported live path is intentionally limited to compressed-key standard P2PKH participant inputs.
- Each reserved input must include the compressed public key that matches its standard P2PKH locking script.
- The host-finalized transaction must preserve a standard Schnorr P2PKH unlocking script for each local input.
- Broader BCH script support remains deferred and currently surfaces through `.notImplemented` when the unsupported path is reached.
- Coordinator defaults, retry cadence, wallet policy, signing authority, persistence, and broadcast remain app-owned.

## Common Developer Paths

- Wiring OpalFusion into an app or OpalBase layer: [Integration Guide](docs/integration-guide.md)
- Choosing the right local verification loop: [Validation Guide](docs/validation.md)
- Understanding maintainers' package map: [Architecture Guide](docs/architecture.md)
- Checking the shared facade and engine-selection contract: [Opal Fusion Specification](docs/opal-fusion-specification.md)
- Reviewing the Mosaic design and its limits: [Mosaic Protocol Specification](docs/mosaic-protocol-specification.md) and [Mosaic Security Model](docs/mosaic-security-model.md)
- Reviewing the frozen non-live mainnet contract: [Mosaic Mainnet-Alpha Profile](docs/mosaic-mainnet-alpha-profile.md)
- Reviewing the separately versioned private discovery and deployment contract: [Mosaic Mainnet-Alpha Private-Deployment Profile](docs/mosaic-mainnet-alpha-private-deployment.md)
- Checking normative CashFusion behavior: [CashFusion Implementation Spec](docs/cashfusion-implementation-spec.md)
- Checking row-level conformance and remaining gaps: [CashFusion Official Protocol Matrix](docs/cashfusion-official-protocol-matrix.md)
- Checking the current support claim: [CashFusion Native Swift Support Statement](docs/cashfusion-native-support-statement.md)
- Preparing env-gated live proofing: [Electron Cash Live Pilot Confidence](docs/cashfusion-live-pilot-confidence.md)
- Preparing reviewed transcript fixtures: [Electron Cash Transcript Capture](docs/cashfusion-transcript-capture.md)

## Validation

Default local validation:

```bash
./scripts/run-validation-loop.sh
```

No arguments, `fast`, and `cashfusion-all` run every deterministic CashFusion test. The separate harness excludes Mosaic compilation and registration. Its build deadline is 300 seconds; discovery, process startup, and cold fixture preparation then share a 60-second budget. It requires Python 3 and reports both stages. Protocol timing constants remain unchanged.

Mosaic remains deferred: `mosaic-all` is explicit slow conformance/recovery validation, with a 7,200-second post-build deadline. `all` explicitly runs both harnesses. The historical combined Debug runtime was approximately 97 minutes. The Mosaic lane retains its serialized cryptographic phases and bounded concurrent pool.

Documentation-only edits need relevant documentation checks. Protocol and cryptographic changes require complete validation for their owning engine; shared core behavior, shared dependencies, and public candidate publication require both engines. Timeouts fail the owning check without retries, omitted cases, or altered protocol timing. See the [Validation Guide](docs/validation.md) for the change-to-lane matrix and exact selections.

Live Electron Cash coordinator proofing is separately opt-in, environment-gated, registration-guarded, and should be treated as a slow confidence gate:

```bash
./scripts/run-electron-cash-interop-smoke.sh 3
```

See [Validation Guide](docs/validation.md) for focused filters, validation-loop modes, and slow proof gates.

## Changelog

Package changes are tracked in [CHANGELOG.md](CHANGELOG.md).

## License

Opal Fusion is licensed under the Apache License 2.0. See [LICENSE](LICENSE).
