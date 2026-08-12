# OpalFusion Validation Guide

This guide separates fast deterministic package checks from slow live CashFusion proofing and future Mosaic conformance work. The default development loop should not depend on waiting for a real coordinator round.

## Default Local Loop

Run the full deterministic local suite for normal repo work through the repository wrapper. It keeps the Security.framework-backed Mosaic authorization suites, the CPU-heavy 23-slot material suite, and the reconnect-timing client suite in isolated serialized processes while bounding the remaining deterministic pool to four concurrent tests:

```bash
./scripts/run-validation-loop.sh all
```

Use `swift test --filter <suite>` for focused work. An unrestricted raw `swift test` can exhaust transient RSA key generation when all cryptographic suites start together and is not the full-suite validation lane.

Run a build-only check when you only need package compilation:

```bash
swift build
```

The current OpalCrypto dependency compiles a Metal library through a SwiftPM build plugin. Install the matching Xcode Metal Toolchain component before running package builds; a missing component stops the dependency build before OpalFusion sources or tests compile.

Use the validation wrapper when you want stable named loops:

```bash
./scripts/run-validation-loop.sh build
./scripts/run-validation-loop.sh all
./scripts/run-validation-loop.sh codec
./scripts/run-validation-loop.sh round
./scripts/run-validation-loop.sh runtime
./scripts/run-validation-loop.sh workflow
./scripts/run-validation-loop.sh client
./scripts/run-validation-loop.sh mosaic
./scripts/run-validation-loop.sh interop-parser
```

The wrapper keeps the live Electron Cash coordinator proof disabled for deterministic modes, even when the caller has an interop flag in their shell environment.

The local suite covers the protocol-neutral facade invariants, native protobuf primitives, official/manual CashFusion bytes, primary/covert codecs, pinned Electron Cash constants, round-engine scripts, production workflow materialization, loopback runtime behavior, host boundaries, and diagnostics.

## Coverage Boundary

Passing `./scripts/run-validation-loop.sh all` means the deterministic package checks passed. It does not prove complete OpalFusion capability, complete Electron Cash compatibility, successful operation against a real coordinator, or any live Mosaic support.

Mainnet-alpha.4 validation pins the profile and alpha.3 rejection; exact 138/161/184 capacity; 6–8-contributor overhead shares; salt commitment, salted-component, component-binding, purpose-separated authorization input, spent identifier, 417-byte token, 550-byte BCH-signature submission, PlayerCommit, dual-vector response-set, acknowledgement-set, transcript, signature-set, and complete-transaction vectors; exact 23-slot material with zero blanks and 24-member rejection; P2PKH input checks; Pedersen openings and grouped sums; and one structurally valid globally balanced off-commitment component. Admission-ledger tests cover attempt/generation/material routing, sender-global control replay, complete PlayerCommit and response barriers, real material-derived tokens crossing both anonymous gates, component sequence zero, signature sequence one, raw wrong-purpose rejection, same-x/opposite-parity aggregate rejection, published communication-key rejection, exact-duplicate precedence, semantic-rejection non-consumption, mailbox/sender/token/input conflicts, incomplete/extra signatures, shuffled complete-set determinism, terminal absorption, and in-place retry rejection. Runtime-session tests consume the exact acknowledgement set, signature set, complete payload, and candidate-bound completion validation. Resolver, signing-request, local-signature, assembler, and contributor-executor suites prove deterministic previous-output-backed all-input validation, exact host finalization and commit, pre-sign release, and post-sign recovery ordering. The conductor-coordinator suite proves the six-contributor post-manifest path through 276 blind evaluations, 138 admitted components, complete acknowledgements, all-input signature validation, exact assembly, and candidate-bound completion without wallet, network, or broadcast calls. Combined post-manifest driver and coordinator suites prove exact role selection, construction failure, bounded queues, causal effect draining, signed-event authentication, control and anonymous forwarding, contributor authority denial, one-shot lifecycle, source-loss ordering, and terminal state projection without adding a live network transport or public session.

