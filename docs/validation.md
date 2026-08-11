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

The generic NIP-59 suite validates both official gift-wrap kinds, independent deterministic inbound identifiers, recipient-tag structure, strict unsigned-rumor coding, wrapper and seal signature order, seal-author binding, wrapper-identity separation, recipient-authentication failure, malformed nested payloads, and allocation limits. Mainnet-alpha.5 validation additionally rejects the superseded alpha.4 transport selector. The transport suite pins a deterministic composite gift-wrap vector, normal rumor kind 78, the exact `d` and `p` tags, regular kind-1059 delivery, 8,192-byte lowercase-hex padding, exact encoded NIP-44 payload-content lengths and JSON ceilings, cover-timestamp bounds, sender/recipient identity, signed-wrapper replay mapping, and driver-owned transport authentication before role-runtime mutation. The ingress suite proves nonempty x-only-distinct attempt-scoped recipient capabilities, exact outer-identity lookup, immutable channel selection, unknown and malformed recipient rejection before runtime mutation, and source/cancellation ordering. It also preserves the changed manifest, acknowledgement, transcript, PlayerCommit, and complete-transaction vectors caused by the manifest-bound alpha.5 transport selector. The control-publication bridge suite proves validated-bootstrap and exact-manifest binding, sealed attempt/generation/material contributor provenance, complete 7–9-member recipient allocation, control/event/mailbox key-role separation, conductor and contributor sequence-zero rules, canonical aggregate fragmentation and reassembly, signed expiry propagation, one recipient-bound wrapper per roster peer, independently signed inner acknowledgements, sender-global sequence continuation, rollback rejection, partial-handoff terminalization, cancellation before and during handoff construction, concurrent-use failure, and terminal no-reuse; the conductor-coordinator suite separately proves exact coordinator-minted attempt, generation, material, and conductor context on every conductor publication. The anonymous-publication bridge suite proves exact runtime, material, and manifest binding; all 23 component gift wraps at mailbox sequence zero; the exact local-input-signature subset at sequence one on the corresponding mailboxes; grouped, component-envelope, signature-envelope, and mailbox identity separation; exact payload round trips; malformed validation, phase-skipping, duplicate, substitution, cancellation, concurrency, and post-terminal rejection; and no state advance after a failed whole-batch callback. That callback is not evidence of route allocation, timing policy, relay delivery, persistence or erasure, semantic loopback, a live Mosaic session, or mainnet execution. The relay-publisher suite validates the frozen outer gift-wrap shape, valid and wrapper-distinct recipient keys, injected manifest-relay-digest endpoint identifiers, exact three-route and distinct-capability construction, byte-identical EVENT frames, all-route handoff before success, accepted-ACK precedence over later route failure, two accepted acknowledgements, impossible-quorum failure, one unavailable route, terminal reuse rejection, and close-draining cancellation over scripted Tor-only capabilities. The relay-fan-in suite validates one shared manifest digest and endpoint set, one control mailbox, contributor control-only routing, roster-bounded conductor anonymous groups, x-only-distinct recipients, globally distinct per-mailbox connections and subscription identifiers, all-group subscription startup before consumption into one runtime, unchanged duplicate EVENT forwarding, EOSE and NOTICE tolerance, fail-fast and cancellation-responsive startup, aggregate-buffer overflow, source-loss terminalization, accepted-FIFO drain, cancellation during ingress startup, and prior queued-runtime terminal precedence. These tests do not prove global remote wrapper-key freshness, production-authenticated recipient allocation or distribution, complete production recipient/mailbox/route allocation, durable sender-sequence or digest merging, recipient-key generation, encrypted persistence or erasure, crash replay, authoritative endpoint selection, endpoint-to-capability binding or operator independence, acknowledgement persistence, reconnect, NIP-42, proof of work, concrete Tor routing or circuit isolation, or relay availability. The transcript-binding contract supports Opal v0 and mainnet-alpha, while the generic `RuntimeSessionDriver` supports only Opal v0 and rejects draft and mainnet-alpha. Passing these suites does not prove production stateful ownership of live reservation material, cross-attempt secret freshness or erasure, app-authoritative previous-output and host composition, durable crash recovery, independent protocol/privacy review, app broadcast approval, or live mainnet execution. The accepted alpha.4 off-commitment vector is evidence of a documented accountability limitation, not a privacy or membership guarantee.

The control-batch publisher suite proves foreign attempt, generation, material, manifest, and recipient-allocation rejection before route provisioning; one complete roster-sized route request keyed only by recipient event identity; manifest, recipient, and coding validation; cross-recipient connection uniqueness; per-recipient byte-identical three-route publication; two accepted acknowledgements for every roster member; all-route closure before success; and cleanup on allocation, quorum, and cancellation failures.

The anonymous-batch publisher suite proves bridge-sealed purpose and material binding; exact component and local-input recipient sets; recipient-only complete route requests; zero permit or event exposure before batch-global route preflight; per-recipient permit gating; cross-recipient connection uniqueness; byte-identical exact-three-route publication; two accepted acknowledgements per sealed wrap; and cleanup on permit, allocation, quorum, publication, and cancellation failures. The injected permits and routes are not evidence of timing privacy, endpoint authority, concrete Tor routing, durable delivery, persistence, retry, semantic loopback, a live Mosaic session, or mainnet execution.

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
swift test --filter MosaicMainnetAlphaControlPublicationBridgeValidator
swift test --filter MosaicMainnetAlphaPostManifestAnonymousPublicationBridgeValidator
swift test --filter MosaicMainnetAlphaPostManifestAnonymousBatchPublisherValidator
swift test --filter MosaicMainnetAlphaPostManifestControlBatchPublisherValidator
swift test --filter MosaicMainnetAlphaPostManifestRelayPublisherValidator
swift test --filter MosaicMainnetAlphaPostManifestRelayFanInValidator
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

Use these as fast feedback loops before running broader validation. They are deterministic and do not require coordinator credentials, wallet secrets, live UTXOs, Tor, or funded test material.

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
