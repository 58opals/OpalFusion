# Mosaic Mainnet-Alpha Progress

Status date: 2026-08-14. This is a non-normative implementation record; the protocol profile and security model remain authoritative.

## Current Claim

The private scaffold now composes the minimum roster of six contributors and one conductor, preserves one authoritative runtime lifecycle and one authoritative wallet lifecycle, journals semantically admitted replay facts before effects, owns attempt-scoped transport provisioning, pins the exact OpalBase integration profile pair, authenticates durable wallet restart snapshots, and reaches exact in-memory host commit through the real-cryptography rehearsal path. The separately versioned private-deployment.1 contract has freeze-grade canonical evidence, and one exact Wallet dependency composition now builds against the proposed OpalFusion, OpalBase, OpalCrypto, SwiftFulcrum, and OpalDiagnostics revisions. Separate RSA-free filters provide focused construction, lifecycle, recovery, and broadcast-authority feedback.

This is not a live BCH mainnet engine. No public Mosaic session, concrete Tor or relay deployment, durable Mosaic runtime restoration, production Mosaic persistence backend, Mosaic application-session composition, network broadcast, or public-lane promotion is enabled.

## Completed Slices

| Rank | Slice | Result | Local evidence |
| --- | --- | --- | --- |
| 1 | Minimum-roster composition | Six contributors plus one non-contributing conductor compose through fan-in, ingress, role selection, and shutdown without wallet or RSA signing authority. | `3502472` |
| 2 | Lifecycle ownership | OpalFusion keeps one pending disposition; OpalBase keeps one wallet lifecycle enum and one write-ahead journal authority for release, signing, commit, recovery, and broadcast facts. | `2824ea2`, OpalBase `efc69e1` |
| 3 | Admission replay | One attempt-bound journal records only semantically accepted control and anonymous replay facts before coordinator effects; restored partial runtime state fails closed. | `79c366b` |
| 4 | Attempt transport provisioning | One peer-local owner provisions mailbox route groups, rejects local capability reuse, and can mint one role-complete inbound provisioning value. | `1fe3380` |
| 5 | Private rehearsal | The explicitly slow real-RSABSSA rehearsal covers conductor authorization and contributor BCH signing through exact host commit without wallet, relay, Tor, node, or broadcast access. | `70ba317` |
| 6 | Private execution gate | Owner provisioning is the sole runtime-construction authority. Fan-in alone requests the one claim, passes its immutable token through ingress to the specialized driver, rejects substitution or reuse, and closes transferred routes after construction failure. Pure route validation and an inert endpoint keep component feedback RSA-free without another runtime constructor. | `6884256`, `7226993` |
| 7 | Exact wallet integration contract | OpalBase accepts only the exact mainnet-alpha.4 profile and transaction-profile identifier pair; a source-compatible future profile fails before wallet or recovered-broadcast mutation. | OpalBase `f2ba606` |
| 8 | Authenticated wallet restart | OpalBase AES-GCM-seals each complete versioned journal snapshot under a caller-owned key and wallet/journal scope, exclusively creates fresh authority, authenticates loaded recovery, re-quarantines exact inputs, and rejects corruption, substitution, incompatible versions, invalid transitions, and uncertain empty restarts. | OpalBase `62af542` |
| 9 | Final authority closure | Compare-and-replace prevents reentrant or stale journal owners from overwriting newer state; a recovery gate issues one outcome, host candidates share one coordinator claim, every network dispatch persists an exact intent through compare-and-replace, and broadcast network identity derives from the concrete Fulcrum client. | OpalBase `62af542` |
| 10 | Private-deployment contract proposal | A separately versioned contract fixes proposal bytes for discovery, pre-manifest authority, deadlines, nonce-allocation publication, terminal mappings, and conservative recovery decisions without changing alpha.4 or alpha.5; adoption remains pending explicit G0 semantic approval. | OpalFusion `b5f60b0` |
| 11 | Exact application dependency graph | Wallet tracks and builds one exact public-URL lock for OpalBase, OpalFusion, OpalCrypto, SwiftFulcrum, and OpalDiagnostics; app-owned secret erasure and diagnostic privacy compatibility compile and pass focused behavior checks. This is dependency composition, not a Mosaic session. | Wallet `2472190`, OpalFusion `34b1cfc` |