The generic NIP-59 suite validates both official gift-wrap kinds, independent deterministic inbound identifiers, recipient-tag structure, strict unsigned-rumor coding, wrapper and seal signature order, seal-author binding, wrapper-identity separation, recipient-authentication failure, malformed nested payloads, and allocation limits. Mainnet-alpha.5 validation additionally rejects the superseded alpha.4 transport selector. The transport suite pins the kind-78 application namespace, exact `d` and `p` tags, regular kind-1059 delivery, 8,192-byte padding, allocation ceilings, cover timestamps, identities, and signed-wrapper replay mapping. Ingress and fan-in coverage proves attempt-scoped recipient selection, authentication before runtime mutation, globally distinct injected subscriptions, all-group startup, per-source order, bounded FIFO drain, source-loss and cancellation ordering, and the accepted-control append boundary. Three identical relay copies produce one control record; an append failure terminalizes with no stored record; and restored nonempty state fails before route startup because full runtime recovery is unavailable. The pure journal tests separately classify synthetic anonymous wrapper and mailbox facts. Publisher and bridge suites continue to prove exact roster/material binding, whole-batch handoff, exact-three-route/two-acknowledgement publication, and terminal no-reuse over injected capabilities. These tests do not prove global wrapper-key freshness, production-authenticated key or route allocation, a particular durable store, full admission/runtime/coordinator crash restoration, recipient-key persistence or erasure, authoritative endpoint independence, acknowledgement persistence, reconnect, NIP-42, proof of work, concrete Tor routing or circuit isolation, relay availability, app-owned wallet composition, broadcast approval, or live mainnet execution. The generic `RuntimeSessionDriver` still rejects mainnet-alpha. The accepted alpha.4 off-commitment vector remains evidence of a documented accountability limitation, not a privacy or membership guarantee.

The control-batch publisher suite proves foreign attempt, generation, material, manifest, and recipient-allocation rejection before route provisioning; one complete roster-sized route request keyed only by recipient event identity; manifest, recipient, and coding validation; cross-recipient connection uniqueness; per-recipient byte-identical three-route publication; two accepted acknowledgements for every roster member; all-route closure before success; and cleanup on allocation, quorum, and cancellation failures.

The anonymous-batch publisher suite proves bridge-sealed purpose and material binding; exact component and local-input recipient sets; recipient-only complete route requests; zero permit or event exposure before batch-global route preflight; per-recipient permit gating; cross-recipient connection uniqueness; byte-identical exact-three-route publication; two accepted acknowledgements per sealed wrap; and cleanup on permit, allocation, quorum, publication, and cancellation failures. The injected permits and routes are not evidence of timing privacy, endpoint authority, concrete Tor routing, durable delivery, persistence, retry, semantic loopback, a live Mosaic session, or mainnet execution.

The fast contributor transport bridge validator uses embedded verification keys, byte-shaped authorization requests, and a test lease without constructing evaluator-backed material. It proves exact bootstrap, manifest, and local-control mailbox binding; pre-material publication order; invalid eligibility before wallet work; construction failure; concurrent-use drain ordering; stop-request and termination-wait behavior; cancelled material construction; terminal absorption; no in-place reuse; and local versus foreign bootstrap binding for bridge-minted inbound route groups. The serialized contributor transport bridge conformance validator shares one evaluator-backed real 23-slot fixture to preserve lease and material binding; the ordered PlayerCommit → components → acknowledgement → local-signature path; exact route and permit requests; injected expiry propagation; and post-material publication failure, cancellation, and drain semantics. The minimum-roster composition validator constructs six contributor roots and one conductor root from one shared manifest and attempt, starts each existing fan-in over three distinct in-memory route capabilities, and drains every fan-in and contributor bridge exactly once without admitting a manifest or invoking wallet, material, publication, or RSA signing authority. It proves only deterministic lifecycle and wiring composition; semantic completion remains in the serialized real-crypto conformance lane, and production key distribution, route authority, timing policy, persistence, semantic loopback, and live execution remain unproved.

The fast post-manifest replay-journal validator uses embedded RSA verification keys and fixed-scalar secp256k1 identities; it does not generate RSABSSA signing keys. It proves exact attempt-context matching, control and synthetic-anonymous duplicate classification, control-sequence and anonymous mailbox conflicts, append failure without journal-state installation, rejection non-consumption, and rehydrated classification. The focused relay-fan-in cases additionally prove that three relay copies create one accepted control record, append failure terminalizes with no stored record, and a restored nonempty journal refuses a fresh runtime before any route opens. This is persistence-contract evidence, not proof of a particular durable store, accepted-anonymous coordinator integration, or crash-resumable execution: restoring the admission ledger, phase, coordinator work, wallet disposition, and publication state remains a separate recovery requirement.

