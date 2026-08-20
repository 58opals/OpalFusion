# Mosaic Mainnet-Alpha Progress

Status date: 2026-08-21. This is a non-normative implementation record; the protocol profile, security model, and private-deployment contract remain authoritative.

## Current Claim

The package-owned private-alpha scope through OpalBase is complete at the injected application boundary. OpalFusion `2dc1adc952975f160cc1eb465e761a081f599afa` preserves one runtime owner across fresh and restored attempts, fixes route identity to the concrete actor for the attempt lifetime, proves cancellation cleanup, and supplies one authoritative serialized private-alpha SPI aggregate. OpalBase `8694c1645fc164b9b3968d5e20f93f3975917310` preserves one wallet-recovery actor, requires every exact selected input before recovered commit intent or wallet mutation, accepts an authenticated committed record as package proof of the downstream absent-input postcondition, and keeps ambiguous pre-commit absence quarantined and fail-closed. OpalCrypto `cc51fc436c95381dfce25fd3f04377d6c29a17f3` supplies the exact RSA private-key restoration primitive. Fusion and Base are fetchable on public `develop`, Base pins the exact Fusion revision through public URLs, and the complete clean public-URL lanes pass. Durable wallet inventory and missing-input tombstones belong to the integrating application, not either package; no application composition is current evidence. Exact results and non-proofs are recorded in the [2026-08-19 package-layer completion checkpoint](mosaic-package-layer-checkpoint-2026-08-19.md).

This is not a live BCH mainnet engine. The packages expose only a macOS private-alpha SPI and injected persistence/transport boundaries; no public Mosaic session, production persistence backend, concrete Tor or relay deployment, application-session composition, external-network broadcast, or release promotion is enabled.

## Completed Slices

| Rank | Slice | Result | Local evidence |
| --- | --- | --- | --- |
| 1 | Minimum-roster composition | Six contributors plus one non-contributing conductor compose through fan-in, ingress, role selection, and shutdown without wallet or RSA signing authority. | `3502472` |
| 2 | Lifecycle ownership | OpalFusion keeps one pending disposition; OpalBase keeps one wallet lifecycle enum and one write-ahead journal authority for release, signing, commit, recovery, and broadcast facts. | `2824ea2`, OpalBase `efc69e1` |
| 3 | Admission replay | One attempt-bound journal records exact accepted gift wraps, original acceptance times, and semantic replay facts before coordinator effects; private-alpha recovery re-authenticates and replays the exact ordered snapshot, while partial or inconsistent state fails closed. | `251a3f0` |
| 4 | Attempt transport provisioning | One peer-local owner provisions mailbox route groups, rejects local capability reuse, and can mint one role-complete inbound provisioning value. | `1fe3380` |
| 5 | Private rehearsal | The explicitly slow real-RSABSSA rehearsal covers conductor authorization and contributor BCH signing through exact host commit without wallet, relay, Tor, node, or broadcast access. | `70ba317` |
| 6 | Private execution gate | Owner provisioning is the sole runtime-construction authority. Fan-in alone requests the one claim, passes its immutable token through ingress to the specialized driver, rejects substitution or reuse, and closes transferred routes after construction failure. Pure route validation and an inert endpoint keep component feedback RSA-free without another runtime constructor. | `6884256`, `7226993` |
| 7 | Exact wallet integration contract | OpalBase accepts only the exact mainnet-alpha.4 profile and transaction-profile identifier pair; a source-compatible future profile fails before wallet or recovered-broadcast mutation. | OpalBase `f2ba606` |
| 8 | Authenticated wallet restart | OpalBase AES-GCM-seals each complete versioned journal snapshot under a caller-owned key and wallet/journal scope, exclusively creates fresh authority, authenticates loaded recovery, re-quarantines exact inputs, and rejects corruption, substitution, incompatible versions, invalid transitions, and uncertain empty restarts. | OpalBase `62af542` |
| 9 | Final authority closure | Compare-and-replace prevents stale overwrite; the sole Base recovery actor owns exact replay, guarded dispatch, chain disposition, quarantine release, and linear erasure authorization, while Fusion terminal evidence remains separate for app-owned composition. | OpalBase `140a951`, OpalFusion `251a3f0` |
| 10 | Private-deployment semantic contract | A separately versioned contract fixes discovery, pre-manifest authority, deadlines, nonce-allocation publication, terminal mappings, and conservative recovery decisions without changing alpha.4 or alpha.5. The exact contract and its limited accountability, admission, relay, and claim posture were accepted for the private alpha on 2026-08-21. | OpalFusion `b5f60b0`; [semantic decision](mosaic-private-deployment-decision-2026-08-21.md) |
| 11 | Complete package recovery boundary | OpalFusion restores signed formation and the existing post-manifest coordinator/runtime around exact companion journals and terminal records. OpalBase restores exactly-once wallet, broadcast, chain, terminal, and cleanup plans through one private-alpha facade without enabling a public session. | OpalFusion `251a3f0`, OpalBase `140a951` |
| 12 | Package-layer completion | The authoritative Fusion SPI aggregate, exhaustive formation-prefix restoration, full repository aggregate, private rehearsal, dependency doctors, and Class D producer promotion all pass at `2dc1adc`; Base `8694c16` pins that exact public revision, fails closed at ambiguous pre-commit missing-input cuts, and passes its build, focused recovery, offline network-target, full local, dependency, static, and Class D promotion gates. | [2026-08-19 checkpoint](mosaic-package-layer-checkpoint-2026-08-19.md) |

