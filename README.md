# Opal Fusion

Status: the CashFusion engine is a pilot on `develop`; Mosaic remains non-live. Its deterministic foundations include the attempt and runtime reducers, an internal ordered host coordinator, the chipnet-only Opal v0 conformance contracts, and the additive `Mosaic/0-opal-mainnet-alpha.4` contract profile. Alpha.4 freezes role hashing, complete manifests, exact 23-slot contributor-local material, salt and Pedersen openings, deterministic allocation of BCH's fixed ten-satoshi transaction overhead, two component-bound blind-authorization purposes under distinct attempt keys, dual-vector response sets, complete contributor acknowledgements, typed aggregate reassembly, authenticated control admission, paired anonymous mailbox sequences, canonical signature sets, and exact complete-transaction assembly. Its sealed admission ledger and role-specific executors enforce attempt, generation, material, roster, phase, replay, wallet disposition, previous-output, signing, and exact-commit boundaries against injected non-network seams. The post-manifest `nostr-tor/0-opal-mainnet-alpha.5` mapping fixes an unsigned kind-78 rumor namespace, exact 8,192-byte padded application content, regular kind-1059 gift wraps, sender and recipient authority, cover-timestamp bounds, signed-wrapper replay identity, resource ceilings, and a three-relay/two-acceptance contract. An internal ingress accepts only signed events, resolves their sole outer recipient identity against an immutable attempt-scoped recipient set, and supplies the matching key and sealed channel to the driver-owned authentication gate, which routes to one freshly selected role executor. A bootstrap-bound sender-global internal control-publication bridge accepts only the exact manifest, sealed reservation/transcript validations, or coordinator-minted conductor publications for its attempt, generation, and material, starts its local sender sequence at zero, reserves each complete aggregate fragment run before handoff, separately signs inner acknowledgements and outer control envelopes, creates one recipient-bound gift wrap for every roster peer, and advances only after the injected whole-batch acknowledgement boundary succeeds. A separate contributor-side anonymous-publication bridge accepts only the exact local material and coordinator-minted component or BCH-signature validation, uses distinct one-time sender identities for mailbox sequences zero and one, creates recipient-bound NIP-59 gift wraps, and terminalizes on order, cancellation, construction, or handoff ambiguity; route allocation, timing policy, durable state, and semantic loopback remain injected or external. A one-shot internal publisher attempts one byte-identical signed gift wrap over exactly three injected Tor-only routes whose opaque endpoints pass a manifest-relay-digest validation seam and returns only after two accepted NIP-01 acknowledgements. A separate bounded multi-recipient fan-in consumes one owner-provisioned role-complete mailbox allocation, requires exactly three globally distinct injected connections and subscription identifiers per group under one manifest relay selection, starts every group before consuming into one ingress and runtime authority, serializes signed EVENT copies through a bounded FIFO while preserving each route's source order, ignores EOSE and NOTICE, fails closed on source loss, and drains accepted input before terminal disposition. One opaque immutable claim token is required by fan-in, ingress, and the specialized driver, and transferred routes are closed before a failed construction returns. An injected attempt-bound journal records only semantically admitted control digest/sequence and anonymous wrapper/mailbox facts before coordinator effects, so identical relay copies create one append and append failure discards staged mutation; the boundary is durable only when the caller supplies a durable store. The separate `nostr-tor/0-opal-mosaic-private-alpha-bootstrap.1` package contract now authenticates an attempt-exclusive blind-authorization key, complete control-mailbox claims, blind-authorized anonymous registrations, conductor-local public-key assignments, an unlabeled bundle-commitment set, and complete roster acknowledgements; preserves exact wrappers across durable per-relay acknowledgement retry; enforces a caller-supplied attempt-wide event-identity reservation; and reconnects a bounded exact-three-source inbox from replay facts before minting the existing sole mailbox capability. No anonymous recipient private key crosses the protocol boundary. OpalFusion still does not own a concrete relay or Tor deployment: application key custody, encrypted transport-material persistence, endpoint policy, concrete Tor-only WebSockets, circuit isolation, timing policy, and lifecycle composition remain injected or external to this package. The generic transport-facing `RuntimeSessionDriver` remains disabled for mainnet-alpha and no public Mosaic session exists. Wallet's exact first-party G1 through G3 composition now supplies durable recovery, disabled-by-default concrete private transport, one supervised application session, exact host commit, and restart at explicit broadcast approval without directly depending on OpalFusion. G4 has locally verified the Wallet Release boundary, privacy-safe aggregate observability, and the absence of a reachable Mosaic user surface, has prepared a no-network recovery and disable runbook plus a manual-only exact-graph package matrix, and now has a bounded first-party deterministic mutation campaign for 54 parser seeds across five focused test bodies without changing production source or dependencies. Package CI execution, a reviewed parser-root registry, complete vectors, fuzz coverage for every parser, supported-environment evidence, signed runbook drills, independent review including UXC and safe claims, chain reconciliation, real spending, broadcast, canary execution, and residual-risk acceptance remain open or separately approval-gated. The remaining CashFusion proof gates are tracked in [CashFusion Native Swift Support Statement](docs/cashfusion-native-support-statement.md).