The fast mailbox-route provisioning validator uses embedded RSA verification keys and fixed-scalar secp256k1 identities; it does not construct RSA signing keys. It proves the six-contributor plus conductor role projections, seven private control capabilities, the conductor's unlabeled 138-private-capability set, the complete 139-group conductor inbound allocation, exact three-route endpoint sets, fixture-wide distinct in-memory connections and subscriptions, one-shot inbound issuance, and rejection of binding, endpoint, connection, or opaque isolation-lease substitution before any route opens. Each owner enforces reuse only across its local purposes; the injected provisioner remains responsible for cross-peer allocation. These are structural ownership and reuse checks, not authenticated cross-peer key distribution, recipient-key persistence or erasure, proof that distinct lease values name distinct Tor circuits, remote-DNS or clearnet-exclusion proof, relay contact, or live-mainnet readiness.

The fan-in suite also pins route-to-recipient `p` binding before shared ingress, pre-subscription route drains, multiple stored events plus EOSE buffered without early admission, an exact roster-derived mailbox-group count boundary, and terminal failure when startup input exceeds the shared FIFO.

The current local suite does not replace a live coordinator smoke, reviewed transcript replay, wallet/app integration validation, or host-owned policy checks for coin selection, funding, signing authority, persistence, broadcast, retry behavior, and user-facing fusion controls. Those responsibilities remain separate proof gates or downstream integration concerns.

Use the fast loop to validate package behavior while editing. Use the live smoke and transcript replay path to establish CashFusion interoperability evidence.

## Focused Filters

Use focused filters while iterating on a specific layer:

```bash
swift test --filter CashFusionPrimaryMessageCodecValidator
swift test --filter CashFusionCovertMessageCodecValidator
swift test --filter CashFusionOfficialProtobufFixtureValidator
swift test --filter RoundEngineScriptedValidator
swift test --filter PrimaryRuntimeSessionValidator
swift test --filter LiveRuntimeDriverValidator
swift test --filter ProductionWorkflowValidator
swift test --filter ClientSessionValidator
swift test --filter FusionFacadeScaffoldValidator
swift test --filter MosaicAttemptCoreValidator
swift test --filter MosaicRoleElectionValidator
swift test --filter MosaicManifestAgreementValidator
swift test --filter MosaicManifestSignatureValidator
swift test --filter MosaicUnsignedTransactionTranscriptValidator
swift test --filter MosaicRuntimeSessionValidator
swift test --filter MosaicRuntimeSessionDriverValidator
swift test --filter MosaicRuntimeCoordinatorValidator
swift test --filter MosaicMainnetAlphaReservationCoordinatorValidator
swift test --filter MosaicMainnetAlphaPostManifestRuntimeDriverValidator
swift test --filter MosaicMainnetAlphaSigningRequestBuilderValidator
swift test --filter MosaicPreviousOutputContractValidator
swift test --filter MosaicSemanticValidator
swift test --filter MosaicNostrRelayMessageCodecValidator
swift test --filter MosaicNostrNIP59EnvelopeCodecValidator
swift test --filter MosaicMainnetAlphaPostManifestNIP59TransportValidator
swift test --filter MosaicMainnetAlphaPostManifestTransportIngressValidator
swift test --filter PostManifestReplayJournal
swift test --filter MosaicMainnetAlphaControlPublicationBridgeValidator
swift test --filter MosaicMainnetAlphaPostManifestAnonymousPublicationBridgeValidator
swift test --filter MosaicMainnetAlphaPostManifestAnonymousBatchPublisherValidator
swift test --filter MosaicMainnetAlphaPostManifestControlBatchPublisherValidator
swift test --filter MosaicMainnetAlphaPostManifestRelayPublisherValidator
swift test --filter MosaicMainnetAlphaPostManifestRelayFanInValidator
swift test --filter MosaicMainnetAlphaPostManifestContributorTransportBridgeValidator
swift test --filter MosaicMainnetAlphaPostManifestContributorTransportBridgeConformanceValidator
swift test --filter MosaicMainnetAlphaMinimumRosterCompositionValidator
swift test --filter MosaicMainnetAlphaPostManifestMailboxRouteProvisioningValidator
swift test --filter MosaicNIP01RelaySessionValidator
swift test --filter MosaicOpalV0ProfileValidator
swift test --filter MosaicOpalV0AuthorizationValidator
swift test --filter MosaicOpalV0WireContractValidator
swift test --filter MosaicOpalV0TransportContractValidator
swift test --filter MosaicHostContractValidator
swift test --filter MosaicMainnetAlphaContractValidator
swift test --filter MosaicMainnetAlphaContributionFeeValidator
swift test --filter MosaicMainnetAlphaAggregateContractValidator
swift test --filter MosaicMainnetAlpha4MaterialValidator
swift test --filter MosaicMainnetAlphaAdmissionLedgerValidator
swift test --filter MosaicMainnetAlphaRuntimeSessionValidator
swift test --filter MosaicMainnetAlphaBCHCompletionValidator
swift test --filter MosaicMainnetAlphaLocalBCHSignatureBuilderValidator
swift test --filter MosaicMainnetAlphaContributorExecutorValidator
swift test --filter MosaicMainnetAlphaConductorCoordinatorValidator
```

