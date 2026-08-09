# Opal Fusion

Status: the CashFusion engine is a pilot on `develop`; Mosaic remains non-live. Its deterministic foundations include the attempt and runtime reducers, an internal ordered host coordinator, the chipnet-only Opal v0 conformance contracts, and the additive `Mosaic/0-opal-mainnet-alpha.3` contract profile with a sealed admission ledger and paired internal runtime bridge. Mainnet-alpha freezes role hashing, complete manifests, PlayerCommit, deterministic allocation of BCH's fixed ten-satoshi transaction overhead, grouped Pedersen balance validation, per-contributor authorization-response sets, the complete contributor acknowledgement set, typed aggregate reassembly, authenticated control admission, BCH signature sets, and exact complete-transaction assembly. The ledger binds admitted material through transcript agreement to one attempt and generation, derives a zero sequence epoch for every roster sender, enforces per-sender replay and immediate externally validated phase synchronization, requires complete PlayerCommit and response-set collection with contributor-local blind-response finalization, restricts anonymous intake to the conductor with one-time sender and mailbox identities, requires exact acknowledgement-set publication, and absorbs terminal input. The paired bridge advances the same validated local attempt through transcript agreement, requires an externally sealed reservation-publication validation carrying the exact reference and PlayerCommit binding before contributor wallet advancement, and verifies that the conductor's commitment set contains every local commitment. It does not convert the acknowledgement set into BCH-signing eligibility, and the mainnet runtime driver remains disabled. Separate profile-contract tests prove previous-output-backed transaction assembly; the coordinator proves in-process release, signing, exact-commit, cancellation, and recovery-required ordering against injected seams. Production salt/opening and privacy-preserving component linkage, lease-material construction, live lease and PlayerCommit provenance validation, previous-output resolution in executable runtime composition, anonymous BCH-signature authorization, production mailbox ingress, concrete Tor networking, durable recovery, independent review, and all mainnet spending or broadcast remain unavailable. The remaining CashFusion proof gates are tracked in [CashFusion Native Swift Support Statement](docs/cashfusion-native-support-statement.md).

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
- Current live CashFusion transport support, including the Tor SOCKS5 covert path, is macOS-only in this package. Mosaic has strict relay framing and an injected Tor-only WebSocket capability boundary, but no concrete live connection implementation.

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

The package includes the protocol-neutral facade and internal Mosaic attempt, transcript, authorization, relay-validation, ordered runtime, and host-coordination foundations. The host coordinator drains reducer effects through the exact public Mosaic wallet contract, releases a late reservation before signing, refuses automatic release after signing may have begun, commits only an injected validated complete transaction, and exposes recovery-required outcomes when disposition is ambiguous. It also includes the additive `Mosaic/0-opal-mainnet-alpha.3` deterministic contract profile: mainnet identity, exact final-size fee rules, canonical 6–8-contributor fixed-overhead shares, grouped Pedersen balance validation, role hashing, complete manifest, PlayerCommit, per-contributor authorization-response sets, a complete contributor acknowledgement set, strict typed aggregate reassembly, authenticated control admission, signature-set validation, and exact complete-transaction assembly with golden vectors. The public reservation and signing contracts carry the exact roster-derived excess share instead of only a range. Their legacy initializers remain source-compatible for singleton ranges and reject ambiguous ranges. Its internal admission ledger binds admitted documents, commitment and component sets, and anonymous components to one attempt, generation, roster, round, local role, a roster-derived zero sequence epoch, and an immediate externally validated phase successor. A paired internal mainnet-alpha runtime session translates those sealed facts into the same validated local attempt through transcript agreement; contributors additionally require an externally validated attempt-, generation-, material-, manifest-, reservation-reference-, and PlayerCommit-bound publication token and exact local commitment inclusion before leaving the grouped-commitment phase. The complete acknowledgement set remains admission-only and cannot produce BCH-signing eligibility. The internal runtime driver still accepts only `.opalV0`; mainnet-alpha rejects legacy aggregate host markers and has no public session, production reservation-provenance validator, production mailbox ingress, production host composition, durable recovery driver, transport route, or broadcast path. Salt/opening and privacy-preserving component linkage, production lease-material construction, previous-output resolution in executable runtime composition, anonymous BCH-signature authorization, concrete Tor integration, and independent review remain release blockers, so the profile is not a live Mosaic or mainnet-readiness claim. `OpalFusion.Client.Session` remains the only live entry point and runs CashFusion.

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
swift test
./scripts/run-validation-loop.sh codec
```

The fast local suite is the normal development loop. Live Electron Cash coordinator proofing is opt-in, environment-gated, registration-guarded, and should be treated as a slow confidence gate:

```bash
./scripts/run-electron-cash-interop-smoke.sh 3
```

See [Validation Guide](docs/validation.md) for focused filters, validation-loop modes, and slow proof gates.

## Changelog

Package changes are tracked in [CHANGELOG.md](CHANGELOG.md).

## License

Opal Fusion is licensed under the Apache License 2.0. See [LICENSE](LICENSE).
