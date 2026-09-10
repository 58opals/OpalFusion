# Opal Fusion

Opal Fusion is the collaborative-transaction protocol package for the Opal Bitcoin Cash stack. It contains the coordinator-based CashFusion compatibility engine and the non-live Mosaic protocol foundation. OpalBase and integrating applications retain wallet policy, funds, signing authority, persistence, broadcast, and user experience.

CashFusion is a pilot on `develop`, with `OpalFusion.Client.Session` as its live entry point. Mosaic provides deterministic protocol contracts, authenticated admission and replay, role-specific execution, mailbox bootstrap, and injected transport and recovery seams. Its generic mainnet runtime driver remains disabled, and `OpalFusion.Session` has no public constructor. Package tests do not establish a concrete Tor deployment, application durability, anonymity, or production readiness.

The frozen [mainnet-alpha profile](docs/mosaic-mainnet-alpha-profile.md), [transport bootstrap contract](docs/mosaic-private-alpha-transport-bootstrap.md), and [security model](docs/mosaic-security-model.md) describe Mosaic's capabilities, application obligations, and remaining proof requirements. The [parser evidence](docs/mosaic-g4-parser-mutation-evidence-2026-08-23.md) records bounded deterministic package coverage and its limits. CashFusion's remaining proof requirements are in the [support statement](docs/cashfusion-native-support-statement.md).

An internal control-batch publisher validates each bridge-minted batch against its exact bootstrap-derived context, complete roster recipient allocation, and manifest relay selection. It obtains a complete roster-sized route allocation keyed only by recipient event identities before publication, rejects connection reuse across all recipient groups, delegates each gift wrap to one exact-three-route/two-accepted-ACK publisher, and returns only after every delegated publisher has closed; it owns no endpoint provisioning or endpoint-to-capability proof, concrete Tor circuit, persistence, reconnect, durable acknowledgement or delivery state, retry, or semantic loopback admission.

An internal anonymous-batch publisher accepts only a bridge-minted, material-bound component or local-signature batch. It preflights the complete recipient-only route allocation, rejects connection reuse across the batch, requires a separate injected publication permit for each recipient immediately before relay delegation, and returns only after every exact-three-route/two-accepted-ACK publisher has closed. The permit and route providers remain authoritative; this boundary defines no timing policy, endpoint or Tor provisioning, persistence, retry, semantic loopback, or live support.

An internal contributor transport bridge binds the reservation coordinator's ordered PlayerCommit, anonymous-component, pre-sign-acknowledgement, and local-signature callbacks to the control and anonymous publication paths for one exact lease-backed material value. Its exact attempt transport owner is the bridge's sole gateway to validated control recipients, the local inbound capability, and outbound control and anonymous route access; the injected provisioner remains authoritative for raw connections and isolation leases. The bridge has no raw route-provider construction path and separates a nonblocking stop request from the lifecycle owner's termination wait so active work drains before terminal state. It does not start or supervise fan-in, automatically connect source loss to that stop boundary, allocate keys or routes, choose expiry values, perform semantic loopback, persist attempt state, or enable a live session.

## Source Of Truth

- [Opal Fusion Specification](docs/opal-fusion-specification.md): normative product hierarchy, shared facade, engine selection, fallback, and host boundaries.
- [Mosaic Protocol Specification](docs/mosaic-protocol-specification.md): draft peer-conducted protocol, roles, phases, manifest, transcript, transport contract, and release gates.
- [Mosaic Security Model](docs/mosaic-security-model.md): Mosaic threats, trust assumptions, safe claims, privacy limits, and review gates.
- [Mosaic G4 Parser-Mutation Evidence](docs/mosaic-g4-parser-mutation-evidence-2026-08-23.md): exact test-only revision, first-party mutation and positive-variant design, focused results, production-tree parity, package parser accounting, and non-proofs.
- [Mosaic G4 Parser-Root Registry](docs/mosaic-g4-parser-root-registry-2026-08-23.md): machine-checked 52-file low-level surface, nine-parent transport composite map, consumer boundary, and future-drift rule.
- [Mosaic Private-Alpha Transport Bootstrap.1](docs/mosaic-private-alpha-transport-bootstrap.md): package-owned authenticated mailbox distribution, wrapper/ACK recovery, replay, and concrete application obligations.
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

