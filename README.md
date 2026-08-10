# Opal Fusion

Status: the CashFusion engine is a pilot on `develop`; Mosaic remains non-live. Its deterministic foundations include the attempt and runtime reducers, an internal ordered host coordinator, the chipnet-only Opal v0 conformance contracts, and the additive `Mosaic/0-opal-mainnet-alpha.4` contract profile. Alpha.4 freezes role hashing, complete manifests, exact 23-slot contributor-local material, salt and Pedersen openings, deterministic allocation of BCH's fixed ten-satoshi transaction overhead, two component-bound blind-authorization purposes under distinct attempt keys, dual-vector response sets, complete contributor acknowledgements, typed aggregate reassembly, authenticated control admission, paired anonymous mailbox sequences, canonical signature sets, and exact complete-transaction assembly. Its sealed admission ledger and role-specific executors enforce attempt, generation, material, roster, phase, replay, wallet disposition, previous-output, signing, and exact-commit boundaries against injected non-network seams. The post-manifest `nostr-tor/0-opal-mainnet-alpha.5` mapping now fixes an unsigned kind-78 rumor namespace, exact 8,192-byte padded application content, regular kind-1059 gift wraps, sender and recipient authority, cover-timestamp bounds, signed-wrapper replay identity, resource ceilings, and a three-relay/two-acceptance contract. An internal ingress forwards those events to a driver-owned authentication gate before one freshly selected role executor receives them. This is not a concrete relay or Tor implementation: recipient-key storage, relay endpoint selection, publication, fan-in, acknowledgements, reconnect, and circuit isolation remain external. The generic transport-facing `RuntimeSessionDriver` remains disabled for mainnet-alpha and no public Mosaic session exists. Production stateful lease-to-material ownership, cross-attempt secret persistence and erasure, authoritative app composition, durable crash recovery, independent review, real mainnet spending, and broadcast remain unavailable. The remaining CashFusion proof gates are tracked in [CashFusion Native Swift Support Statement](docs/cashfusion-native-support-statement.md).

Opal Fusion is the collaborative-transaction protocol package for the Opal Bitcoin Cash stack. It is the umbrella for the coordinator-based CashFusion compatibility engine and the peer-conducted Mosaic protocol, while OpalBase and Opal Wallet retain wallet policy, funds, signing authority, persistence, broadcast, and user experience.

## Source Of Truth

- [Opal Fusion Specification](docs/opal-fusion-specification.md): normative product hierarchy, shared facade, engine selection, fallback, and host boundaries.
- [Mosaic Protocol Specification](docs/mosaic-protocol-specification.md): draft peer-conducted protocol, roles, phases, manifest, transcript, transport contract, and release gates.
- [Mosaic Security Model](docs/mosaic-security-model.md): Mosaic threats, trust assumptions, safe claims, privacy limits, and review gates.
- [CashFusion Implementation Spec](docs/cashfusion-implementation-spec.md): normative Electron Cash `4.4.3` CashFusion behavior, round lifecycle, timing, and host seams.
- [CashFusion Official Protocol Matrix](docs/cashfusion-official-protocol-matrix.md): row-level implementation status and test evidence against the pinned Electron Cash baseline.
- [CashFusion Native Swift Support Statement](docs/cashfusion-native-support-statement.md): current public support claim, intentional exclusions, and remaining proof gates.
- [Integration Guide](docs/integration-guide.md): how app and OpalBase layers should wire OpalFusion.
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

- Swift tools version: `6.2`
- Platforms: `macOS 26`
- Xcode's Metal Toolchain component, required by the current OpalCrypto build plugin.
- Current live CashFusion transport support, including the Tor SOCKS5 covert path, is macOS-only in this package. Mosaic has strict relay framing, a frozen internal post-manifest NIP-59 event mapping and authenticated runtime ingress, and an injected Tor-only WebSocket capability boundary, but no concrete relay fan-in/publication or live Tor connection implementation.

## Installation

For public review of the current pilot surface, use the public `develop` branch or a specific public revision:

