# Mosaic Package-Layer Completion Checkpoint — 2026-08-19

Status: The authorized package-owned Mosaic private-alpha scope through OpalBase is complete at the injected application boundary. OpalFusion and OpalBase source integration candidates are published on public `develop`, OpalBase pins the exact public Fusion revision, and every required package, dependency, static, and Class D promotion gate passed. This does not close G0 through G6 or any release, readiness, application, live-network, privacy, anonymity, broadcast, or value-movement gate.

## Scope And Outcome

This closeout finishes the bounded package work left open by the [2026-08-17 package-layer wrap-up](mosaic-package-layer-checkpoint-2026-08-17.md): the unchanged exhaustive signed-formation restoration case completed, one tracked serialized private-alpha SPI aggregate passed, the complete Fusion aggregate passed, missing-input tombstone ownership was resolved without adding another package lifecycle owner, Base now fails closed at ambiguous pre-commit absence, and the exact producer-to-consumer public dependency lane passed. The 2026-08-15 and 2026-08-17 checkpoints remain historical records and are not rewritten.

The package boundary is now explicit. OpalFusion owns protocol formation, runtime reconstruction, transport state, reconnect, and protocol terminal evidence. OpalBase owns wallet validation, reservation, signing, commit execution, guarded broadcast composition, chain reconciliation, quarantine, and journal-erasure authorization. The integrating application owns durable wallet inventory and any missing-input tombstone, plus atomic outer composition, rollback and deletion detection, cross-process exclusion, key loading, enumeration, physical deletion, and lifecycle supervision.

## Exact Revisions And Lanes

| Repository | Exact revision | Lane state |
| --- | --- | --- |
| OpalCrypto | `cc51fc436c95381dfce25fd3f04377d6c29a17f3` | Private `draft` and public `develop`; public `main` remains `9903d6fc6fb90f2a4e8e8a27319db9e2049ae5af`. |
| OpalFusion package source | `2dc1adc952975f160cc1eb465e761a081f599afa` | Private `draft` and public `develop` at source publication; this checkpoint is a private-draft-only documentation successor. Public `main` remains `808635ae5db8dcd5abfdbc83347099d6c751d405`. |
| OpalBase | `8694c1645fc164b9b3968d5e20f93f3975917310` | Private `draft` and public `develop`; public `main` remains `606c188fea5a139a178fa38d962c61b80baa3a27`. |

OpalBase `Package.resolved` uses only public GitHub URLs and resolves OpalFusion `2dc1adc952975f160cc1eb465e761a081f599afa`, OpalCrypto `cc51fc436c95381dfce25fd3f04377d6c29a17f3`, OpalDiagnostics `8c42eeb40d64776789e70694e4e5006d2afa400c` through public annotated tag `v0.2.0`, and SwiftFulcrum `66a5a8ba9381b21881ad074d3a8dec3dc473ba0f`. No local path, editable dependency, private URL, credential, or unreachable private revision is committed.

The Class D pre-push and post-push verifiers passed for exact Fusion source `2dc1adc` and exact Base source `8694c16`. These public `develop` refs are integration candidates, not releases. No public `main`, tag, release, application repository, or production configuration moved.

## Missing-Input Ownership Decision

Durable missing-input tombstones and authoritative wallet inventory belong to the integrating application. OpalFusion must never see or own wallet disposition. OpalBase owns the fail-closed interpretation and may consume future application proof only after exact binding verification; this task adds no tombstone store, public API, frozen-SPI expansion, or second recovery owner.

An authenticated Base `.committed` record immediately following the exact matching `.commitIntent` is sufficient package-owned completion evidence that every selected input was removed by the committed wallet operation. That evidence remains valid for broadcast and chain-reconciliation descendants, where selected-input absence is the required postcondition. A `.locallySigned` or `.commitIntent` prefix proves authorization but not wallet-mutation completion. Without injected durable application proof, a missing input at either pre-commit cut produces `walletStateMismatch`, appends no new record, performs no approval, broadcast, chain, finality, or cleanup effect, and retains exact-owner quarantine.

Any future application capability that classifies an input as durably removed by this exact attempt must be one atomic authenticated inventory/tombstone snapshot bound to all of the following:

- The outer attempt-record revision.
- The wallet reservation UUID and wallet generation.
- The distinct Fusion attempt, generation, and material identifiers.
- The exact outpoint and digest of the complete selected-input payload.
- The exact committed transaction hash.

The application must compare-and-replace and read back that evidence with wallet inventory, enumerate it at startup, anchor rollback and deletion detection independently, exclude concurrent processes, and retain it until composed terminal cleanup. Base may accept a `durablyRemovedByThisAttempt` classification only after every binding is exact. Missing, unknown, stale, tampered, substituted, extra, duplicate, rolled-back, deleted, cross-process-conflicted, or outcome-uncertain evidence remains held and fail-closed.

## Package Changes

### OpalFusion

- Added the tracked `mosaic-private-alpha-spi` validation mode, which runs the complete `MosaicPrivateAlphaRuntimeSPIValidator` serially without decomposing or weakening the unchanged nine-member formation fixture, persistence readbacks, reloads, re-authentication steps, or signed prefixes.
- Bound route allocation and fan-in identity to the concrete actor identity captured before existential storage. Successful claimed connections remain alive for the attempt lifetime, preventing object-address reuse from becoming a false route-identity match.
- Added the cancellation probe `waitsForExplicitResumeAfterCancellation` and paired coverage proving wait cancellation, explicit resume, and route cleanup semantics.
- Applied narrow Swift 6.2 inference annotations required by the exact toolchain. Frozen public/private SPI shapes and frozen alpha.4/alpha.5 bytes did not change.

