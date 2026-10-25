# OpalFusion Validation Guide

This guide separates focused development feedback, complete offline assurance, and live CashFusion proofing. Expensive Mosaic cryptography does not require a network connection. Full Mosaic and live proofing are explicit choices, never part of the default CashFusion lane.

## Default Local Loop

Run the bounded development selection for normal implementation work through the repository wrapper:

```bash
./scripts/run-validation-loop.sh
# Equivalent explicit mode:
./scripts/run-validation-loop.sh develop
```

The wrapper first builds the dependency-free native Swift runner in `Tools/Validation` with the selected toolchain. The runner then builds only the CashFusion harness at `Tests/CashFusion`, whose dependencies exclude Mosaic and the compatibility umbrella. The engine build has a separate 300-second deadline, after runner bootstrap. Discovery, process startup, and cold fixture preparation then share one 60-second post-build budget. Timeout fails the run, terminates only the owned process group, and allows up to five additional seconds for cleanup; it does not retry, extend the budget, or reduce the selection. Interruption also cleans up the owned processes. Test deadlines are runner limits; CashFusion protocol timing constants and runtime validation remain unchanged.

The default selects the nine critical suites listed below, not every discovered CashFusion suite. It prints `PASS (selected scope only)`; this is development feedback, not complete assurance. Use the narrowest relevant named mode or an explicit `cashfusion-focused FILTER` / `mosaic-focused FILTER` while editing. Both focused modes reject an empty discovery match before executing tests, retain serial execution, and require an actual successful, non-skipped testcase in SwiftPM's xUnit output. Discovery alone cannot establish execution: a regex anchored to a listed method's trailing `()` can match discovery while SwiftPM executes no cases and returns zero. Prefer a suite selector such as `MosaicPrivateAlphaRuntimeSPIValidator/` or a method-name prefix without trailing parentheses. Raw `swift test --package-path Tests/CashFusion --filter <suite>` selects a CashFusion suite, and `swift test --package-path Tests/Mosaic --filter <suite>` explicitly selects a deferred Mosaic suite. Raw commands do not provide the wrapper's deadlines. Filters in the root package cannot isolate compilation: SwiftPM builds unrelated root products even when a test filter excludes them. Root tests have moved into the two harness packages.

Run a build-only check when you only need package compilation:

```bash
./scripts/run-validation-loop.sh build
```

The current OpalCrypto dependency compiles a Metal library through a SwiftPM build plugin. Install the matching Xcode Metal Toolchain component before running package builds; a missing component stops the dependency build before OpalFusion sources or tests compile.

Use the validation wrapper when you want stable named loops:

```bash
./scripts/run-validation-loop.sh build
./scripts/run-validation-loop.sh fast
./scripts/run-validation-loop.sh cashfusion-all
./scripts/run-validation-loop.sh mosaic-all
./scripts/run-validation-loop.sh all
./scripts/run-validation-loop.sh assurance
./scripts/run-validation-loop.sh codec
./scripts/run-validation-loop.sh round
./scripts/run-validation-loop.sh runtime
./scripts/run-validation-loop.sh workflow
./scripts/run-validation-loop.sh client
./scripts/run-validation-loop.sh mosaic
./scripts/run-validation-loop.sh mosaic-fast
./scripts/run-validation-loop.sh mosaic-private-alpha-consumer-surface
./scripts/run-validation-loop.sh mosaic-private-alpha-spi
./scripts/run-validation-loop.sh mosaic-private-alpha-transport
./scripts/run-validation-loop.sh mosaic-rehearsal
./scripts/run-validation-loop.sh interop-parser
```

For exact cross-repository work, set `OPALFUSION_SPM_SCRATCH_PATH`, `OPALFUSION_SPM_CACHE_PATH`, `OPALFUSION_SPM_CONFIG_PATH`, `OPALFUSION_SPM_SECURITY_PATH`, and `OPALFUSION_SPM_MODULE_CACHE_PATH` to the same lane used by the preceding SwiftPM resolve and dependency audit. These overrides are local validation inputs; machine-specific paths and private remotes must not be committed to the product manifest or lockfile. Keep the CashFusion and Mosaic scratch directories separate; they have distinct harness graphs and test executables.