## Ownership

| Concern | Authority |
| --- | --- |
| Phase semantics | OpalFusion attempt/runtime reducers and the selected contributor or conductor coordinator. |
| Admission and replay | OpalFusion `AdmissionLedger` plus the post-manifest admission journal for accepted replay facts. |
| Wallet lifecycle | One OpalBase host actor lifecycle; pinned reservation, signing, and commit material are exact operation values rather than parallel lifecycle flags. |
| Durable wallet restart | One OpalBase journal-store actor owns authenticated snapshot and compare-and-replace state. The macOS-only private-alpha facade consumes exact Base and Fusion fresh/recovery capabilities, exposes the sole recovery actor as a replay-only transaction host, and authorizes cleanup only after exact wallet/chain terminal disposition. |
| Durable wallet inventory and tombstones | The integrating application owns one atomic authenticated inventory/tombstone snapshot bound to the outer revision, exact wallet and Fusion identities, selected-input payload, and committed transaction. OpalBase consumes only verified evidence in a future capability; OpalFusion neither sees nor owns wallet disposition. |
| Outbound publication | OpalFusion attempt transport owner, control/anonymous bridges, complete-batch publication journal, batch publishers, and one-shot relay publisher over injected routes. The caller owns the durable backend and authoritative route capabilities. |
| Inbound fan-in | The attempt transport owner issues one role-complete provisioning value and owns its single claim; fan-in, ingress, and the specialized driver consume the resulting immutable token while fan-in owns subscription startup, bounded serialization, failure rollback, and drain. |
| Broadcast release | OpalBase alone turns an exact committed or recovered candidate into one coordinator after security-profile, app-approval, durable-intent, compare-and-replace, and Fulcrum-derived network checks. OpalFusion has no broadcast callback. |
| Cryptography | OpalCrypto supplies BCH, NIP-44, Pedersen, and RSABSSA primitives without phase, wallet, transport, or broadcast authority. |

## Package Boundary Assessment

The dependency direction is acyclic: OpalBase depends on OpalFusion and OpalCrypto, while OpalFusion depends on OpalCrypto and OpalCrypto has no upward dependency. OpalFusion defines protocol state and the narrow host capability contracts; OpalBase implements those contracts with independent wallet validation, authenticated recovery, and guarded broadcast; OpalCrypto remains a computation-focused leaf with no workflow authority.