## Ownership

| Concern | Authority |
| --- | --- |
| Phase semantics | OpalFusion attempt/runtime reducers and the selected contributor or conductor coordinator. |
| Admission and replay | OpalFusion `AdmissionLedger` plus the post-manifest admission journal for accepted replay facts. |
| Wallet lifecycle | One OpalBase host actor lifecycle; pinned reservation, signing, and commit material are exact operation values rather than parallel lifecycle flags. |
| Durable wallet restart | One OpalBase journal-store actor owns the authenticated snapshot and compare-and-replace state; one consumed fresh capability constructs a host, while one consumed loaded capability constructs a recovery gate. |
| Outbound publication | OpalFusion attempt transport owner, control/anonymous bridges, batch publishers, and one-shot relay publisher over injected routes. |
| Inbound fan-in | The attempt transport owner issues one role-complete provisioning value and owns its single claim; fan-in, ingress, and the specialized driver consume the resulting immutable token while fan-in owns subscription startup, bounded serialization, failure rollback, and drain. |
| Broadcast release | OpalBase alone turns an exact committed or recovered candidate into one coordinator after security-profile, app-approval, durable-intent, compare-and-replace, and Fulcrum-derived network checks. OpalFusion has no broadcast callback. |
| Cryptography | OpalCrypto supplies BCH, NIP-44, Pedersen, and RSABSSA primitives without phase, wallet, transport, or broadcast authority. |

## Package Boundary Assessment

The dependency direction is acyclic: OpalBase depends on OpalFusion and OpalCrypto, while OpalFusion depends on OpalCrypto and OpalCrypto has no upward dependency. OpalFusion defines protocol state and the narrow host capability contracts; OpalBase implements those contracts with independent wallet validation, authenticated recovery, and guarded broadcast; OpalCrypto remains a computation-focused leaf with no workflow authority.

The boundary shape is sound for a private alpha. The exact cross-repository profile pair now fails closed, OpalBase reconstructs serialized OpalFusion values through their existing constructors and validates the complete journal transition before issuing recovery authority, and no reverse dependency was introduced. OpalFusion's single Swift target still exposes internal types across source files, but no alternate internal constructor can mint the owner request plus claimed runtime token. Remaining work is deployment composition rather than a reason to merge the packages: an app-owned durable backend and rollback anchor, reconciliation executors, concrete Tor/relay adapters, and live network policy stay above these package boundaries.

## Validation Lanes

The focused OpalFusion contributor lane is `./scripts/run-validation-loop.sh mosaic-fast`. It statically rejects evaluator generation, evaluator access, and real-material fixture preparation in the selected route-plan and contributor-lifecycle test sources before running them. Both suites passed inside one warm aggregate in 14.412 seconds on 2026-08-13, within the 15-second post-build budget. The minimum-roster, mailbox-provisioning, and owner-authorized execution-gate suites use only embedded public verification keys and remain separate extended RSA-free structural checks. OpalBase recovery validation is now split across `AccountMosaicAttemptRecoveryPlannerValidator`, `AccountMosaicAttemptJournalValidator`, `AccountMosaicAttemptRecoveryGateValidator`, and `AccountMosaicTransactionBroadcastCoordinatorValidator`; build, discovery, and all four focused filters passed in the bounded no-network lane, with each filter under ten seconds.