The wrapper keeps the live Electron Cash coordinator proof disabled for deterministic modes, even when the caller has an interop flag in their shell environment.

SwiftPM package sandboxing remains enabled, including when custom cache paths are supplied. A surrounding execution environment must permit SwiftPM to start its sandbox; a sandbox launch failure is infrastructure failure, not permission to disable package isolation.

The 15-second `mosaic-fast` lane reuses the freshly built bundle through SwiftPM's [documented Darwin Swift Testing helper](https://github.com/swiftlang/swift-testing/blob/main/Documentation/CommandlineDebugging.md). Bundle, helper and matching selected Xcode test-library paths are resolved within the build deadline. Complete discovery, readiness checks, process startup and all selected tests still share the unchanged post-build deadline. This avoids repeating package planning during discovery and execution; missing helper or bundle inputs fail the lane. Other lanes retain their SwiftPM commands.

Complete CashFusion validation covers native protobuf primitives, official/manual bytes, primary/covert codecs, pinned Electron Cash constants, round-engine scripts, production workflow materialization, loopback runtime behavior, host boundaries, diagnostics, and real CashFusion cryptography. Mosaic's independent harness retains all its cryptographic conformance, exact authenticated recovery, and mixed facade cases. No existing test cases are removed by the split.

### Development CashFusion Coverage

The default `develop` lane selects these critical suites. `ClientSessionValidator` runs in its existing serialized process; the other eight selected suites share a pool bounded to four concurrent tests. Existing suite-level serialization remains effective. The explicit `fast` and `cashfusion-all` aliases retain their previous complete selection, with the client in its serialized process and its complete complement in the width-four pool.

| Contract | Complete suites |
| --- | --- |
| CashFusion codecs and official bytes | `CashFusionPrimaryMessageCodecValidator`, `CashFusionCovertMessageCodecValidator`, `CashFusionOfficialProtobufFixtureValidator` |
| Round transitions and workflow | `RoundEngineScriptedValidator`, `ProductionWorkflowValidator` |
| Client lifecycle and runtime state | `ClientSessionValidator`, `PrimaryRuntimeSessionValidator`, `CovertRuntimeSessionValidator` |
| CashFusion diagnostics | `OpalDiagnosticsFusionValidator` |

Before execution, discovery must find at least one test in every required critical suite and reject empty, duplicate, or foreign-module identifiers. The runner prints selected and total discovered counts and assigns every selected test exactly once. Unselected tests remain registered and available in complete assurance; no test source, workload, assertion, or eligibility is changed by selecting a development lane. Facade, Mosaic host, reservation, and transport tests remain in the explicit Mosaic harness. A development pass does not establish live coordinator interoperability, resolve the documented support gaps, or prove Mosaic conformance or package publication readiness.

### Comprehensive Local Validation

Explicit `cashfusion-all` / `fast` validation runs every discovered CashFusion test exactly once within 60 seconds after build. Discovery, startup, and fixture preparation count toward that deadline. It does not weaken codec, malformed-message, cryptographic, timing, cancellation, or host validation to meet the limit. There is no larger alternate CashFusion budget.

`mosaic-all` explicitly runs every deferred Mosaic and facade test. It retains the Security.framework-backed authorization suites and the 23-slot material suite in isolated serialized processes, followed by their exact complement at width four. A complete offline run measured 6,099.400 post-build seconds (101.7 minutes) on October 25, 2026; that is an observation, not a current timing promise. The explicit slow lane has a 7,200-second post-build deadline. `assurance` / `all` explicitly run both complete harnesses with their separate budgets. None of these modes enables a live coordinator. Do not run `develop` and then complete CashFusion solely for duplicate acceptance: the complete lane already includes the development selection. Rerun affected checks after a correction; do not repeat unchanged assurance merely for a fresh timestamp.

| Lane | Build deadline | Post-build deadline | Scope |
| --- | --- | --- | --- |
| Default / `develop` | 300 seconds | 60 seconds | Nine critical CashFusion suites, selected-scope evidence |
| `fast` / `cashfusion-all` | 300 seconds | 60 seconds | Every deterministic CashFusion test |
| `codec`, `round`, `runtime`, `workflow`, `client`, `interop-parser` | 300 seconds | 60 seconds | Named CashFusion suites |
| `mosaic-fast` | 300 seconds | 15 seconds | Existing material-free Mosaic feedback selection |
| Other explicit Mosaic modes | 300 seconds | 7,200 seconds | Named Mosaic selection or complete Mosaic harness |
| `assurance` / `all` | Per engine above | Per engine above | Both complete harnesses, once each |