```swift
dependencies: [
    .package(url: "https://github.com/58opals/OpalFusion.git", branch: "develop")
]
```

Do not treat `develop` as a SemVer release. The current pilot is intentionally narrow and remains blocked on repeated coordinator-backed confidence plus reviewed pinned transcript replay before a complete support claim.

## 5-Minute CashFusion Pilot Integration

OpalFusion exposes a conservative public `OpalFusion.Client.Session` wrapper over the internal runtime. The app or OpalBase layer supplies coordinator configuration, join pools, participant reservation material, transaction finalization, and observers.

```swift
import OpalFusion

let covertChannel = OpalFusion.Transport.CovertChannelConfiguration(
    entryPath: "/fusion",
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

The package includes the protocol-neutral facade and internal Mosaic attempt, transcript, authorization, relay-validation, ordered-runtime, and host-coordination foundations. Its additive `Mosaic/0-opal-mainnet-alpha.4` profile supplies deterministic mainnet contract evidence for 6–8 contributors, exact 23-slot lease material, grouped Pedersen balance, two purpose-separated authorization vectors, response finalization bound to one attempt/generation/material, strict authenticated admission, and conductor collection of component and BCH-signature mailbox deliveries. The profile explicitly accepts that authorization does not prove a disclosed component belongs to a contributor-tagged grouped commitment; tests pin one valid off-commitment vector and make no privacy or accountability claim. The internal alpha.4 runtime consumes the complete acknowledgement, signature-set, and complete-transaction facts through exact previous-output-backed validation. Its contributor executor invokes the refined host contract through byte-exact commit, and its conductor executor deterministically issues both authorization vectors, hands each locally constructed aggregate to an injected publisher, advances only after its later authenticated admission, verifies anonymous signatures against resolved previous outputs, and assembles the exact complete transaction. The post-manifest lifecycle ingress forwards signed gift wraps and recipient capabilities to an internal `PostManifestRuntimeDriver`, which derives the exact bootstrap context, authenticates and decrypts each event, privately routes the resulting typed delivery, and selects the roster-derived role without owning a live network task. The generic `RuntimeSessionDriver` still accepts only `.opalV0`, `OpalFusion.Session` remains unconstructible, and no live transport or broadcast is selected. Production stateful material ownership, app-authoritative previous-output and host composition, authenticated mailbox/Tor adapters, durable recovery, explicit broadcast approval, and deployment review remain release gates. `OpalFusion.Client.Session` remains the only live entry point and runs CashFusion.

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
- Checking normative CashFusion behavior: [CashFusion Implementation Spec](docs/cashfusion-implementation-spec.md)
- Checking row-level conformance and remaining gaps: [CashFusion Official Protocol Matrix](docs/cashfusion-official-protocol-matrix.md)
- Checking the current support claim: [CashFusion Native Swift Support Statement](docs/cashfusion-native-support-statement.md)
- Preparing env-gated live proofing: [Electron Cash Live Pilot Confidence](docs/cashfusion-live-pilot-confidence.md)
- Preparing reviewed transcript fixtures: [Electron Cash Transcript Capture](docs/cashfusion-transcript-capture.md)

## Validation

Default local validation:

```bash
swift build
./scripts/run-validation-loop.sh all
./scripts/run-validation-loop.sh codec
```

The validation wrapper serializes the Security.framework-backed Mosaic authorization suites so the full local run does not exhaust transient RSA key generation. Use raw `swift test --filter <suite>` for focused work. Live Electron Cash coordinator proofing is opt-in, environment-gated, registration-guarded, and should be treated as a slow confidence gate:

```bash
./scripts/run-electron-cash-interop-smoke.sh 3
```

See [Validation Guide](docs/validation.md) for focused filters, validation-loop modes, and slow proof gates.

## Changelog

Package changes are tracked in [CHANGELOG.md](CHANGELOG.md).

## License

Opal Fusion is licensed under the Apache License 2.0. See [LICENSE](LICENSE).
