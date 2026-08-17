# Mosaic Package-Layer Wrap-Up Checkpoint — 2026-08-17

Status: Package implementation, producer publication, downstream pinning, and the clean public-URL Base lane are complete. This chat is wrapping up with a private-draft test-harness follow-up, but the broader package-engine goal remains paused rather than complete because exhaustive Fusion formation-prefix validation, the combined private-alpha SPI suite, and the missing-input tombstone decision remain open. No roadmap, release, readiness, anonymity, live-network, or value-movement gate is closed.

## Goal

Complete package-owned private-alpha responsibilities through OpalBase while preserving the disabled generic mainnet driver and public Mosaic session. OpalFusion owns private formation, runtime reconstruction, reconnect, protocol terminal handling, and exact package evidence. OpalBase owns exactly-once wallet recovery, guarded broadcast reconciliation, chain observation and reorganization handling, quarantine disposition, and journal-erasure authority. OpalCrypto changes only for a proven primitive.

## Current State

The implementation and dependency sequence described by the [2026-08-15 pre-publication checkpoint](mosaic-package-layer-checkpoint-2026-08-15.md) has landed. OpalCrypto and OpalFusion integration candidates are publicly fetchable on `develop`; OpalBase private `draft` pins those exact public revisions and passes its clean public-URL build and test lane. This wrap-up adds a private-only Fusion test-isolation follow-up that replaces production-like terminal route setup with a narrow test runtime, supports the exact Nostr subscription frames used by fan-in, removes fixture signing-key collisions, and keeps terminal recovery assertions focused on zero-route and no-wait-leak behavior.

The source of truth after this wrap-up is this file plus the exact repository refs below. The 2026-08-15 checkpoint remains a historical record of the pre-publication state and should not be edited to imply that its then-open publication steps were already complete.

## Exact Revisions And Lanes

| Repository | Revision | Final lane state for this chat |
| --- | --- | --- |
| OpalCrypto | `cc51fc436c95381dfce25fd3f04377d6c29a17f3` | RSA signing-key restoration primitive on private `draft` and public `develop`; public `main` remains `9903d6fc6fb90f2a4e8e8a27319db9e2049ae5af`. |
| OpalFusion package source | `251a3f0ca4f8d823d07d526d50b8b61b314a855e` | Private-alpha runtime and recovery implementation. |
| OpalFusion published candidate | `12c45757f2ff5185b31ed14902e3304680576636` | Package source plus the 2026-08-15 checkpoint on private `draft` and public `develop`; public `main` remains `808635ae5db8dcd5abfdbc83347099d6c751d405`. |
| OpalFusion test follow-up | `ed7ec16fdd191fc740521af4a2558621070c1379` | Private-draft-only terminal recovery test isolation and fixture correction; no downstream source dependency requires public promotion. |
| OpalBase | `0483fdc4d043ca792d8ba5a07695136af1a3e6ce` | Recovery source `140a951`, documentation `8bfd7a2`, and exact public dependency pins on private `draft`; public `develop` remains `824df313c82177074a766ccbebb2b5169218aa92` and public `main` remains `606c188fea5a139a178fa38d962c61b80baa3a27`. |

OpalBase `Package.resolved` pins OpalFusion `12c45757f2ff5185b31ed14902e3304680576636` and OpalCrypto `cc51fc436c95381dfce25fd3f04377d6c29a17f3` from their public GitHub URLs. No local path, editable dependency, private URL, credential, or unreachable private revision is committed.

## Decisions And Constraints

- The three Fusion binding fields remain distinct 32-byte `attemptIdentifier`, `generationIdentifier`, and `materialIdentifier` values; Base adds a separate wallet reservation UUID and `UInt64` wallet generation.
- Fusion and Base each retain one lifecycle owner. The deleted Base recovery gate must not return, and recovery must not construct a live host, regenerate material, sign again, or retry an operation in place.
- Persisted exact bytes and exact readback precede every reservation, signing, commit, publication, broadcast, terminal, and cleanup effect. Ambiguous durable cuts reconcile rather than redispatch.
- Restored admission, publication, terminal, mailbox, role, and route metadata must authenticate before any route provisioning. Known terminal recovery uses the package-owned zero-route path.
- Fusion terminal evidence and Base cleanup authority remain separate linear values. An application may compare equal bindings and retain both before physical deletion; neither package independently deletes the other's material.
- `nostr-tor/0-opal-mainnet-alpha-private-deployment.1` remains unapproved. Alpha.4 and alpha.5 frozen bytes remain unchanged.
- OpalBase public `develop`, every repository `main`, all tags, releases, applications, concrete Tor deployment, external Mosaic networks, transaction broadcast, and value movement remain outside this wrap-up.

## Work Completed

### OpalCrypto

- Added the macOS private-alpha RSA signing-key restoration initializer with exact profile, private-operation, and canonical public-key matching checks.
- Published only the required integration candidate; no workflow, recovery, transport, or wallet authority moved into the cryptographic package.

### OpalFusion