The harness lockfiles retain the same external dependency revisions as the root package. Changing dependency versions requires deliberate lockfile updates and the owning engine's complete validation. A deadline failure is a failed check requiring fixture or runner diagnosis, not permission to skip cases, reduce protocol delays, or expand the deadline automatically.

The validation entry point builds the dependency-free Swift runner in `Tools/Validation` before entering an engine lane. Its tool bootstrap is separate from the unchanged 300-second engine-build and post-build deadlines. Runner contracts can be checked without cryptographic execution using `swift test --package-path Tools/Validation --scratch-path .build/validation-tools --jobs 2`. These Swift Testing checks exercise command dispatch, discovery failures, failure propagation, timeouts, interruption cleanup, parser proof history, and live-coordinator exclusion through a native command double; they are runner evidence, not engine package-test evidence. The runner and its tests require the selected Swift toolchain and Apple system libraries, with no Python runtime or external package dependencies.

The `Dependency graph` workflow runs on pushes and pull requests. It resolves the root, CashFusion and Mosaic package graphs against their published dependencies and requires all three tracked lockfiles to remain unchanged. This metadata check runs without an engine build or live proof and does not replace the engine validation required above.

### Offline Timing Profiles

Every executed phase reports its elapsed time, including failed phases. Rank completed test and suite timings from a retained log without running the suite again:

```bash
./scripts/run-validation-loop.sh profile-log /path/to/validation.log
```

This bounded parser accepts a regular UTF-8 log up to 64 MiB and prints the ten slowest completed records per kind plus harness summaries. Reported case and suite wall times overlap under concurrent execution; do not sum them. A log may be truncated, may include failures, and belongs to its original sources/toolchain. This command explicitly supplies historical analysis, not current validation acceptance or CPU attribution.

For a fresh CPU investigation, select one exact offline case with `mosaic-focused FILTER`, retain its normal assertions and inputs, and sample only its owned test helper using macOS `sample`. Stop sampling at a predetermined diagnostic window; if the test itself is interrupted or exceeds its deadline, record incomplete profiling and failure rather than claiming a passing test. Keep the full run separate. The October 25 complete run spent 2,580.215 seconds in authorization, 245.440 seconds in material, and 3,268.829 seconds in remaining protocol/composition tests; these sequential harness durations can be compared. A bounded sample observed BIP340 verification-key reconstruction and elliptic-curve precomputation. It does not attribute the entire run to those functions or justify removing recovery cuts, caching mutable sessions, reducing roster sizes, or weakening cryptographic checks.

A fresh one-second sample of the isolated signed-admission-prefix recovery case on the same date found cold immutable formation preparation constructing signed admissions through BIP340 signing and hardened scalar arithmetic. The diagnostic execution was stopped after approximately 138 seconds and is incomplete, with no passing-test or complete-recovery claim. This confirms that a narrow selector can still pay substantial cold fixture cost; it does not prove that this initialization accounts for the entire full-suite runtime.

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

The authoritative private-alpha recovery aggregate is `./scripts/run-validation-loop.sh mosaic-private-alpha-spi`. It first rejects any direct RSABSSA signing-key generation in the transport validator and its test fixture, then runs the complete serialized `MosaicPrivateAlphaRuntimeSPIValidator` suite in one process so the cached nine-member, 59-document proof is built once while every exact persistence readback, snapshot reload, re-authentication, signed formation prefix, sealed recovery, and post-manifest construction remains covered. Signed formation recovery is intentionally divided into seven phase-bounded test bodies: each body reaches its starting phase through the same real state machine, then reloads after every signed prefix in that phase and verifies the next recovery boundary. This preserves the complete recovery contract while allowing an exact-revision downstream CI owner to assign individual test bodies deterministically across isolated jobs; downstream sharding must discover the complete package test list, reject duplicate normalized identifiers, and assign every identifier exactly once without changing the selected test set. The wrapper starts the serialized `MosaicPrivateAlphaTransportBootstrapValidator` suite in a fresh process so the transport fixture does not inherit process-global test state from the long-running runtime suite; it does not parallelize, skip, or change either suite's test selection. The transport suite imports RFC 9500's publicly known RSA-2048 test key through Security, and OpalCrypto validates the resulting `SecKey` capability and performs every cryptographic calculation. The fixture is test-target-only, has no security properties, and is not a substitute for application-owned production key generation or custody evidence. The command fails if either process fails or its shared 7,200-second post-build deadline expires. A timeout requires fixture diagnosis; it does not permit shorter authentication or recovery checks. A pass is package-level deterministic SPI evidence only; it does not prove an application durable backend, live transport, broadcast, value movement, readiness, privacy, or anonymity.