Focused filters isolate one layer, but they are not uniformly fast. `MosaicMainnetAlphaPostManifestContributorTransportBridgeValidator`, `MosaicMainnetAlphaMinimumRosterCompositionValidator`, and `MosaicMainnetAlphaPostManifestMailboxRouteProvisioningValidator` are the fast contributor lifecycle, composition, and provisioning loops; none constructs RSA signing keys. Target 15 seconds for narrow lifecycle work and cap the warm minimum-roster or mailbox-provisioning filter at 30 seconds. A fast filter that reaches RSA generation, a live wallet or network, a SwiftPM lock retry, or the 30-second cap must stop for fixture diagnosis instead of widening the budget. `MosaicMainnetAlphaPostManifestContributorTransportBridgeConformanceValidator`, together with every suite named by the wrapper's `MOSAIC_RSA_DEPENDENT_FILTER`, is deterministic but intentionally slow and serialized. None of the fast focused filters require coordinator credentials, wallet secrets, live UTXOs, Tor, or funded test material.

`./scripts/run-validation-loop.sh mosaic` runs every `Mosaic*` suite followed by `FusionFacadeScaffoldValidator`. Passing it proves only the bounded deterministic conformance and public-scaffold checks described above.

## Live Electron Cash Smoke

The live smoke runner is an opt-in proof gate for a configured Electron Cash `4.4.3`-compatible coordinator environment:

```bash
./scripts/run-electron-cash-interop-smoke.sh --run-count 1
./scripts/run-electron-cash-interop-smoke.sh 3
```

The real coordinator session proof is registered as an opt-in Swift Testing test and remains disabled for normal local validation. The runner enables the interop gate for the test process, verifies the live proof test identifier is registered, and then executes the filtered interop suite. A successful script run is still only live-smoke evidence for the configured environment; complete compatibility remains blocked until repeated smoke and reviewed transcript replay evidence exist.

The runner requires `OPALFUSION_EC_*` environment variables and intentionally omits their values from output. Keep coordinator hostnames, ports, wallet material, private keys, scripts, addresses, Tor settings, and raw environment dictionaries out of repo docs and committed artifacts.

## Transcript Capture And Replay Direction

Transcript capture is the bridge from slow live proofing to fast local replay:

```bash
./scripts/run-electron-cash-transcript-capture.sh --output /private/tmp/opalfusion-electron-cash-transcript.swift
```

Use capture only after a configured live smoke actually executes and passes the real coordinator session proof. The capture candidate must be reviewed outside the repository, stripped to approved test-only primary/covert byte fixtures, then committed in a later replay slice. Once replay fixtures exist, they should become the fast Electron Cash compatibility loop, while live smoke remains the slower confidence gate.

## Acceptance For Docs And Protocol Changes

- Run `./scripts/run-validation-loop.sh all` after changes that touch examples, public API references, protocol behavior, or validation docs.
- Run the most relevant focused filter first when changing a narrow layer.
- Run live smoke only when the goal is coordinator-backed proof and the environment is configured.
- Update [Opal Fusion Specification](opal-fusion-specification.md), [Mosaic Protocol Specification](mosaic-protocol-specification.md), and [Mosaic Security Model](mosaic-security-model.md) together when shared boundaries or Mosaic invariants change.
- Update [CashFusion Official Protocol Matrix](cashfusion-official-protocol-matrix.md) when row-level support status or test evidence changes.
- Update [CashFusion Native Swift Support Statement](cashfusion-native-support-statement.md) when the public support claim or remaining proof gates change.