- Added the macOS-only private-alpha binding, move-only fresh and recovery handles, signed formation execution and restoration, bounded canonical snapshots, persisted publication continuation, exact admission replay, contributor/conductor reconstruction, deterministic reconnect, write-ahead abort/completion handling, zero-route terminal recovery, and linear terminal evidence.
- Preserved the generic mainnet driver guard and the unconstructible public Mosaic session; no alternate runtime or clearnet fallback was added.
- Added `ed7ec16fdd191fc740521af4a2558621070c1379`, a test-only isolation follow-up. A minimal actor-backed terminal runtime replaces the full contributor coordinator where the assertion concerns terminal replay, scripted connections now acknowledge `EVENT`, `REQ`, and `CLOSE` frames, control-event fixture keys no longer collide with candidate keys, and wrong-phase tests select the exact recognized signer before asserting fail-closed state.

### OpalBase

- Added one private-alpha facade that consumes Fusion and Base fresh or loaded handles, compares recovered bindings before owner construction, returns the Fusion owner with the sole Base live or replay-only transaction host, and rejects profile, network, protocol identifier, wallet UUID, or wallet generation mismatch before mutation.
- Added authenticated journal v2 recovery, reservation crash cuts, signer-free recovered signing-intent abort, byte-identical locally signed continuation, write-ahead and idempotent commit, guarded approval and broadcast intent, tri-state chain observation, confirmation retreat and reorganization handling, exact-owner quarantine release, and linear terminal journal-erasure authorization.
- Deleted the parallel recovery gate and temporary Base-owned Fusion binding. OpalBase public `develop` did not move.

## Major Session Blockers

### Resolved blockers

- Producer/consumer API sequencing: Base mapping began before Fusion had a stable move-only handle and owner contract. Producer-dependent Base mutations stayed frozen until the Fusion boundary stabilized, then the temporary Base binding was removed and direct handle composition was validated.
- Identity conflation: early designs risked collapsing Fusion attempt, generation, and material identity into the wallet reservation generation. The final boundary preserves all five independent values and rejects every one-field substitution before owner or wallet mutation.
- Duplicate lifecycle authority: an intermediate Base recovery gate duplicated ownership. It was deleted; the sole recovery actor now owns replay, release, broadcast, chain, terminal, and erasure transitions.
- Crash ordering: reservation, signing, commit, publication, received terminal events, broadcast, chain disposition, and cleanup all required write-ahead exact bytes plus readback before effects. The final state machines reconcile durable-but-reported-failed cuts without material regeneration or ambiguous redispatch.
- Recovery before routes: the runtime previously risked provisioning transport before authenticating companion state. Restored formation, admission, publication, mailbox, role, and terminal data now validate before route closures, with a zero-route known-terminal path.
- Terminal evidence composition: neither package alone could safely authorize physical deletion. Fusion proves protocol terminal state and drained companion journals; Base proves exact wallet journal and wallet/chain disposition; the application owns atomic composition and deletion.
- Dependency publication and pin honesty: temporary local mirrors were necessary during producer development and repeatedly rewrote downstream resolved state. Required Crypto and Fusion candidates were then published to public `develop`, Base was pinned to those exact public revisions, and the final lane was rerun without mirrors.
- Documentation drift: current architecture, security, validation, and progress documents were reconciled to distinguish implemented private-alpha recovery from still-disabled generic/public and application-owned paths.
- Test harness nontermination ambiguity: large SPI filters were silent long enough to resemble suspended continuations. CPU and phase markers proved expensive canonical signing and re-authentication through nonce allocation, while the terminal follow-up replaced unrelated production coordinator and route setup with a narrow deterministic probe.

### Open blockers and non-proofs

- `restoreSignedFormationPrefixesAndConstructRuntime` is not green. The bounded diagnostic run completed nonce allocation and entered the persisted manifest-agreement prefix at 1,148.994 seconds, then exited 130 before manifest agreement completed. It must finish or be decomposed into independently bounded prefix cases without reducing exact snapshot/reload coverage.
- The combined `MosaicPrivateAlphaRuntimeSPIValidator` suite is not accepted as green. Specifically listed focused slices pass, but a single authoritative aggregate result is still absent.
- Missing-input tombstones remain fail-closed rather than implemented. The next task must decide from the authoritative profile whether the package must persist a tombstone or whether a higher-layer durable inventory is the intended owner; it must not silently treat absence as success.
- No application-owned durable backend, Keychain lifecycle, rollback/deletion anchor, journal enumeration, cross-process exclusion, outer atomic evidence composition, finality policy, physical deletion, lifecycle supervision, controls, or observability was implemented or tested.
- No concrete Tor adapter or route policy, live relay, BCH node, external Mosaic network, transaction broadcast, value movement, canary, independent assurance, release, readiness, Sybil-resistance, or anonymity proof exists.

## Repo State At Wrap-Up