The named private mainnet rehearsal is `./scripts/run-validation-loop.sh mosaic-rehearsal`. It runs exactly the six-contributor conductor completion and contributor exact-commit cases, serially in one SwiftPM process so both purpose-separated real RSABSSA evaluator fixtures are paid once. The conductor case proves authorization issuance and canonical completion publication; the contributor case proves local authorization finalization, BCH signing, exact complete-transaction validation, and one refined-host commit. The host and publication seams are in-memory, OpalFusion has no broadcast callback, and the rehearsal performs no relay contact, wallet access, value movement, or public session construction. It is intentionally slow milestone evidence, not part of the fast feedback lane and not proof of concrete Tor, authenticated mailbox distribution, crash continuation, or live-mainnet readiness. Run it in an environment where Security.framework may create nonpersistent RSA keys; an immediate `authorizationEvaluatorUnavailable` before either test body is a runner precondition failure and should not trigger repeated per-test retries.

`MosaicMainnetAlphaReservationCoordinatorDependencyValidator` is the material-construction-free reservation ownership filter. It proves complete lease equality, unconditional execution-material dependency, exact pre-sign release, and exact-reference recovery after release failure without creating a `LocalContributionMaterial`. Before running it, apply the same static pattern used by the native runner's `validateSourceGuards` in `Tools/Validation/Sources/FusionValidation/Selection.swift`: `requireAuthorizationEvaluators\(|authorizationEvaluator\(|bchSignatureAuthorizationEvaluator\(|AuthorizationEvaluator\.generate\(|ExecutionFixtures?\.prepare\(|LocalContributionMaterial\.build\(|makeLocalContributionMaterial\(|makeMaterializedPreparation\(`. Run it once with `swift test --package-path Tests/Mosaic --skip-build --filter MosaicMainnetAlphaReservationCoordinatorDependencyValidator`; its warm post-build budget is 15 seconds. The existing full-material reservation suite runs in the serialized authorization process selected by the native runner's `mosaicRSASuites`, and contributor-executor coverage retains successful execution, pre-sign release, and post-sign recovery.

The fan-in suite also pins route-to-recipient `p` binding before shared ingress, pre-subscription route drains, multiple stored events plus EOSE buffered without early admission, an exact roster-derived mailbox-group count boundary, and terminal failure when startup input exceeds the shared FIFO.

The current local suite does not replace a live coordinator smoke, reviewed transcript replay, wallet/app integration validation, or host-owned policy checks for coin selection, funding, signing authority, persistence, broadcast, retry behavior, and user-facing fusion controls. Those responsibilities remain separate proof gates or downstream integration concerns.

Use the fast loop to validate package behavior while editing. Use the live smoke and transcript replay path to establish CashFusion interoperability evidence.

## Focused Filters

Use focused filters while iterating on a specific layer:

