# Mosaic Mainnet-Alpha Progress

Status date: 2026-08-13. This is a non-normative implementation record; the protocol profile and security model remain authoritative.

## Current Claim

The private scaffold now composes the minimum roster of six contributors and one conductor, preserves one authoritative runtime lifecycle and one authoritative wallet lifecycle, journals semantically admitted replay facts before effects, owns attempt-scoped transport provisioning, pins the exact OpalBase integration profile pair, authenticates durable wallet restart snapshots, and reaches exact in-memory host commit through the real-cryptography rehearsal path. Separate RSA-free filters provide focused construction, lifecycle, recovery, and broadcast-authority feedback.

This is not a live BCH mainnet engine. No public Mosaic session, concrete Tor or relay deployment, durable runtime restoration, production app persistence backend, wallet application composition, network broadcast, or public-lane promotion is enabled.

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

The fast OpalFusion structural lane is `swift test --skip-build --filter MosaicMainnetAlphaPostManifestRelayFanInRouteValidationValidator`; it has no dependency on the shared Mosaic mainnet fixture or an authorization evaluator. The owner-authorized `MosaicMainnetAlphaExecutionGateValidator` uses only embedded public verification keys and likewise does not generate RSA signing keys. The fast OpalBase wallet lane is `swift test --skip-build --filter AccountMosaicAttemptRecoveryValidator`; at `62af542` it passed 22 tests in 5.116 seconds after the build and its focused files contain no authorization-evaluator or RSABSSA key-generation call.

The serialized `./scripts/run-validation-loop.sh mosaic-rehearsal` lane remains the intentionally slow milestone proof because it generates two real purpose-separated RSABSSA signing keys. On 2026-08-13 it passed both rehearsals in one process: conductor completion in 191.516 seconds and contributor exact commit in 135.741 seconds, 2/2 in 327.258 seconds. A restricted sandbox invocation failed before either test body with `authorizationEvaluatorUnavailable`; the same commit passed when Security.framework could create nonpersistent keys outside that sandbox. Treat that fixture error as an environment precondition failure, not a reason to loop individual RSA-heavy filters.

## Hardening Goal Closure

The four approved hardening gates are closed: exact integration version binding, authenticated durable wallet recovery, network-attested broadcast composition, and removal of alternate runtime or duplicated lifecycle authorities. This goal stops here. It does not authorize or claim live deployment, value movement, public session construction, or public-lane promotion.

## Ranked Release Roadmap — Not Started

1. App durability and reconciliation composition. Stop when an app-owned backend implements exclusive creation, atomic compare-and-replace with file and directory synchronization, Keychain-backed key loading, journal enumeration, and an independent rollback/deletion anchor, and a fresh process executes exactly one wallet or chain reconciliation action without rebuilding or resigning material. Validation budget: one RSA-free warm unit filter under 15 seconds and one fresh-process integration filter under 60 seconds.
2. Concrete private transport deployment. Stop when authenticated mailbox distribution and concrete Tor/relay adapters carry the minimum roster through disconnect, retry, route drain, and privacy-boundary review without introducing a second runtime constructor. Validation budget: local loopback under 30 seconds; one no-value staging smoke under five minutes only after separate external-network approval.
3. Private app session composition. Stop when one internal app-owned composition binds OpalBase wallet authority, OpalFusion runtime authority, concrete transport, restart recovery, and exact host commit while the generic driver and public session construction remain disabled. Validation budget: RSA-free construction under 15 seconds and one serialized real-RSABSSA rehearsal under ten minutes; no broadcast.
4. Chain reconciliation and guarded mainnet canary. Stop when persisted approval/intent recovery, confirmation and reorganization handling, network attestation, concurrent-dispatch exclusion, and operator rollback are proven end to end. Validation budget: deterministic synthetic coverage under 30 seconds, one isolated Fulcrum-process integration under five minutes, and one explicitly approved bounded-value mainnet canary; no external network access or value movement is implicit.
5. Private-alpha release decision. Stop when the complete serial validation manifest, threat/privacy review, operational recovery runbook, and exact dependency locks pass together and the public lane remains disabled. Validation budget: one full serial milestone run capped at 30 minutes plus manual review; merging, pushing, tagging, or promotion requires separate approval.