The serialized `./scripts/run-validation-loop.sh mosaic-rehearsal` lane remains the intentionally slow milestone proof because it generates two real purpose-separated RSABSSA signing keys. On 2026-08-13 it passed both rehearsals in one process: conductor completion in 191.516 seconds and contributor exact commit in 135.741 seconds, 2/2 in 327.258 seconds. After the bounded ownership roadmap changes, the required one-shot 2026-08-14 rehearsal again passed in one process: conductor completion in 188.344 seconds and contributor exact commit in 132.693 seconds, 2/2 in 321.038 seconds, within the ten-minute cap. A restricted sandbox invocation failed before either test body with `authorizationEvaluatorUnavailable`; the same code passes when Security.framework can create nonpersistent keys outside that sandbox. Treat that fixture error as an environment precondition failure, not a reason to loop individual RSA-heavy filters.

## Hardening Goal Closure

The four previously approved package-hardening gates are closed: exact integration-profile binding, authenticated OpalBase wallet-journal restart primitives, network-attested broadcast-composition primitives, and removal of alternate runtime or duplicated lifecycle authorities. These are component closures, not end-to-end durability, recovery, deployment, or production closure; G0 through G6 remain open. This goal does not authorize or claim live deployment, value movement, public session construction, or public-lane promotion.

## Roadmap Contract

The [Mosaic Protocol Specification](mosaic-protocol-specification.md) owns draft `Mosaic/1` behavior and release gates, the [Mosaic Mainnet-Alpha Profile](mosaic-mainnet-alpha-profile.md) owns the frozen alpha protocol and transport requirements, and the [Mosaic Security Model](mosaic-security-model.md) owns threat assumptions, safe claims, required verification, and security review gates. This implementation record owns only sequencing, status, ownership, and closure evidence; it cannot weaken, waive, or silently reinterpret any authoritative document.

This roadmap targets a private-alpha decision with the public Mosaic session and public release lane still disabled. Public production is a separate horizon governed by P0 through P4 after Gate G6.

The release-gate order is `G0 -> (G1 and G2) -> G3 -> G4 -> G5 -> G6`. Implementation work may overlap, and assurance work should begin as early as practical, but no later gate may close before all of its predecessors close. In particular, independent review and operational readiness in G4 must close before any bounded-value canary in G5, and exact cross-package dependency alignment in G0 must precede integrated app evidence.

Every gate uses one of four statuses: `not started`, `in progress`, `blocked`, or `complete`. A status change must be dated and must identify the exact evidence that changed it. A merged commit, passing unit test, synthetic seam, or in-memory rehearsal does not by itself close a durability, transport, deployment, or live-network gate.

External-network access, value movement, public-lane promotion, tagging, and publication always require their own explicit approval even when the preceding technical gate is complete. If later evidence invalidates an earlier assumption, work returns to the earliest affected gate and every dependent gate reopens.

## Roadmap Ownership

| Surface | Accountable owner | Roadmap responsibility |
| --- | --- | --- |
| Protocol, runtime, and transport semantics | OpalFusion | Canonical pre-manifest contracts, runtime restoration semantics, role execution, relay/mailbox behavior, and fail-closed profile gates. |
| Wallet and broadcast authority | OpalBase | Reservation, signing, authenticated wallet journal, reconciliation execution, network attestation, broadcast approval, and confirmation/reorganization handling. |
| Chain client | SwiftFulcrum | Network-specific node connectivity and chain-query correctness without wallet policy or broadcast-approval authority. |
| Deployment composition | Application | Keychain loading, durable backend, rollback anchor, cross-process exclusion, Tor and relay provisioning, session lifecycle, operator controls, and user policy. |
| Cryptographic primitives | OpalCrypto | Primitive implementation, vector conformance, constant-time behavior, and secret lifecycle. |
| Independent assurance | Reviewers independent of implementation owners | Cryptographic, protocol, side-channel, privacy, wallet-policy, deployment, and safe-claim review with tracked findings closure. |

No gate may close by moving an unresolved responsibility into a lower-level package, a test-only constructor, or an injected capability whose production owner remains undefined.

## Gate Traceability