```bash
swift test --package-path Tests/CashFusion --filter CashFusionPrimaryMessageCodecValidator
swift test --package-path Tests/CashFusion --filter CashFusionCovertMessageCodecValidator
swift test --package-path Tests/CashFusion --filter CashFusionOfficialProtobufFixtureValidator
swift test --package-path Tests/CashFusion --filter RoundEngineScriptedValidator
swift test --package-path Tests/CashFusion --filter PrimaryRuntimeSessionValidator
swift test --package-path Tests/CashFusion --filter LiveRuntimeDriverValidator
swift test --package-path Tests/CashFusion --filter ProductionWorkflowValidator
swift test --package-path Tests/CashFusion --filter ClientSessionValidator
swift test --package-path Tests/Mosaic --filter FusionFacadeScaffoldValidator
swift test --package-path Tests/Mosaic --filter MosaicAttemptCoreValidator
swift test --package-path Tests/Mosaic --filter MosaicRoleElectionValidator
swift test --package-path Tests/Mosaic --filter MosaicManifestAgreementValidator
swift test --package-path Tests/Mosaic --filter MosaicManifestSignatureValidator
swift test --package-path Tests/Mosaic --filter MosaicUnsignedTransactionTranscriptValidator
swift test --package-path Tests/Mosaic --filter MosaicRuntimeSessionValidator
swift test --package-path Tests/Mosaic --filter MosaicRuntimeSessionDriverValidator
swift test --package-path Tests/Mosaic --filter MosaicRuntimeCoordinatorValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaReservationCoordinatorValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaReservationCoordinatorDependencyValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaSigningRequestBuilderValidator
swift test --package-path Tests/Mosaic --filter MosaicPreviousOutputContractValidator
swift test --package-path Tests/Mosaic --filter MosaicSemanticValidator
swift test --package-path Tests/Mosaic --filter MosaicNostrRelayMessageCodecValidator
swift test --package-path Tests/Mosaic --filter MosaicNostrNIP59EnvelopeCodecValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaPostManifestNIP59TransportValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaPostManifestTransportIngressValidator
swift test --package-path Tests/Mosaic --filter PostManifestReplayJournal
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaControlPublicationBridgeValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaPostManifestAnonymousPublicationBridgeValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaPostManifestAnonymousBatchPublisherValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaPostManifestControlBatchPublisherValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaPostManifestPublicationRouteAllocationValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaPostManifestRelayPublisherValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaPostManifestRelayFanInValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaPostManifestRelayFanInRouteValidationValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaPostManifestContributorTransportBridgeValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaPostManifestContributorTransportBridgeConformanceValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaMinimumRosterCompositionValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaPostManifestMailboxRouteProvisioningValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaExecutionGateValidator
swift test --package-path Tests/Mosaic --filter MosaicNIP01RelaySessionValidator
swift test --package-path Tests/Mosaic --filter MosaicOpalV0ProfileValidator
swift test --package-path Tests/Mosaic --filter MosaicOpalV0AuthorizationValidator
swift test --package-path Tests/Mosaic --filter MosaicOpalV0WireContractValidator
swift test --package-path Tests/Mosaic --filter MosaicOpalV0TransportContractValidator
swift test --package-path Tests/Mosaic --filter MosaicHostContractValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaContractValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaContributionFeeValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaAggregateContractValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlpha4MaterialValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaAdmissionLedgerValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaRuntimeSessionValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaBCHCompletionValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaLocalBCHSignatureBuilderValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaContributorExecutorValidator
swift test --package-path Tests/Mosaic --filter MosaicMainnetAlphaConductorCoordinatorValidator
```

Focused filters isolate one layer, but they are not uniformly fast. The `mosaic-fast` wrapper owns the 15-second contributor feedback contract, and the separately guarded `MosaicMainnetAlphaReservationCoordinatorDependencyValidator` owns the 15-second reservation-dependency contract. `MosaicMainnetAlphaMinimumRosterCompositionValidator`, `MosaicMainnetAlphaPostManifestMailboxRouteProvisioningValidator`, and `MosaicMainnetAlphaExecutionGateValidator` are extended RSA-free structural checks; they do not require coordinator credentials, wallet secrets, live UTXOs, Tor, or funded test material, but they have no claim to the focused latency budget. A focused filter that reaches RSA generation, a live wallet or network, a SwiftPM lock retry, or its documented cap must stop for fixture diagnosis instead of widening the budget. `MosaicMainnetAlphaPostManifestContributorTransportBridgeConformanceValidator`, together with every suite named by the native runner's `mosaicRSASuites`, is deterministic but intentionally slow and serialized. The slow filter includes the runtime, admission, conductor, contributor, reservation coordinator, local BCH-signature, anonymous publication bridge, anonymous batch publisher, contributor conformance, contract, and Opal v0 authorization suites so both purpose-separated Security.framework evaluator fixtures are shared in one process.

