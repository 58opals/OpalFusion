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
./scripts/run-validation-loop.sh mosaic-fast
./scripts/run-validation-loop.sh mosaic-private-alpha-consumer-surface
./scripts/run-validation-loop.sh mosaic-private-alpha-spi
./scripts/run-validation-loop.sh mosaic-rehearsal
./scripts/run-validation-loop.sh interop-parser
```

For exact cross-repository work, set `OPALFUSION_SPM_SCRATCH_PATH`, `OPALFUSION_SPM_CACHE_PATH`, `OPALFUSION_SPM_CONFIG_PATH`, `OPALFUSION_SPM_SECURITY_PATH`, and `OPALFUSION_SPM_MODULE_CACHE_PATH` to the same lane used by the preceding SwiftPM resolve and dependency audit. These overrides are local validation inputs; local paths and private remotes must not be committed to the product manifest or lockfile.

The wrapper keeps the live Electron Cash coordinator proof disabled for deterministic modes, even when the caller has an interop flag in their shell environment.

The local suite covers the protocol-neutral facade invariants, native protobuf primitives, official/manual CashFusion bytes, primary/covert codecs, pinned Electron Cash constants, round-engine scripts, production workflow materialization, loopback runtime behavior, host boundaries, and diagnostics.

## Coverage Boundary

Tests own protocol bytes, authentication, replay protection, participant lifecycle, host integration, and recovery. Keep canonical vectors, real cryptographic checks, and exact roster or capacity tests when those properties define the contract. Consolidate repeated fixture or value-construction assertions at one owner; retain consumer-facing privacy, authority, and cancellation checks. Source inspection should protect boundaries that executed tests cannot express, rather than freeze incidental declaration spellings.

Mosaic test helpers reuse immutable cryptographic preparation within each test process. Material reuse is bound to the manifest, attempt, generation, contributor, and material identity; default execution preparation also reuses validated authorization and signing inputs. Sessions, admission ledgers, recovery owners, stores, and probes remain independent for each consumer. Formation phase templates are built through real formation and restored with the consumer's binding through normal authenticated recovery; tests still execute every event and recovery cut in the phase they protect. Fresh-material and complete-formation tests continue to exercise construction. Include cold preparation when measuring a process, and keep the existing serialized and bounded lanes unchanged.

Passing `./scripts/run-validation-loop.sh all` means the deterministic package checks passed. It does not prove complete OpalFusion capability, complete Electron Cash compatibility, successful operation against a real coordinator, or any live Mosaic support.

Mainnet-alpha.4 validation pins the profile and alpha.3 rejection; exact 138/161/184 capacity; 6–8-contributor overhead shares; salt commitment, salted-component, component-binding, purpose-separated authorization input, spent identifier, 417-byte token, 550-byte BCH-signature submission, PlayerCommit, dual-vector response-set, acknowledgement-set, transcript, signature-set, and complete-transaction vectors; exact 23-slot material with zero blanks and 24-member rejection; P2PKH input checks; Pedersen openings and grouped sums; and one structurally valid globally balanced off-commitment component. Admission-ledger tests cover attempt/generation/material routing, sender-global control replay, complete PlayerCommit and response barriers, real material-derived tokens crossing both anonymous gates, component sequence zero, signature sequence one, raw wrong-purpose rejection, same-x/opposite-parity aggregate rejection, published communication-key rejection, exact-duplicate precedence, semantic-rejection non-consumption, mailbox/sender/token/input conflicts, incomplete/extra signatures, shuffled complete-set determinism, terminal absorption, and in-place retry rejection. Runtime-session tests consume the exact acknowledgement validation artifacts, signature set, complete payload, and candidate-bound completion validation. Resolver, signing-request, local-signature, assembler, and contributor-executor suites prove deterministic previous-output-backed all-input validation, exact host finalization and commit, pre-sign release, and post-sign recovery ordering. The conductor-coordinator suite proves the six-contributor post-manifest path through 276 blind evaluations, 138 admitted components, complete acknowledgements, all-input signature validation, exact assembly, and candidate-bound completion without wallet, network, or broadcast calls. The owner-authorized execution gate plus route, transport, runtime-session, coordinator, and private-alpha recovery suites prove exact role selection, bounded queues, causal effect draining, signed-event authentication, control and anonymous forwarding, one-shot lifecycle, exact companion-journal replay, persisted terminal reconstruction, source-loss ordering, and terminal state projection without adding a live network transport or public session.

The generic NIP-59 suite validates both official gift-wrap kinds, independent deterministic inbound identifiers, recipient-tag structure, strict unsigned-rumor coding, wrapper and seal signature order, seal-author binding, wrapper-identity separation, recipient-authentication failure, malformed nested payloads, and allocation limits. Mainnet-alpha.5 validation additionally rejects the superseded alpha.4 transport selector. The transport suite pins the kind-78 application namespace, exact `d` and `p` tags, regular kind-1059 delivery, 8,192-byte padding, allocation ceilings, cover timestamps, identities, and signed-wrapper replay mapping. Ingress and fan-in coverage proves attempt-scoped recipient selection, authentication before runtime mutation, globally distinct injected subscriptions, all-group startup, per-source order, bounded FIFO drain, source-loss and cancellation ordering, and the accepted-control append boundary. Three identical relay copies produce one control record, an append failure terminalizes with no stored record, and generic fresh construction rejects restored nonempty state before route startup. Private-alpha recovery cases separately reconstruct exact companion journals and persisted terminal state before any normal route provisioning. Publisher and bridge suites continue to prove exact roster/material binding, whole-batch handoff, exact-three-route/two-acknowledgement publication, and terminal no-reuse over injected capabilities. These tests do not prove global wrapper-key freshness, production-authenticated key or route allocation, a production durable store, recipient-key persistence or erasure, authoritative endpoint independence, concrete Tor routing or circuit isolation, relay availability, app-owned wallet composition, broadcast approval, or live mainnet execution. The generic `RuntimeSessionDriver` still rejects mainnet-alpha. The accepted alpha.4 off-commitment vector remains evidence of a documented accountability limitation, not a privacy or membership guarantee.

The control-batch publisher suite proves foreign attempt, generation, material, manifest, and recipient-allocation rejection before route provisioning; one complete roster-sized route request keyed only by recipient event identity; manifest, recipient, and coding validation; cross-recipient connection uniqueness; per-recipient byte-identical three-route publication; two accepted acknowledgements for every roster member; all-route closure before success; and cleanup on allocation, quorum, and cancellation failures.

The anonymous-batch publisher suite proves bridge-sealed purpose and material binding; exact component and local-input recipient sets; recipient-only complete route requests; zero permit or event exposure before batch-global route preflight; per-recipient permit gating; cross-recipient connection uniqueness; byte-identical exact-three-route publication; two accepted acknowledgements per sealed wrap; and cleanup on permit, allocation, quorum, publication, and cancellation failures. The injected permits and routes are not evidence of timing privacy, endpoint authority, concrete Tor routing, durable delivery, persistence, retry, semantic loopback, a live Mosaic session, or mainnet execution.

The fast contributor transport bridge validator uses embedded verification keys, byte-shaped authorization requests, and a test lease without constructing evaluator-backed material. It proves exact bootstrap, manifest, and attempt-owner binding; pre-material publication order; invalid eligibility before wallet work; construction failure; concurrent-use drain ordering; stop-request and termination-wait behavior; cancelled material construction; terminal absorption; and no in-place reuse. Invalid mailbox projections are tested at the attempt owner, which is now the bridge's sole control and anonymous route-access and validation gateway; the injected provisioner remains the raw connection and isolation-lease authority. The bridge no longer has a raw route-provider constructor. The serialized contributor transport bridge conformance validator shares one evaluator-backed real 23-slot fixture to preserve lease and material binding; the ordered PlayerCommit → components → acknowledgement → local-signature path; exact route and permit requests; injected expiry propagation; and post-material publication failure, cancellation, and drain semantics. The minimum-roster composition validator constructs six contributor roots and one conductor root from one shared manifest and attempt, starts each transport-only fan-in over three distinct in-memory route capabilities, and drains every fan-in and contributor bridge exactly once without admitting a manifest or invoking wallet, material, publication, or RSA signing authority. It proves only deterministic lifecycle and wiring composition; semantic completion remains in the serialized real-crypto conformance lane, and production key distribution, route authority, timing policy, persistence, semantic loopback, and live execution remain unproved.

The focused contributor feedback command is `./scripts/run-validation-loop.sh mosaic-fast`. Before starting SwiftPM, it statically rejects evaluator access, evaluator generation, and real-material fixture preparation in its two selected source files. It then runs only the pure fan-in route validator and contributor transport lifecycle suite. On 2026-08-13 both suites passed inside a larger warm run in 14.412 seconds, so the focused command retains a 15-second post-build budget. The minimum-roster, mailbox-provisioning, and execution-gate suites remain RSA-free structural validation, but they are not part of this latency contract.

The fast post-manifest replay-journal validator uses embedded RSA verification keys and fixed-scalar secp256k1 identities; it does not generate RSABSSA signing keys. It proves exact attempt-context matching, control and synthetic-anonymous duplicate classification, control-sequence and anonymous mailbox conflicts, append failure without journal-state installation, rejection non-consumption, rehydrated classification, and bounded recovery decoding. The focused relay-fan-in cases additionally prove that three relay copies create one accepted control record, append failure terminalizes with no stored record, and a restored nonempty journal refuses a fresh runtime before any route opens. This is the generic fresh-construction guard; separate private-alpha recovery validation authenticates the exact snapshot, reconstructs coordinator and publication state, and fails closed on partial or mismatched companion data. Neither lane proves a production durable store, recipient-key lifecycle, wallet disposition, or live network execution.

The fast mailbox-route provisioning validator uses embedded RSA verification keys and fixed-scalar secp256k1 identities; it does not construct RSA signing keys. It proves the six-contributor plus conductor role projections, seven private control capabilities, the conductor's unlabeled 138-private-capability set, the complete 139-group conductor inbound allocation, exact three-route endpoint sets, fixture-wide distinct in-memory connections and subscriptions, one-shot inbound issuance, and rejection of binding, endpoint, connection, or opaque isolation-lease substitution before any route opens. Each owner enforces reuse only across its local purposes; the injected provisioner remains responsible for cross-peer allocation. These are structural ownership and reuse checks, not authenticated cross-peer key distribution, recipient-key persistence or erasure, proof that distinct lease values name distinct Tor circuits, remote-DNS or clearnet-exclusion proof, relay contact, or live-mainnet readiness.

`MosaicMainnetAlphaPostManifestRelayFanInRouteValidationValidator` is the narrowest fast structural filter. It uses fixed scalar secp256k1 keys and no Mosaic mainnet fixture, validates valid and malformed role/recipient/route/subscription/relay/coding plans, and cannot claim provisioning, construct ingress or the specialized driver, access a journal, or open or close a route. Run it with `swift test --skip-build --filter MosaicMainnetAlphaPostManifestRelayFanInRouteValidationValidator`; its warm post-build budget is 15 seconds.

`MosaicMainnetAlphaExecutionGateValidator` is the owner-authorized construction filter. It parses only the two embedded RSABSSA public keys, provisions one contributor control mailbox, and proves that the generic mainnet-alpha driver still rejects; foreign attempt, generation, material, local-role, or manifest bindings do not consume the owner-issued capability; one exact fan-in consumes the sole claim; a second exact claim fails; successful start carries one valid in-memory control relay frame through the actual ingress and specialized driver before deterministic stop; and a post-transfer ingress failure closes every route before returning while leaving the claim consumed. Run it with `swift test --skip-build --filter MosaicMainnetAlphaExecutionGateValidator`; its warm post-build budget is 15 seconds. It is construction, authenticated delivery, and lifecycle authorization evidence, not live relay, Tor, wallet, node, value-movement, or deployment evidence.

The private-alpha consumer-surface gate is `./scripts/run-validation-loop.sh mosaic-private-alpha-consumer-surface`. It statically rejects `@testable import OpalFusion` from the selected recovery validator, then compiles and runs the app-visible SPI recovery path through loaded-owner continuation, resume, and transport-bootstrap proof access. It must pass before the expensive producer aggregate or downstream promotion so an internal test fixture cannot hide a missing consumer API. Its early-phase proof request is expected to fail closed because no complete manifest exists; successful post-manifest proof restoration remains in the authoritative aggregate.

The authoritative private-alpha recovery aggregate is `./scripts/run-validation-loop.sh mosaic-private-alpha-spi`. It first rejects any direct RSABSSA signing-key generation in the transport validator and its test fixture, then runs the complete serialized `MosaicPrivateAlphaRuntimeSPIValidator` suite in one process so the cached nine-member, 59-document proof is built once while every exact persistence readback, snapshot reload, re-authentication, signed formation prefix, sealed recovery, and post-manifest construction remains covered. Signed formation recovery is intentionally divided into seven phase-bounded test bodies: each body reaches its starting phase through the same real state machine, then reloads after every signed prefix in that phase and verifies the next recovery boundary. This preserves the complete recovery contract while allowing an exact-revision downstream CI owner to assign individual test bodies deterministically across isolated jobs; downstream sharding must discover the complete package test list, reject duplicate normalized identifiers, and assign every identifier exactly once without changing the selected test set. The wrapper starts the serialized `MosaicPrivateAlphaTransportBootstrapValidator` suite in a fresh process so the transport fixture does not inherit process-global test state from the long-running runtime suite; it does not parallelize, skip, or change either suite's test selection. The transport suite imports RFC 9500's publicly known RSA-2048 test key through Security, and OpalCrypto validates the resulting `SecKey` capability and performs every cryptographic calculation. The fixture is test-target-only, has no security properties, and is not a substitute for application-owned production key generation or custody evidence. The command fails if either process fails and has no elapsed-time cutoff: long canonical signing and recovery progress is not a failure. A pass is package-level deterministic SPI evidence only; it does not prove an application durable backend, live transport, broadcast, value movement, readiness, privacy, or anonymity.

The named private mainnet rehearsal is `./scripts/run-validation-loop.sh mosaic-rehearsal`. It runs exactly the six-contributor conductor completion and contributor exact-commit cases, serially in one SwiftPM process so both purpose-separated real RSABSSA evaluator fixtures are paid once. The conductor case proves authorization issuance and canonical completion publication; the contributor case proves local authorization finalization, BCH signing, exact complete-transaction validation, and one refined-host commit. The host and publication seams are in-memory, OpalFusion has no broadcast callback, and the rehearsal performs no relay contact, wallet access, value movement, or public session construction. It is intentionally slow milestone evidence, not part of the fast feedback lane and not proof of concrete Tor, authenticated mailbox distribution, crash continuation, or live-mainnet readiness. Run it in an environment where Security.framework may create nonpersistent RSA keys; an immediate `authorizationEvaluatorUnavailable` before either test body is a runner precondition failure and should not trigger repeated per-test retries.

`MosaicMainnetAlphaReservationCoordinatorDependencyValidator` is the material-construction-free reservation ownership filter. It proves complete lease equality, unconditional execution-material dependency, exact pre-sign release, and exact-reference recovery after release failure without creating a `LocalContributionMaterial`. Before running it, apply the same static pattern used by `assert_mosaic_reservation_dependency_lane_is_material_free`: `requireAuthorizationEvaluators\(|authorizationEvaluator\(|bchSignatureAuthorizationEvaluator\(|AuthorizationEvaluator\.generate\(|ExecutionFixtures?\.prepare\(|LocalContributionMaterial\.build\(|makeLocalContributionMaterial\(|makeMaterializedPreparation\(`. Run it once with `swift test --skip-build --filter MosaicMainnetAlphaReservationCoordinatorDependencyValidator`; its warm post-build budget is 15 seconds. The existing full-material reservation suite belongs to the one serialized `MOSAIC_RSA_DEPENDENT_FILTER` process, and contributor-executor coverage retains successful execution, pre-sign release, and post-sign recovery.

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
swift test --filter MosaicMainnetAlphaReservationCoordinatorDependencyValidator
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
swift test --filter MosaicMainnetAlphaPostManifestPublicationRouteAllocationValidator
swift test --filter MosaicMainnetAlphaPostManifestRelayPublisherValidator
swift test --filter MosaicMainnetAlphaPostManifestRelayFanInValidator
swift test --filter MosaicMainnetAlphaPostManifestRelayFanInRouteValidationValidator
swift test --filter MosaicMainnetAlphaPostManifestContributorTransportBridgeValidator
swift test --filter MosaicMainnetAlphaPostManifestContributorTransportBridgeConformanceValidator
swift test --filter MosaicMainnetAlphaMinimumRosterCompositionValidator
swift test --filter MosaicMainnetAlphaPostManifestMailboxRouteProvisioningValidator
swift test --filter MosaicMainnetAlphaExecutionGateValidator
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

Focused filters isolate one layer, but they are not uniformly fast. The `mosaic-fast` wrapper owns the 15-second contributor feedback contract, and the separately guarded `MosaicMainnetAlphaReservationCoordinatorDependencyValidator` owns the 15-second reservation-dependency contract. `MosaicMainnetAlphaMinimumRosterCompositionValidator`, `MosaicMainnetAlphaPostManifestMailboxRouteProvisioningValidator`, and `MosaicMainnetAlphaExecutionGateValidator` are extended RSA-free structural checks; they do not require coordinator credentials, wallet secrets, live UTXOs, Tor, or funded test material, but they have no claim to the focused latency budget. A focused filter that reaches RSA generation, a live wallet or network, a SwiftPM lock retry, or its documented cap must stop for fixture diagnosis instead of widening the budget. `MosaicMainnetAlphaPostManifestContributorTransportBridgeConformanceValidator`, together with every suite named by the wrapper's `MOSAIC_RSA_DEPENDENT_FILTER`, is deterministic but intentionally slow and serialized. The slow filter includes the runtime, admission, conductor, contributor, reservation coordinator, local BCH-signature, anonymous publication bridge, anonymous batch publisher, contributor conformance, contract, and Opal v0 authorization suites so both purpose-separated Security.framework evaluator fixtures are shared in one process.

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
- Update [Opal Fusion Specification](opal-fusion-specification.md), [Mosaic Protocol Specification](mosaic-protocol-specification.md), [Mosaic Security Model](mosaic-security-model.md), and any applicable frozen profile such as the [private-deployment supplement](mosaic-mainnet-alpha-private-deployment.md) together when shared boundaries or Mosaic invariants change.
- Update [CashFusion Official Protocol Matrix](cashfusion-official-protocol-matrix.md) when row-level support status or test evidence changes.
- Update [CashFusion Native Swift Support Statement](cashfusion-native-support-statement.md) when the public support claim or remaining proof gates change.
