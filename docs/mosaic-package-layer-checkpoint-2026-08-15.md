# Mosaic Package-Layer Checkpoint — 2026-08-15

Status: The package-owned Mosaic private-alpha engine implementation is committed on isolated OpalFusion and OpalBase task branches. OpalBase is fully green in the local three-package lane. OpalFusion builds, its repository-native fast and rehearsal gates and the specifically listed focused recovery, replay, publication, and terminal cases pass, but its combined private-alpha SPI suite, exhaustive formation-prefix validation, and final public-only publication sequence remain incomplete. No roadmap, release, readiness, or anonymity gate is closed.

## Goal

Complete package-owned private-alpha responsibilities through OpalBase without enabling the generic mainnet driver or public Mosaic session. OpalFusion owns private formation, runtime reconstruction, reconnect, protocol terminal handling, and exact package evidence. OpalBase owns exactly-once wallet recovery, guarded broadcast reconciliation, chain observation and reorganization handling, quarantine disposition, and journal-erasure authority. OpalCrypto changes only when a concrete primitive is required.

## Exact Implementation Revisions

| Repository | Revision | Checkpoint state |
| --- | --- | --- |
| OpalCrypto | `cc51fc436c95381dfce25fd3f04377d6c29a17f3` | RSA signing-key restoration primitive committed and published to private `draft` and public `develop`; public `main` unchanged. |
| OpalFusion | `251a3f0ca4f8d823d07d526d50b8b61b314a855e` | Private-alpha runtime/recovery source and tests committed on `wip/mosaic-recovery-runtime-20260815-0105`; landing and publication were pending when this checkpoint was authored. |
| OpalBase | `140a951e92c94589e5edf1e24589dbeb4d206766` | Wallet/recovery/chain implementation and direct Fusion adapter committed on `wip/mosaic-package-engine-20260815-0107`; the tracked lock still points to the older public Fusion revision pending producer publication. |

The source commits above are the exact inputs to the requested Class D landing. Live remote refs, post-push parity, and downstream pins must be re-read rather than inferred from this pre-publication record.

## Work Completed

### OpalCrypto

- Added the macOS private-alpha RSA signing-key restoration initializer that requires an RSA private key, the expected blind-signature profile, successful raw private operation, and an exact canonical public-key match.
- Kept workflow, persistence, recovery, and terminal authority out of the cryptographic leaf package.

### OpalFusion

- Added a macOS-only `@_spi(MosaicPrivateAlpha)` boundary with one three-identifier `Binding`, move-only `FreshAttempt`, `LoadedRecovery`, and `TerminalEvidence`, and one actor owner for fresh and restored protocol transitions.
- Added signed local pre-manifest formation and restoration for discovery, candidate-set agreement, admission, role commitments and reveals, nonce allocation, manifest proposal and signatures, package-derived aborts, duplicates, equivocation, invalid authenticated transitions, and timeout authority.
- Added canonical bounded recovery snapshots, exact compare-and-readback transitions, one-shot persisted publication, and restoration code for every recorded formation prefix without a caller-supplied proof jump.
- Added contributor and conductor post-manifest construction over the existing runtime/coordinator path, including exact SecKey restoration, mailbox and relay capability validation, admission replay, publication continuation, deterministic reconnect barriers, and terminal no-route reconstruction.
- Added write-ahead received abort, local timeout, and received completion records; exact terminal predecessor validation; drained admission/publication evidence; and linear terminal evidence that deliberately carries no Base wallet or deletion authority.
- Preserved the structural disable: `.opalMainnetAlpha` still fails the generic `RuntimeSessionDriver` capability guard, and no public Mosaic session or alternate runtime constructor was introduced.

### OpalBase

- Replaced the temporary recovery gate with the sole `MosaicPrivateAlphaRecoveryOwner`; its lifecycle owns deterministic replay, wallet reconciliation, broadcast, chain, terminal, and erasure transitions without creating a second wallet owner.
- Added journal v2 binding three independent Fusion identifiers plus a separate wallet UUID and `UInt64` generation. Fresh reservation preparation is durable before wallet mutation; legacy intent remains decode-only and cannot become a later approved dispatch.
- Added deterministic reservation crash-cut recovery, exact input/output/script/public-key validation, signer-free recovery of signing intent, byte-identical locally signed continuation, write-ahead complete commit, idempotent post-commit replay, exact-owner quarantine release, and linear journal-erasure authorization.
- Added exact ambiguous-broadcast presence reconciliation, persisted approval and intent, at-most-one dispatch, tri-state chain presence, repeated observation idempotence, confirmation advance and retreat, block replacement, disappearance, wrong-network and malformed-metadata holds, and app-authorized finality over the latest exact confirmed identity.
- Added a direct Fusion adapter that consumes both move-only handles, derives one cross-package binding before mutation, retains the Fusion owner, and exposes the same Base recovery actor as a replay-only `MosaicCompleteTransactionHost`. Historical terminal replay returns only authenticated lease/signature/commit results and cannot reopen wallet state.