`./scripts/run-validation-loop.sh mosaic` runs every `Mosaic*` suite followed by `FusionFacadeScaffoldValidator`. Passing it proves only the bounded deterministic conformance and public-scaffold checks described above.

## Live Electron Cash Smoke

The live smoke runner is an opt-in proof gate for a configured Electron Cash `4.4.3`-compatible coordinator environment:

```bash
./scripts/run-electron-cash-interop-smoke.sh --run-count 1
./scripts/run-electron-cash-interop-smoke.sh 3
```

Live coordinator and reviewed transcript proof are deferred during routine maintenance and dependency cleanup. Existing deterministic parser, runtime, and loopback transport checks remain required. The live runner retains its environment and test-registration checks and fails closed when configured proof is unavailable; a routine pass supplies no live or production compatibility claim. Only separately authorized coordinator-backed qualification may enable the interop gate, verify the registered proof identifier, and execute the filtered interop suite. Complete compatibility remains blocked until repeated smoke and reviewed transcript replay evidence exist.

The runner requires `OPALFUSION_EC_*` environment variables and intentionally omits their values from output. Keep coordinator hostnames, ports, wallet material, private keys, scripts, addresses, Tor settings, and raw environment dictionaries out of repo docs and committed artifacts.

## Transcript Capture And Replay Direction

Transcript capture is the bridge from slow live proofing to fast local replay:

```bash
./scripts/run-electron-cash-transcript-capture.sh --output /private/tmp/opalfusion-electron-cash-transcript.swift
```

Use capture only after a configured live smoke actually executes and passes the real coordinator session proof. The capture candidate must be reviewed outside the repository, stripped to approved test-only primary/covert byte fixtures, then committed in a later replay slice. Once replay fixtures exist, they should become the fast Electron Cash compatibility loop, while live smoke remains the slower confidence gate.

## Required Validation By Change

| Change or operation | Required validation |
| --- | --- |
| Documentation and comments | Relevant documentation, relative-link, and structural checks; compile examples when executable usage changes |
| Isolated CashFusion implementation change | `develop` plus affected CashFusion suites, without repeating suites already selected |
| CashFusion transport or lifecycle change | `develop` plus affected integration, cancellation, and recovery suites, without duplicate selection |
| CashFusion cryptography, authentication, protocol bytes, fixtures, or dependency changes | Complete `cashfusion-all` lane |
| Mosaic implementation, cryptography, authentication, protocol bytes, fixtures, or dependency changes | Explicit affected Mosaic checks; complete `mosaic-all` for protocol or cryptographic changes |
| Shared core behavior or shared dependency changes | Complete checks for both engines |
| Public candidate publication | Comprehensive `assurance` / `all` against the exact candidate |

When several rows apply, use the broader requirement. Documentation-only changes do not require the comprehensive suite just because they mention an API or validation command. Runner-only changes require dispatch, discovery, failure, and cleanup checks plus execution of the affected lane. A prior comprehensive pass may be reused only when test sources, dependencies, toolchain, complete selection, and comprehensive execution remain equivalent; a changed comprehensive path requires a new full run. Fast-lane budget failures block that lane's acceptance and require diagnosis, not a larger budget or automatic removal of tests.

- Run the most relevant focused filter first when changing a narrow layer, then complete the applicable checks above.
- Run live smoke only when the goal is coordinator-backed proof and the environment is configured.
- Update [Opal Fusion Specification](opal-fusion-specification.md), [Mosaic Protocol Specification](mosaic-protocol-specification.md), [Mosaic Security Model](mosaic-security-model.md), and any applicable frozen profile such as the [private-deployment supplement](mosaic-mainnet-alpha-private-deployment.md) together when shared boundaries or Mosaic invariants change.
- Update [CashFusion Official Protocol Matrix](cashfusion-official-protocol-matrix.md) when row-level support status or test evidence changes.
- Update [CashFusion Native Swift Support Statement](cashfusion-native-support-statement.md) when the public support claim or remaining proof gates change.