- Swift tools version: `6.4`
- Platforms: `macOS 27`
- Xcode's Metal Toolchain component, required by the current OpalCrypto build plugin.
- Current live CashFusion transport support, including the Tor SOCKS5 covert path, is macOS-only in this package. Mosaic has strict relay framing, a frozen internal post-manifest NIP-59 event mapping, blind-authorized mailbox bootstrap, attempt-scoped recipient routing, authenticated runtime ingress, a byte-stable exact-three-relay/two-durable-acknowledgement publisher, and a bounded reconnectable fan-in whose externally provisioned mailbox groups each use three injected Tor-only WebSocket capabilities; it has no concrete Mosaic Tor connection, application durable transport-secret lifecycle, supervised live session, or public live transport implementation.

The internal roster-wide control-batch boundary preflights route groups by recipient event identity and drains every per-recipient one-shot publisher; concrete Tor and route provisioning remain external.

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

The control-batch publisher accepts only the bridge's exact attempt, generation, material, manifest, sender, and recipient binding, requests all recipient routes without disclosing control identities, and completes only after every per-recipient three-route/two-ACK operation has closed.

The anonymous-batch publisher preserves the bridge's sealed purpose and material binding, requests all routes using only recipient event identities, and withholds each sealed wrap until its injected per-recipient publication permit succeeds. The route provider must supply fresh anonymous capabilities; in-process connection uniqueness does not prove Tor-circuit isolation or timing privacy.

The package includes the protocol-neutral facade and internal Mosaic attempt, transcript, authorization, relay-validation, ordered-runtime, and host-coordination foundations. Its additive `Mosaic/0-opal-mainnet-alpha.4` profile supplies deterministic mainnet contract evidence for 6–8 contributors, exact 23-slot lease material, grouped Pedersen balance, purpose-separated authorization, strict authenticated admission, and conductor collection of component and BCH-signature mailbox deliveries. The profile explicitly accepts that authorization does not prove a disclosed component belongs to a contributor-tagged grouped commitment; tests pin one valid off-commitment vector and make no privacy or accountability claim. The internal alpha.4 runtime consumes complete acknowledgement, signature-set, and complete-transaction facts through previous-output-backed validation. Its contributor executor reaches byte-exact host commit, and its conductor executor issues authorization, admits anonymous material, validates signatures, and assembles the exact transaction through injected seams. Post-manifest ingress selects one immutable recipient capability before its driver authenticates and decrypts the gift wrap. Control and anonymous publication bridges seal exact context and material into complete recipient batches; one-shot publishers require two accepted acknowledgements across three injected Tor-only routes. Multi-recipient fan-in starts three globally distinct subscriptions per mailbox, preserves source order through a bounded serial queue, and terminates on source loss. One injected admission journal records only semantically accepted control digest/sequence and anonymous wrapper/mailbox facts before effects, merging relay copies to one append and refusing partial restart state; persistence depends on the caller-supplied store. Bootstrap.1 authenticates the public mailbox assignment and consensus handoff without exporting recipient private keys. The generic `RuntimeSessionDriver` still accepts only `.opalV0`, `OpalFusion.Session` remains unconstructible, and no live transport or broadcast is selected. Application-owned key custody and encrypted persistence, live mailbox-route provisioning, full application runtime/coordinator crash composition, concrete Tor adapters, authoritative endpoint binding, explicit broadcast approval, and deployment review remain release gates. `OpalFusion.Client.Session` remains the only live entry point and runs CashFusion.

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

No arguments and `fast` run the same representative regression selection with a 60-second post-build budget. The wrapper builds test targets first, then includes discovery, process startup, and cold fixture preparation in that budget. It requires Python 3 and reports build time separately. A pass covers only the selected suites; run affected focused suites as well when changing a narrow layer.

Use `./scripts/run-validation-loop.sh all` explicitly for comprehensive deterministic validation. Its historical Debug runtime is approximately 97 minutes. It retains serialized cryptographic phases and a bounded concurrent pool; the fast-lane cutoff does not apply. Plain `swift test` is unchanged and can start the expensive suites together, so it is not the recommended comprehensive runner.

Documentation-only edits need relevant documentation checks. Cryptography, authentication, protocol bytes, shared cryptographic fixtures, dependency changes, and public candidate publication require comprehensive validation. See the [Validation Guide](docs/validation.md) for the complete change-to-lane matrix and exact fast selection.

Live Electron Cash coordinator proofing is separately opt-in, environment-gated, registration-guarded, and should be treated as a slow confidence gate:

```bash
./scripts/run-electron-cash-interop-smoke.sh 3
```

See [Validation Guide](docs/validation.md) for focused filters, validation-loop modes, and slow proof gates.

## Changelog

Package changes are tracked in [CHANGELOG.md](CHANGELOG.md).

## License

Opal Fusion is licensed under the Apache License 2.0. See [LICENSE](LICENSE).