The dependency boundary remains acyclic and the exact profile pair fails closed. The package-owned recovery implementations and validation closeout are complete: Fusion restores formation, coordinator, admission/publication, reconnect, and protocol terminal evidence; Base restores wallet, guarded broadcast, chain, quarantine, and journal cleanup authority. Producer publication, downstream public pinning, exhaustive Fusion prefix restoration, the serialized SPI aggregate, full package lanes, and the missing-input ownership decision are complete. There is no remaining package-layer closeout item in this scope. Application-owned durable storage, authenticated inventory/tombstones, rollback/deletion detection, cross-process ownership, Keychain lifecycle, state enumeration, outer atomic composition, Tor provisioning, controls, finality policy, physical deletion, and supervision remain deliberately deferred rather than moved into either package.

## Validation Lanes

On Fusion `2dc1adc`, `mosaic-fast` passed 6/6 tests in two suites in 7.786 seconds; the new authoritative `mosaic-private-alpha-spi` lane passed 18/18 in one suite in 3,183.815 seconds, including the unchanged exhaustive formation-prefix case in 1,348.830 seconds; `mosaic-rehearsal` passed 2/2 in 189.662 seconds; and the full aggregate passed 944 tests across 113 suites. On Base `8694c16`, the clean public-URL build passed, focused recovery passed 22/22 in two suites in 14.013 seconds, the network target passed 37/37 in ten suites in 0.003 seconds with every live-network input absent, and the full local target passed 1,036 tests across 108 suites in 241.134 seconds. Dependency doctors, static checks, and both repositories' Class D pre-push and post-push verifiers passed. Exact commands, phase timings, revisions, and non-proofs are recorded in the [2026-08-19 checkpoint](mosaic-package-layer-checkpoint-2026-08-19.md).

The serialized `./scripts/run-validation-loop.sh mosaic-rehearsal` lane remains the intentionally slow milestone proof because it generates two real purpose-separated RSABSSA signing keys. On Fusion `2dc1adc`, it passed 2/2 in 189.662 seconds: conductor completion in 111.738 seconds and contributor exact commit in 77.923 seconds. This proves the internal real-cryptography phase and host-commit path only; it does not contact a wallet, relay, Tor process, BCH node, or broadcaster.

## Hardening Goal Closure

The package-hardening objective is closed at the injected application boundary: exact integration-profile binding, authenticated OpalBase wallet-journal restart primitives, network-attested broadcast-composition primitives, sole-owner lifecycle architecture, route-identity stability, cancellation cleanup, exhaustive aggregate validation, and fail-closed ambiguous-input recovery are complete. This task authorized Class D integration-candidate promotion to public `develop` only. It did not authorize or close any roadmap gate, end-to-end application durability, deployment, release, live-network, value-movement, privacy, or anonymity claim; G0 through G6 remain open.

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

Status: `in progress` as of 2026-08-21. The [Mosaic Private-Deployment.1 Semantic Decision](mosaic-private-deployment-decision-2026-08-21.md) accepts the implemented supplement unchanged for the internal macOS private alpha, including its off-commitment accountability limitation, admission throttle and non-Sybil posture, exact fee and deadline policy, relay restrictions, recovery decisions, and safe-claim boundary. Fusion `2dc1adc952975f160cc1eb465e761a081f599afa`, Base `8694c1645fc164b9b3968d5e20f93f3975917310`, and Crypto `cc51fc436c95381dfce25fd3f04377d6c29a17f3` remain the prior exact fetchable package evidence without changing frozen alpha.4 or alpha.5 bytes. The accepted Fusion revision must now be promoted and consumed through one exact Base and Wallet resolved graph with SwiftFulcrum and OpalDiagnostics, and that complete graph must pass its focused local checks before G0 can close.

Close G0 only after the accepted off-commitment accountability tradeoff or its replacement proof, the Sybil/admission posture and permitted privacy claims, the mainnet fee and deadline policy, and every discovery and pre-manifest document or mapping needed by the private deployment are recorded without implementation-defined gaps. Any decision that changes frozen alpha.4 protocol or alpha.5 transport semantics requires a new profile identifier.