## Major Session Blockers

### Resolved engineering blockers

- Producer/consumer contract sequencing: Base mapping began before Fusion had a stable handle and owner API. Base producer-dependent edits remained frozen until Fusion exposed direct `Binding`, `FreshAttempt`, `LoadedRecovery`, owner, construction, and terminal-evidence contracts. The final adapter consumes those types directly; the temporary Base binding was deleted.
- Identity conflation: early designs risked treating attempt identity, Fusion generation/material identity, and wallet reservation generation as one value. The final contract keeps three independent 32-byte Fusion identifiers plus a separate wallet UUID and wallet generation, with mismatch rejection before owner construction or wallet mutation.
- Duplicate lifecycle authority: an intermediate Base recovery gate duplicated ownership. It was removed, committed candidate authorization now requires the isolated sole recovery actor, and direct Fusion replay uses that same actor rather than a live-host retry or second owner.
- Crash ordering across package boundaries: reservation, signing, commit, broadcast, terminal publication, received abort/completion, and cleanup each required an exact write-ahead/readback boundary. The implementation now persists the authenticated operation before effects and reconciles durable-but-reported-failed cuts without regenerating material or redispatching ambiguously.
- Recovery before route provisioning: restored admission bytes, original acceptance times, mailbox capabilities, role/cardinality, and companion journals had to be authenticated before any Tor route closure could run. Construction now performs that pure preflight first and selects a package-minted zero-route path for known terminal recovery.
- Terminal authority composition: neither package could safely authorize deletion alone. Fusion terminal evidence proves signed protocol terminal state plus drained companion journals; Base cleanup authority proves the exact encrypted wallet journal and chain/wallet disposition. The application must retain and compare both equal bindings before physical deletion.
- SwiftPM local-lane mutation: editable local mirrors repeatedly caused SwiftPM to remove mirrored Fusion/Crypto pins from Base `Package.resolved`. Every temporary rewrite was restored, and no local path, private URL, or removed-pin artifact entered the Base source commit.
- Documentation drift: front-door Fusion and Base documents still described nonempty admission recovery, wallet recovery execution, chain reconciliation, and terminal cleanup as unavailable. The checkpoint, architecture, security, progress, audit, and README surfaces were reconciled to the implemented ownership while preserving the unpublished, application-owned, and live-network non-proofs.

### Remaining package and validation blockers

- The exhaustive `restoreSignedFormationPrefixesAndConstructRuntime` test performs cumulative canonical signature verification after every accepted prefix. A diagnostic run proved forward progress through nonce allocation at 1,148.994 seconds and entered the persisted manifest-agreement prefix, then was stopped with exit 130 for a user-requested checkpoint before manifest agreement completed. It is not a passing result and must be completed or safely decomposed without weakening prefix coverage.
- The combined private-alpha SPI suite was not accepted as green. Its earlier silent aggregate runs were stopped to distinguish fixture cost from a continuation leak; phase markers showed deterministic computation rather than a leak through nonce, but the manifest and final construction portion remains unproved by that run.
- OpalFusion's `mosaic-fast` and `mosaic-rehearsal` gates pass on the exact source commit, but Class D public-boundary and promotion checks remain before its revision can be treated as the fetchable producer candidate.
- OpalBase `Package.resolved` still pins Fusion `2e657d6e1ef8b879cfa2f12d5b9f7c08b892d505` and Crypto `cdbadf398bcfdb0d9a3c7cd655a0f65089337f80`. Its full adapter evidence used a temporary local mirror; default-lane and public-only proof require public Fusion publication followed by an honest lock refresh to exact fetchable revisions.

### Deliberately deferred non-blockers