An internal control-batch publisher validates each bridge-minted batch against its exact bootstrap-derived context, complete roster recipient allocation, and manifest relay selection. It obtains a complete roster-sized route allocation keyed only by recipient event identities before publication, rejects connection reuse across all recipient groups, delegates each gift wrap to one exact-three-route/two-accepted-ACK publisher, and returns only after every delegated publisher has closed; it owns no endpoint provisioning or endpoint-to-capability proof, concrete Tor circuit, persistence, reconnect, durable acknowledgement or delivery state, retry, or semantic loopback admission.

An internal anonymous-batch publisher accepts only a bridge-minted, material-bound component or local-signature batch. It preflights the complete recipient-only route allocation, rejects connection reuse across the batch, requires a separate injected publication permit for each recipient immediately before relay delegation, and returns only after every exact-three-route/two-accepted-ACK publisher has closed. The permit and route providers remain authoritative; this boundary defines no timing policy, endpoint or Tor provisioning, persistence, retry, semantic loopback, or live support.

An internal contributor transport bridge binds the reservation coordinator's ordered PlayerCommit, anonymous-component, pre-sign-acknowledgement, and local-signature callbacks to the control and anonymous publication paths for one exact lease-backed material value. Its exact attempt transport owner is the bridge's sole gateway to validated control recipients, the local inbound capability, and outbound control and anonymous route access; the injected provisioner remains authoritative for raw connections and isolation leases. The bridge has no raw route-provider construction path and separates a nonblocking stop request from the lifecycle owner's termination wait so active work drains before terminal state. It does not start or supervise fan-in, automatically connect source loss to that stop boundary, allocate keys or routes, choose expiry values, perform semantic loopback, persist attempt state, or enable a live session.

Opal Fusion is the collaborative-transaction protocol package for the Opal Bitcoin Cash stack. It is the umbrella for the coordinator-based CashFusion compatibility engine and the peer-conducted Mosaic protocol, while OpalBase and Opal Wallet retain wallet policy, funds, signing authority, persistence, broadcast, and user experience.

## Source Of Truth

- [Opal Fusion Specification](docs/opal-fusion-specification.md): normative product hierarchy, shared facade, engine selection, fallback, and host boundaries.
- [Mosaic Protocol Specification](docs/mosaic-protocol-specification.md): draft peer-conducted protocol, roles, phases, manifest, transcript, transport contract, and release gates.
- [Mosaic Security Model](docs/mosaic-security-model.md): Mosaic threats, trust assumptions, safe claims, privacy limits, and review gates.
- [Mosaic G4 Independent Review Packet](docs/mosaic-g4-independent-review-packet-2026-08-23.md): exact private-alpha review target, required independent lanes, source and evidence map, mandatory questions, declared non-proofs, and reviewer deliverable.
- [Mosaic G4 Findings Register](docs/mosaic-g4-findings-register.md): independent assignments, findings, remediation, retest, dispositions, and known evidence gaps; an empty register is never closure evidence.
- [Mosaic G4 Parser-Mutation Evidence](docs/mosaic-g4-parser-mutation-evidence-2026-08-23.md): exact test-only revision, first-party mutation design, focused result, production-tree parity, remaining parser families, and non-proofs.
- [Mosaic Private-Alpha Transport Bootstrap.1](docs/mosaic-private-alpha-transport-bootstrap.md): package-owned authenticated mailbox distribution, wrapper/ACK recovery, replay, and concrete G2 application obligations.
- [CashFusion Implementation Spec](docs/cashfusion-implementation-spec.md): normative Electron Cash `4.4.3` CashFusion behavior, round lifecycle, timing, and host seams.
- [CashFusion Official Protocol Matrix](docs/cashfusion-official-protocol-matrix.md): row-level implementation status and test evidence against the pinned Electron Cash baseline.
- [CashFusion Native Swift Support Statement](docs/cashfusion-native-support-statement.md): current public support claim, intentional exclusions, and remaining proof gates.
- [Integration Guide](docs/integration-guide.md): how app and OpalBase layers should wire OpalFusion.
- [Validation Guide](docs/validation.md): fast local loops, focused protocol/runtime filters, live-smoke caveats, and transcript replay direction.
- [Architecture Guide](docs/architecture.md): compact maintainer map of public API, runtime, transport, wire, execution, host, and diagnostics layers.
- [Architecture Complexity Audit](docs/architecture-complexity-audit.md): measured ownership findings, applied simplifications, deferred reopen signals, and validation budgets.

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
- Platforms: `macOS 26`
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
- Tracking the gated private-alpha roadmap and closure evidence: [Mosaic Mainnet-Alpha Progress](docs/mosaic-mainnet-alpha-progress.md)
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