The exact OpalFusion, OpalBase, OpalCrypto, SwiftFulcrum, OpalDiagnostics, and application dependency revisions must then build and pass their focused cross-package contract checks together. Profile drift must fail before wallet, recovery, transport, or broadcast mutation. Validation remains local and no external network or value movement is permitted.

Starting evidence on 2026-08-14 is recorded in [Mosaic Private-Alpha Evidence — 2026-08-14](mosaic-private-alpha-evidence-2026-08-14.md). Inspected OpalBase commit `f6219cad06517924cddb45e9bb9b95c0a6e2e47d` initially resolved OpalFusion to `2e657d6e1ef8b879cfa2f12d5b9f7c08b892d505`, while Wallet commit `543927b36fa4dae839719e7ab356f01ad863220e` resolved an older graph and contained no Mosaic composition. The temporary Wallet task commit `24721909fe901ffe3018cb368690c9536e8128e6` was reversed by `1be8018dc5db9575c2005d56815920bb45b0fc92`; its resulting Wallet tree exactly matches `543927b36fa4dae839719e7ab356f01ad863220e`, so it is historical validation evidence only and not a current dependency or application composition.

### G1 — Durable State And Complete Recovery

Status: `in progress` as of 2026-08-19. Fusion `2dc1adc` restores every signed formation prefix, the existing post-manifest coordinator, exact admission/publication journals, reconnect barriers, and protocol terminal evidence; its authoritative serialized SPI and full repository aggregates pass. Base `8694c16` executes authenticated wallet recovery plans exactly once, reconciles guarded broadcast and chain presence, releases exact-owner quarantine, authorizes nonempty terminal journal erasure, and fails closed when a journal-selected input is absent before authenticated commit completion. Durable missing-input inventory and tombstones are explicitly application-owned, and no production implementation exists. These package capabilities still depend on injected application storage, atomic outer composition, rollback/deletion detection, and supervision, so no G1 closure is claimed.

Close G1 only after an app-owned backend implements exclusive creation, atomic compare-and-replace with file and directory synchronization, Keychain-backed key loading, journal enumeration, cross-process exclusion, and an independent rollback/deletion anchor. The combined recovery contract must restore or conservatively reconcile every required state: OpalFusion owns admission phase, coordinator operations, and publication state, while OpalBase and the application own wallet disposition and chain reconciliation. No layer may construct a fresh runtime around partial state.

The application must compose one stateful attempt-material owner that proves the live reservation lease produced the sealed PlayerCommit, prevents reuse across attempts and retries, persists only the minimum recoverable state, and erases salts, nonces, communication keys, blind-request state, and mailbox identities after terminal disposition.

A fresh process must execute exactly one required wallet or chain reconciliation action at every write-ahead boundary without rebuilding or resigning material. The future application inventory/tombstone capability must be atomic and authenticated with the outer record, exact wallet and Fusion identities, selected-input payload, and committed transaction; missing, unknown, stale, tampered, extra, duplicate, rolled-back, deleted, or outcome-uncertain evidence must fail closed. Validation budget: one RSA-free warm unit filter under 15 seconds and one fresh-process integration filter under 60 seconds; no network access.

### G2 — Concrete Private Discovery And Transport

Status: `in progress` as of 2026-08-21. Fusion `2dc1adc952975f160cc1eb465e761a081f599afa` implements package-owned signed discovery and pre-manifest execution, exact publication continuation, authenticated admission replay, deterministic reconnect, stable concrete-actor route identity, and cancellation-safe route cleanup through injected capabilities. Private-deployment.1 semantics are accepted, but application-owned recipient and mailbox key generation, authenticated distribution, encrypted persistence and erasure, a production durable backend, authoritative endpoint and operator policy, and concrete Tor-only WebSockets with reviewed circuit isolation remain absent, so no G2 closure is claimed.

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