- Application-owned durable storage, Keychain integration, rollback/deletion anchors, cross-process exclusion, journal enumeration, outer atomic composition, lifecycle supervision, finality policy, physical deletion, controls, and observability remain outside package scope.
- Concrete Tor provisioning, relay/operator independence, live network execution, actual transaction broadcast, value movement, canaries, independent assurance, and releases remain separate gates.
- `nostr-tor/0-opal-mainnet-alpha-private-deployment.1` remains unapproved. The package implementation does not manufacture G0 semantic approval or establish anonymity, Sybil resistance, readiness, or permission to use real funds.

## Validation Evidence

| Validation | Result |
| --- | --- |
| OpalCrypto focused restoration | 3/3 passed. |
| OpalCrypto related RSA coverage | 7/7 passed. |
| OpalCrypto full package | 372 tests across 51 suites passed. |
| OpalFusion production build | Passed repeatedly on the frozen SPI. |
| OpalFusion `mosaic-fast` | 6/6 tests in 2 suites passed; test time 12.841 seconds and build time 15.27 seconds. |
| OpalFusion `mosaic-rehearsal` | 2/2 tests in 2 suites passed; test time 331.543 seconds and build time 0.55 seconds. |
| OpalFusion lightweight runtime recovery | 3/3 passed. |
| OpalFusion admission replay journal | 8/8 passed, including exact order/time/bytes and decoder bounds. |
| OpalFusion received-completion live and loaded recovery | 1/1 passed in 245.053 seconds with exact previous-output validation and zero route provisioning. |
| OpalFusion oversized publication recovery | 1/1 passed in 5.894 seconds before replay or route work. |
| OpalFusion recovery-barrier failure totality | Passed in 23.682 seconds without a suspended waiter. |
| OpalFusion exhaustive formation-prefix validation | Incomplete: progressed through nonce allocation at 1,148.994 seconds and entered the persisted manifest-agreement prefix; stopped by request before agreement completed. |
| OpalBase focused direct adapter | 7/7 passed, including all three Fusion identifiers plus wallet UUID/generation mismatch cases. |
| OpalBase focused recovery owner | 13/13 passed. |
| OpalBase full package in the temporary Fusion/Crypto lane | Network 37/37 and local 1,034/1,034 across 108 suites passed. |
| Static checks | `git diff --check`, touched Swift filename/header checks, declaration-placement checks, and added unsafe/TODO pattern scans passed before the source commits. |

This evidence proves package implementation behavior only at the listed revisions and lanes. It does not prove public dependency fetchability for Base, application durability, concrete Tor behavior, external-network behavior, release readiness, anonymity, or independent assurance.

## Decisions And Constraints

- Source mutation and landing use Class D `draft`; OpalFusion and OpalCrypto may publish explicitly identified integration candidates to public `develop`. OpalBase remains private `draft` and its public `develop` must not move.
- Non-`main` pushes are authorized when necessary for this task. No repository `main` may move.
- Alpha.4 protocol and alpha.5 post-manifest transport bytes remain unchanged.
- No application repository, SwiftFulcrum, OpalDiagnostics, external Mosaic network, broadcast, value movement, tag, release, or production/readiness claim is in scope.

## Next Steps

1. Complete bounded OpalFusion validation, preserving the frozen SPI and reporting the exhaustive formation-prefix gap exactly if it remains incomplete.
2. Recheck `private/draft`, land the exact Fusion task commits, push private `draft`, run the Class D verifier, and publish only a verified public `develop` integration candidate.
3. Refresh Base only from the fetchable public Fusion and Crypto revisions, run dependency-doctor and the default/public-only build and test lane, then land and push Base private `draft` without moving Base public `develop`.
4. Run the disposable exact three-package public-only lane with tracked public URLs and no local substitutions.
5. Re-audit API, naming, concurrency, security, complexity, documentation consistency, disabled public entry points, and unchanged frozen vectors before declaring the package goal complete.

## Resume Prompt

```text
Resume the package-owned Mosaic private-alpha engine from this checkpoint. Read the goal objective and this file first, then re-route and fetch OpalFusion, OpalBase, and OpalCrypto. Preserve OpalFusion 251a3f0ca4f8d823d07d526d50b8b61b314a855e, OpalBase 140a951e92c94589e5edf1e24589dbeb4d206766, and published OpalCrypto cc51fc436c95381dfce25fd3f04377d6c29a17f3 unless a reviewed follow-up commit supersedes them. Finish the incomplete Fusion validation without changing the frozen SPI, publish only non-main lanes, refresh Base to exact public pins, and prove the final public-only graph. Keep the generic mainnet driver and public Mosaic session disabled, keep private-deployment.1 unapproved, do not touch an app repository or main, and make no readiness or anonymity claim.
```
