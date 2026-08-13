# OpalFusion Architecture Complexity Audit

Status date: 2026-08-13. Audit base: private `draft` at `a8975c44e1152fee527e0657c5631ecec7d3de59`. This report records one bounded cleanup; it is not a protocol revision, deployment plan, or live-mainnet readiness claim.

## Verdict

The package direction is sound: OpalCrypto owns reusable cryptographic computation, OpalFusion owns collaborative protocol state and transport semantics, and OpalBase owns wallet reservation, signing, persistence, approval, and broadcast. The dominant complexity is internal to the private Mosaic scaffold, where security boundaries were added faster than obsolete test and constructor seams were removed. This cleanup removes the one alternate outbound route authority and makes the expensive validation lane explicit. CashFusion behavior and public APIs are unchanged.

## Measured Baseline and Result

The base contained 439 production Swift files and 40,552 production lines, including 188 Mosaic files and 26,060 Mosaic lines. Tests contained 306 Swift files and 61,199 lines. The cleanup leaves 40,436 production lines and 61,272 test lines before this report: production decreases by 116 lines while tests grow by 73 lines to construct the real attempt owner instead of bypassing it and to keep malformed mailbox projections covered at that owner boundary. The meaningful reduction is one route-authority enum, one raw dependency initializer, one raw bridge initializer, two bridge-only mailbox errors, and every direct provider branch.

## Ownership Map

| Concern | Authoritative owner | Preserved boundary |
| --- | --- | --- |
| CashFusion protocol execution | `Client.Session`, primary/covert runtimes, and the round engine | Host reservation and transaction assembly remain injected wallet capabilities. |
| Mosaic phase semantics | Attempt/runtime reducers and the selected contributor or conductor coordinator | The generic mainnet-alpha runtime driver remains disabled. |
| Mosaic admission and replay | `AdmissionLedger` plus the accepted-fact journal seam | Only state-consuming authenticated admission is journaled before effects. |
| Outbound route access and claims | One `PostManifestAttemptTransportOwner` per peer and attempt | The owner is the bridge's sole validation gateway; the injected provisioner remains authoritative for raw connections and isolation leases. |
| Outbound publication lifecycle | Control/anonymous bridges, purpose-specific batch publishers, and one-shot relay publishers | Exact attempt, material, recipient, three-route, two-acknowledgement, cancellation, and closure checks remain layered at their semantic boundaries. |
| Inbound fan-in | Attempt owner provisioning, fan-in, ingress, and the specialized driver | One claim authorizes construction; fan-in owns startup, bounded serialization, source loss, and drain. |
| Wallet and broadcast | OpalBase host contracts | OpalFusion exposes no broadcast callback and cannot move BCH. |
| Cryptography | OpalCrypto | OpalFusion retains domain translation and protocol ordering, not key storage or wallet authority. |

## Applied Findings

1. **P1 resolved — alternate contributor route access.** The contributor bridge previously accepted either an attempt owner or direct raw route providers and mailbox values. Only tests used the direct path, but it bypassed the owner's cross-purpose connection and isolation-lease claims. The bridge now derives recipients and both provider closures from one nonoptional owner, while the injected provisioner remains the raw route-capability authority. Tests construct representative owners, and invalid mailbox projections remain covered at the owner boundary before provisioning.
2. **P2 resolved — validation-process ownership.** The slow RSA filter now includes every known suite that reaches real authorization evaluators: runtime, admission, conductor, contributor, local BCH-signature, anonymous publication bridge, anonymous batch publisher, contributor conformance, contract, and Opal v0 authorization. The full and Mosaic wrappers no longer start the contract suite in a separate evaluator-paying process.
3. **P2 resolved — focused feedback contract.** `./scripts/run-validation-loop.sh mosaic-fast` statically rejects evaluator access, evaluator generation, and real-material fixture preparation in its selected sources, then runs only pure route-plan validation and contributor lifecycle coverage. The larger RSA-free composition/provisioning/gate aggregate is intentionally not called the fast lane.

## Deferred Findings and Reopen Signals

1. **P2 — reservation-only coordinator branch.** Reopen only when tests can supply valid full execution material without manufacturing a second publication authority. Stop when the coordinator has one unconditional execution dependency while the explicit actual-lease-versus-material-lease check, pre-sign release, and post-sign recovery behavior remain covered. Budget: build, test discovery, one RSA-free reservation filter under 15 seconds, and diff check; otherwise retain the branch.
2. **P2 — duplicated control and anonymous route-allocation mechanics.** Reopen after publisher fixtures no longer require real evaluator-backed material. Stop after extracting one concrete allocation validator and resource closer while keeping purpose validation and anonymous permit scheduling separate. Budget: both publisher filters in the one serialized RSA process and one focused structural filter; no generic relay workflow.
3. **P2 — admitted facts mirrored by ledger, runtime, and coordinators.** Reopen only on an observed divergence or when one fact class can be removed independently. Stop after the ledger is the sole stored authority for that class and downstream owners retain only operation artifacts. Budget: one fact class and its focused admission/runtime/coordinator filters per change.
4. **P2 — OpalCrypto scalar boundary.** Reopen when OpalCrypto offers the exact additive scalar operation OpalFusion requires. Stop after removing the local scalar implementation with vector parity and no new protocol dependency in OpalCrypto.
5. **P3 — speculative public `Session` and `Mode` names.** Reopen only at an explicit source-breaking release boundary with a concrete public Mosaic composition. Do not add compatibility wrappers or another workflow facade meanwhile.

## Validation Contract

The focused contributor lane has a 15-second warm post-build budget and must remain statically free of `requireAuthorizationEvaluators()`, evaluator access, `AuthorizationEvaluator.generate()`, and real execution-fixture preparation. The real-cryptography path remains `./scripts/run-validation-loop.sh mosaic-rehearsal`, serialized in one process with a ten-minute cap. An evaluator-unavailable precondition, SwiftPM process lock, or focused-lane budget violation stops validation rather than triggering per-test retries. No validation command contacts a relay, Tor process, wallet, or BCH node.

For this cleanup, `swift build` passed in 0.86 seconds after compilation was warm, test discovery passed, the two focused RSA-free suites passed within their 15-second post-build budget, the static fixture guard passed, and `git diff --check` passed. The deterministic `all` wrapper was started once, but the runner did not retain its terminal exit status; it is therefore not claimed as passing and was not retried under the bounded no-loop policy. The existing serialized real-cryptography conformance and rehearsal results remain milestone evidence rather than part of the fast feedback claim.