| Authoritative obligation | Owning gate |
| --- | --- |
| Unresolved alpha contract decisions, discovery documents, policy values, and exact dependency alignment from [Mainnet-Alpha Profile Section 12](mosaic-mainnet-alpha-profile.md#12-remaining-release-gates) | G0 |
| Durable attempt material, runtime restoration, wallet recovery, and secret erasure from Mainnet-Alpha Profile Section 12 | G1 |
| Recipient and mailbox lifecycle, relay policy, concrete Tor execution, acknowledgement persistence, and reconnect from Mainnet-Alpha Profile Section 12 | G2 |
| Authoritative private application composition from Mainnet-Alpha Profile Section 12 | G3 |
| Required simulator, vector, fuzz, multi-device, traffic-analysis, independent-review, and operational evidence from [Security Model Sections 12 and 13](mosaic-security-model.md#12-required-verification) | G4 |
| Transaction-reader selection, broadcast approval and recovery, chain reconciliation, and the separately approved canary | G5 |
| Integrated evidence, residual-risk acceptance, and the private-alpha decision | G6 |
| The complete [`Mosaic/1` release gates](mosaic-protocol-specification.md#18-release-gates-for-mosaic1), public product surface, production operations, staged rollout, and general availability | P0 through P4 |

## Closure Evidence Contract

Each completed gate must record its status date, exact repository commits and resolved dependency revisions, validation commands and execution environment, produced artifacts and results, required external approvals, residual risks, and rollback or disable procedure. The record must also state what the evidence does not prove.

Dependency evidence must cover one exact OpalFusion, OpalBase, OpalCrypto, SwiftFulcrum, OpalDiagnostics, and application composition. Branch-name compatibility or profile-identifier compatibility without exact resolved-revision parity is insufficient for integrated or canary evidence.

## Ranked Private-Alpha Roadmap — In Progress

### G0 — Contract Decisions And Dependency Alignment

Status: `in progress` as of 2026-08-14. OpalFusion implementation revision `b5f60b07ccc1437acc5ec74cede26e49b8319ad7`, carried by exact composition revision `34b1cfcea45cc113fda1287eeca8c5bf6d88830c`, implements the separately versioned [Mosaic Mainnet-Alpha Private-Deployment Profile](mosaic-mainnet-alpha-private-deployment.md) without changing alpha.4 or alpha.5, passes its package-local exact-leaf validation, and has no unresolved internal G0 audit finding. Wallet revision `24721909fe901ffe3018cb368690c9536e8128e6` tracks and passes one exact OpalFusion, OpalBase, OpalCrypto, SwiftFulcrum, OpalDiagnostics, and application build; exact OpalBase validation against that package set also passes `swift build`, the four required focused Mosaic suites with 22 tests, and the full package suite. The starting state, resolved graph, commands, environment, artifacts, internal assurance, non-proofs, residual risks, and disable procedure are recorded in [Mosaic Private-Alpha Evidence — 2026-08-14](mosaic-private-alpha-evidence-2026-08-14.md). Explicit approval of the exact private-deployment.1 semantic decision set remains open; no G0 closure is claimed.

Close G0 only after the accepted off-commitment accountability tradeoff or its replacement proof, the Sybil/admission posture and permitted privacy claims, the mainnet fee and deadline policy, and every discovery and pre-manifest document or mapping needed by the private deployment are recorded without implementation-defined gaps. Any decision that changes frozen alpha.4 protocol or alpha.5 transport semantics requires a new profile identifier.

The exact OpalFusion, OpalBase, OpalCrypto, SwiftFulcrum, OpalDiagnostics, and application dependency revisions must then build and pass their focused cross-package contract checks together. Profile drift must fail before wallet, recovery, transport, or broadcast mutation. Validation remains local and no external network or value movement is permitted.

Starting evidence on 2026-08-14 is recorded in [Mosaic Private-Alpha Evidence — 2026-08-14](mosaic-private-alpha-evidence-2026-08-14.md). Inspected OpalBase commit `f6219cad06517924cddb45e9bb9b95c0a6e2e47d` initially resolved OpalFusion to `2e657d6e1ef8b879cfa2f12d5b9f7c08b892d505`, while Wallet commit `543927b36fa4dae839719e7ab356f01ad863220e` initially resolved an older graph and contained no Mosaic composition. Wallet task commit `24721909fe901ffe3018cb368690c9536e8128e6` supersedes that dependency mismatch with the exact validated local graph, but adds no Mosaic session and has not been merged or published.

### G1 — Durable State And Complete Recovery

Status: `not started`.

Close G1 only after an app-owned backend implements exclusive creation, atomic compare-and-replace with file and directory synchronization, Keychain-backed key loading, journal enumeration, cross-process exclusion, and an independent rollback/deletion anchor. The combined recovery contract must restore or conservatively reconcile every required state: OpalFusion owns admission phase, coordinator operations, and publication state, while OpalBase and the application own wallet disposition and chain reconciliation. No layer may construct a fresh runtime around partial state.

The application must compose one stateful attempt-material owner that proves the live reservation lease produced the sealed PlayerCommit, prevents reuse across attempts and retries, persists only the minimum recoverable state, and erases salts, nonces, communication keys, blind-request state, and mailbox identities after terminal disposition.

A fresh process must execute exactly one required wallet or chain reconciliation action at every write-ahead boundary without rebuilding or resigning material. Missing-input tombstones, uncertain outcomes, stale owners, rollback, deletion, corruption, and cancellation must fail closed. Validation budget: one RSA-free warm unit filter under 15 seconds and one fresh-process integration filter under 60 seconds; no network access.

### G2 — Concrete Private Discovery And Transport

Status: `not started`.

Close G2 only after authenticated recipient-key and mailbox distribution, encrypted persistence and erasure, wrapper-key freshness, authoritative relay selection, endpoint normalization and operator-independence policy, concrete Tor-only WebSocket adapters with reviewed circuit isolation, route-to-capability binding, reconnect, acknowledgement persistence, timing policy, and pre-manifest discovery and sequencing are implemented without a clearnet fallback or second runtime constructor. The deployment must reject relays that require unsupported NIP-42 authentication or proof of work instead of inventing parameters or silently changing the frozen mapping.

The minimum roster must survive disconnect, retry, source loss, bounded drain, and clean shutdown through the production adapters. Validation budget: local loopback under 30 seconds and one no-value staging smoke under five minutes only after separate external-network approval. Staging evidence must state that relay acknowledgements do not prove durable delivery, circuit independence, or anonymity.

### G3 — Private App Session Composition

Status: `not started`.

Close G3 only after one internal application composition binds the exact G0 dependency set, OpalBase wallet and previous-output authority, OpalFusion runtime authority, G1 recovery, and G2 transport through one supervised lifecycle. It must reach exact host commit, route source loss into terminal disposition, and recover cleanly across app restart without exposing another runtime constructor or public Mosaic session.

Validation budget: RSA-free construction under 15 seconds and one serialized real-RSABSSA rehearsal under ten minutes. The composition must not broadcast or move value.

### G4 — Assurance And Operational Readiness

Status: `not started`.

Close G4 only after clean-build and deterministic validation run in repository-owned continuous integration across the exact G0 revisions; canonical encodings, digests, and message types have positive and negative golden vectors; every parser has fuzz coverage; fault injection covers the required simulator failures; repeated multi-device tests and traffic-analysis testing across the supported Tor and relay environments pass; and independent cryptographic, protocol, side-channel, privacy, wallet-policy, and deployment reviews have no unresolved release-blocking findings.

The application must also provide privacy-safe observability, an operational recovery runbook, incident response, a protocol-disable mechanism, conservative wallet UX, and explicit safe-claim review. Review or automation work may begin before G3, but G4 cannot close until reviewers can assess the integrated private session. No external network access or value movement is implied by this gate.

### G5 — Chain Reconciliation And Guarded Mainnet Canary

Status: `not started`.

Close G5 only after persisted approval and broadcast-intent recovery, confirmation and reorganization handling, network attestation, cross-process concurrent-dispatch exclusion, and operator rollback are proven end to end against the exact G0 dependency set and G3 application composition. Deterministic synthetic coverage and an isolated Fulcrum-process integration must pass before any canary is considered.

Before approval, the canary plan must record maximum attempts and total value, exact dependency revisions and endpoints, success and abort thresholds, monitoring and accounting queries, responsible recovery owner, and tested stop and protocol-disable procedures. Validation budget: deterministic synthetic coverage under 30 seconds and one isolated Fulcrum-process integration under five minutes. One bounded-value mainnet canary may run only after G4 is complete and only with separate explicit external-network and value-movement approval. G5 closes only when every attempted input, output, reservation, journal, broadcast, and chain outcome is accounted for and no release-blocking finding remains; a successful canary cannot waive any earlier gate or establish an anonymity claim.

### G6 — Private-Alpha Release Decision

Status: `not started`.

Close G6 only after G0 through G5 are complete and the complete serial validation manifest, exact dependency locks, gate evidence, independent-review dispositions, operational recovery and disable runbooks, canary acceptance record, residual-risk acceptance, and safe public wording pass together. Validation budget: one full serial milestone run capped at 30 minutes plus manual review.

G6 authorizes only a private-alpha decision. The generic mainnet driver, public Mosaic session, public release lane, and production-ready or anonymity claims remain disabled. Merging, pushing, tagging, promotion, publication, or broader rollout requires separate approval.

## Public Production Roadmap — Unscheduled

Private-alpha evidence may inform public production but cannot automatically satisfy it. Work may begin earlier, but the public-production gate order is `G6 -> P0 -> (P1 and P2) -> P3 -> P4`; no generally available public Mosaic session, public-lane promotion, or production-readiness claim is authorized before P4.

### P0 — `Mosaic/1` Protocol Release Candidate

Status: `not started`.

Close P0 only after every release gate in the [Mosaic Protocol Specification](mosaic-protocol-specification.md) and every open item in the [Mosaic Security Model](mosaic-security-model.md) are resolved, the wire and transport schemas and domain values are frozen, positive and negative vectors are portable across independent implementations, any retained on-chain identifier is collision-reviewed, and the compatibility, upgrade, and downgrade policy is documented. Independent review must cover the complete delta from the private-alpha profiles to the proposed release candidate.

### P1 — Public Wallet And Session Surface

Status: `not started`.

Close P1 only after the public OpalBase facade and Mosaic session can be enabled through one deliberate product-owned path with explicit user consent, conservative wallet policy, transaction and fee review, truthful progress and recovery states, accessibility review, safe claims, configuration migration, and no alternate route around reservation, runtime, recovery, or broadcast authority. Public interfaces must remain disabled by default until P3 approval.

### P2 — Production Operations And Supply Chain

Status: `not started`.

Close P2 only after supported relay and Tor topologies have measured capacity and failure envelopes; privacy-safe telemetry, service-level indicators, alerting, incident ownership, support escalation, dependency and key rotation, disaster recovery, protocol-disable drills, and rollback are exercised; and reproducible release artifacts, exact dependency locks, provenance, vulnerability response, and release signing are documented. Load, soak, upgrade, downgrade, multi-device, and adverse-network tests must pass against the production composition.

### P3 — Staged Public Rollout

Status: `not started`.

Close P3 only after a separately approved opt-in rollout progresses through predeclared cohorts, attempt and value caps, success and stop metrics, support coverage, and rollback checkpoints. Every stage must preserve complete fund and journal accounting, publish no unsupported privacy claim, and stop automatically or operationally when a safety, compatibility, privacy, or reliability threshold is crossed.

### P4 — General-Availability Decision

Status: `not started`.

Close P4 only after P0 through P3 are complete, release artifacts and exact revisions match the reviewed composition, no release-blocking security or operational finding remains, residual risks and public claims are approved, support and incident ownership are staffed, and the release owner records the production enablement and rollback decision. Tagging, publication, public-lane promotion, and broader rollout each remain separately approved external changes.