### OpalBase

- Requires every journal-selected input to be exactly present before a recovered locally signed continuation appends `.commitIntent`, before a recovered `.commitIntent` executes wallet commit, and before any selected input is removed.
- Preserves authenticated `.committed` and later recovery semantics: every selected input must be absent, while any present or substituted payload is rejected.
- Adds negative tests for missing input before recovered intent and at recovered commit intent, plus the positive exact-input continuation. The negative cuts leave the journal unchanged and preserve quarantine when the outpoint reappears.
- Documents application ownership of durable inventory/tombstones in the README, architecture, and existing private-alpha journal SPI comments without expanding the SPI.
- Applies narrow Swift 6.2 inference fixes and replaces a zero-time expiry-test yield spin with a bounded asynchronous poll; neither change alters product authority or public API.

## Validation Evidence

All commands used `TOOLCHAINS=com.apple.dt.toolchain.Metal.32023.883`, exact repository-owned SwiftPM cache/config/security paths, and the public dependency graph. Live-network environment inputs were explicitly absent from Base network-target validation.

| Validation | Exact result |
| --- | --- |
| Fusion dependency doctor | OpalCrypto resolved, checkout, and public `develop` all equal `cc51fc436c95381dfce25fd3f04377d6c29a17f3`; OpalDiagnostics resolved and checkout equal public `v0.2.0` target `8c42eeb40d64776789e70694e4e5006d2afa400c`; passed. |
| Fusion build | Passed in 1.29 seconds. |
| Fusion `mosaic-fast` | 6/6 tests in two suites passed in 7.786 seconds. |
| Fusion route-allocation focus | 6/6 passed. |
| Fusion real contributor transport conformance | 11/11 passed. |
| Fusion paired cancellation semantics | 3/3 passed. |
| Fusion `mosaic-private-alpha-spi` | 18/18 tests in one suite passed in 3,183.815 seconds. The unchanged `restoreSignedFormationPrefixesAndConstructRuntime` case passed in 1,348.830 seconds. |
| Fusion `mosaic-rehearsal` | 2/2 passed in 189.662 seconds: conductor completion in 111.738 seconds and contributor exact commit in 77.923 seconds. |
| Fusion full aggregate | 944 tests across 113 suites passed: RSA phase 127/127 across 11 suites in 2,886.357 seconds, material 6/6 in 131.489 seconds, client 35/35 in 8.979 seconds, and bounded remainder 776/776 across 100 suites in 2,650.109 seconds. The unchanged formation case also passed inside this lane in 1,045.591 seconds. |
| Base dependency doctor | OpalFusion exact `2dc1adc952975f160cc1eb465e761a081f599afa`, OpalCrypto exact `cc51fc436c95381dfce25fd3f04377d6c29a17f3`, SwiftFulcrum exact `66a5a8ba9381b21881ad074d3a8dec3dc473ba0f`, and OpalDiagnostics exact `8c42eeb40d64776789e70694e4e5006d2afa400c`; passed. |
| Base build | Passed in 2.64 seconds. |
| Base focused recovery | 22/22 tests in two suites passed in 14.013 seconds: recovery owner 13/13 and runtime adapter 9/9. |
| Base network target | 37/37 tests across ten suites passed in 0.003 seconds with `OPAL_RUN_LIVE_NETWORK_TESTS`, `OPAL_RUN_EXTENDED_LIVE_NETWORK_TESTS`, and `OPAL_FULCRUM_URL` absent; no external call ran. |
| Base full local target | 1,036/1,036 tests across 108 suites passed in 241.134 seconds. |
| Static and boundary checks | Diff checks, Swift filename/header checks, risky-marker scans, public-signature review, public-URL graph review, and placeholder scans passed. |
| Class D publication | Fusion and Base pre-push and post-push verifiers passed exact candidate and public-boundary parity checks. |

## Non-Proofs And Open Roadmap Work

This evidence proves deterministic package behavior and the exact public dependency graph only. It does not implement or prove an application durable backend, Keychain lifecycle, outer atomic Fusion/Base record, wallet inventory/tombstone persistence, rollback/deletion anchor, cross-process exclusion, startup enumeration, physical deletion, app lifecycle supervision, UI or operator controls, or observability.

It does not implement or prove concrete Tor-only WebSockets, relay policy, production recipient/mailbox lifecycle, external Mosaic networking, Fulcrum-process integration, transaction broadcast, chain effects, finality against a live node, value movement, canary operation, independent assurance, release readiness, Sybil resistance, privacy, or anonymity. The generic mainnet driver remains guarded, the public Mosaic session remains unconstructible, and private-deployment.1 remains unapproved. G0, G1, and G2 remain `in progress`; G3 through G6 and P0 through P4 remain unclosed.

## Disable And Rollback Boundary

No product enablement needs rollback because no application composition or public session was enabled. The operative disable boundary remains the absence of an application-provided durable backend, route capabilities, broadcast approval, and public construction path. If a package regression is found, create reviewed forward commits or reverts on the integration-candidate lanes and rerun the same exact dependency, aggregate, and Class D gates; do not rewrite public history, move tags, or weaken frozen profile bytes.

## Continuation

The next work starts above the package boundary: implement and validate the application-owned durable backend and exact inventory/tombstone capability, then compose the exact Fusion/Base terminal evidence under one revision and lifecycle owner. Any external network, live broadcast, value movement, canary, release, `main`, tag, or broader publication action requires a separate explicit authorization and its owning roadmap prerequisites.