- OpalCrypto and OpalBase were freshly fetched, clean, stash-free, and exactly equal to their private `draft` upstreams before this checkpoint.
- OpalFusion started from private `draft` `12c45757f2ff5185b31ed14902e3304680576636` on the attached continuation branch `wip/mosaic-spi-suite-isolation-20260815-1132`. The test and checkpoint commits were fast-forwarded to local `draft` and pushed only to private `draft` during this wrap-up.
- OpalFusion public `develop`, OpalBase public `develop`, and every public `main` remain unchanged by this wrap-up. No tag or public promotion is authorized or required for the private-only test and documentation follow-up.

## Validation

| Validation | Result |
| --- | --- |
| OpalCrypto focused restoration | 3/3 passed. |
| OpalCrypto related RSA coverage | 7/7 passed. |
| OpalCrypto full package | 372 tests across 51 suites passed. |
| OpalFusion dependency doctor | OpalCrypto resolved, checkout, and public `develop` heads all equal `cc51fc4`; OpalDiagnostics resolved and checkout heads equal `8c42eeb4`; verdicts passed. |
| OpalFusion test target compile after isolation follow-up | Passed with `swift test ... --filter NoSuchFusionTest`; existing unrelated deprecation warnings remain. |
| OpalFusion affected isolation group | 7/7 passed in one suite after 880.936 seconds: exact completion binding, received completion recovery, write-ahead timeout recovery, received-abort reload, invalid authenticated transition, wrong-phase rejection, and exact local publication continuation. |
| OpalFusion `mosaic-fast` | 6/6 tests in 2 suites passed; test time 12.841 seconds and build time 15.27 seconds. |
| OpalFusion `mosaic-rehearsal` | 2/2 tests in 2 suites passed; test time 331.543 seconds. |
| OpalFusion lightweight recovery | 3/3 passed. |
| OpalFusion admission replay | 8/8 passed, including exact order, acceptance time, bytes, duplicates, conflicts, and decoder bounds. |
| OpalFusion received-completion live and loaded recovery | 1/1 passed in 245.053 seconds with previous-output validation and zero route provisioning. |
| OpalFusion oversized publication recovery | 1/1 passed in 5.894 seconds before replay or routes. |
| OpalFusion recovery barrier totality | Passed in 23.682 seconds without a suspended waiter. |
| OpalFusion exhaustive formation-prefix validation | Incomplete at the manifest-agreement prefix; exit 130 after 1,148.994 seconds. |
| OpalBase direct adapter | 7/7 passed, including every Fusion identifier plus wallet UUID and generation mismatch. |
| OpalBase recovery owner | 13/13 passed. |
| OpalBase clean public-URL lane | Build passed; network target 37/37 with live flags disabled; local target 1,034/1,034 across 108 suites passed against Fusion `12c4575` and Crypto `cc51fc4`. |
| Static checks | `git diff --check`, touched Swift filename/header checks, declaration placement, and added force/TODO pattern scans passed for the private follow-up. |

These results prove only the exact deterministic package behavior and dependency graph listed above. They do not close the open blockers or prove application durability, concrete transport, external-network behavior, release readiness, privacy, or anonymity.

## Next Steps

1. Re-route and fetch OpalFusion, OpalBase, and OpalCrypto, then verify private-draft parity and the exact revisions in this checkpoint before new mutations.
2. Decompose `restoreSignedFormationPrefixesAndConstructRuntime` into independently bounded prefix cases or complete it unchanged; preserve exact canonical recovery and do not replace coverage with a single sealed snapshot.
3. Run the complete private-alpha SPI validator only after each bounded group is green, and record an authoritative aggregate result or the exact remaining failing group.
4. Resolve the missing-input tombstone ownership from the authoritative profile and implement it only if it is package-owned; otherwise document the exact injected application capability and fail-closed contract.
5. Re-run `mosaic-fast`, `mosaic-rehearsal` when the covered cryptographic/runtime path changes, dependency doctor, static checks, and the clean public-URL Base lane before any package-completion claim.
6. Keep the generic mainnet driver, public Mosaic session, private-deployment.1 approval, application work, public promotion, main, tags, live network, broadcast, and value movement outside the continuation unless separately authorized.

## Resume Prompt

```text
Resume the package-owned Mosaic private-alpha engine from OpalFusion private draft and read /Users/junecho/Workspace/Git/OpalFusion/docs/mosaic-package-layer-checkpoint-2026-08-17.md plus the active goal objective first. Re-route OpalFusion, OpalBase, and OpalCrypto; verify Fusion private draft contains the test follow-up after 12c45757f2ff5185b31ed14902e3304680576636, Base private draft is 0483fdc4d043ca792d8ba5a07695136af1a3e6ce, Crypto is cc51fc436c95381dfce25fd3f04377d6c29a17f3, and public/main plus Base public/develop are unchanged. First finish or safely decompose restoreSignedFormationPrefixesAndConstructRuntime without weakening exact prefix recovery, then obtain a bounded aggregate SPI result and resolve the missing-input tombstone ownership. Preserve the frozen SPI and alpha.4/alpha.5 bytes, the sole Fusion and Base owners, persist-before-effect ordering, zero-route terminal recovery, disabled generic mainnet driver/public Mosaic session, and the absence of app, external-network, broadcast, value, release, readiness, or anonymity claims.
```
