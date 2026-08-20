# Mosaic G1 Closure Evidence — 2026-08-21

Status: G1 complete. This record closes durable application state, fresh-process recovery, and terminal-erasure obligations only. G2 through G6 remain open under [Mosaic Mainnet-Alpha Progress](mosaic-mainnet-alpha-progress.md), and no concrete Tor route, external Mosaic network, application session, broadcast, value movement, release, or public claim is authorized.

## Decision And Scope

Wallet now supplies the production macOS persistence owner that the package layer deliberately left injected. One app-owned authenticated outer record holds the exact OpalFusion recovery snapshot, OpalBase journal envelope or cleanup authority, immutable selected-input inventory, monotonic tombstones, dependency graph, policy identifier, wallet binding, and Fusion attempt, generation, and material binding under one revision. The record cannot carry G2 transport state or G5 broadcast intent at G1.

This gate does not claim the G3 application session exists. Wallet does not yet bootstrap an OpalFusion runtime, invoke a Tor route, or expose a second runtime constructor. OpalFusion and OpalBase continue to own semantic restoration and wallet reconciliation; Wallet owns their durable bytes, exact bindings, startup catalog, rollback or deletion evidence, and physical cleanup. G3 must later prove that one supervised application owner consumes these G1 records and the future G2 transport without constructing a runtime around partial state.

## Exact Resolved Graph

| Repository | Exact revision | Promoted integration lane |
| --- | --- | --- |
| Wallet | `4eb09a88742d3aeb9efa4a56d031ad15458c87ce` | `origin/draft` and `origin/develop` |
| OpalBase | `3eeeb86d41a609f081c1e32e31d0d21ac6ff52e7` | `private/draft` and `public/develop` |
| OpalFusion runtime and dependency graph | `14819481cdc76535bbb89130a96ae5e148dba2e0` | Runtime revision consumed by Wallet; the documentation-only evidence successor is promoted on `private/draft` and `public/develop` |
| OpalCrypto | `8db85b6853c360105f2baf37fc83be48a0ef92da` | `private/draft` and `public/develop` |
| SwiftFulcrum | `24b44bb2458822d14121dfbd57321fda7ae539ea` | `private/draft` and `public/develop` |
| OpalDiagnostics | `7cd2e383309821e01903077c1e534174f9c8a964` | `private/draft` and `public/develop` |

Wallet's tracked Xcode `Package.resolved` pins all five first-party dependencies exactly. OpalBase's tracked `Package.resolved` pins OpalCrypto, OpalFusion, SwiftFulcrum, and OpalDiagnostics at the same revisions. The OpalFusion commit containing this evidence is documentation-only and is not a runtime dependency of Wallet, so it does not create a circular repinning requirement.

## Implemented Recovery Boundary

- OpalCrypto owns AES-256-GCM, HKDF-HMAC-SHA-256, SHA-256, and secure randomness behind facade-owned values and errors. The G1 Mosaic paths in Wallet and OpalBase contain no direct cryptographic calculation dependency above OpalCrypto.
- OpalBase's private-alpha journal uses a purpose-specific derived key, preserves the frozen pre-OpalCrypto version-two envelope fixture, authenticates wallet and journal scope, exposes exact fresh and recovered persistence operations, and authorizes erasure only from package-owned terminal disposition.
- Wallet creates a fresh 32-byte root and independent 32-byte field salt for each attempt, derives purpose-separated outer and journal keys through OpalCrypto, and stores root, salt, and rollback anchor as separate `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` Keychain items.
- Wallet creates attempt files exclusively, performs byte-exact compare-and-replace through a synchronized sibling and atomic rename, synchronizes the file and parent directory, enforces owner-only `0700` and `0600` metadata, rejects links and substituted lock artifacts, and holds a per-scope kernel `flock` across every file and Keychain transaction.
- The independent Keychain anchor records pending replacement, committed, deleting, and terminal states. Recovery accepts only the exact old-file or new-file pending transition, resolves outcome uncertainty by exact readback, detects rollback or deletion, resumes authorized cleanup from every deletion boundary, and removes the final anchor only after OpalBase confirms outer absence.
- Startup catalogs Keychain and filesystem state in both directions. Malformed, missing, extra, duplicated, misnamed, stale, tampered, rolled-back, or deleted attempt evidence becomes an explicit absence, recovery, or quarantine result; unknown catalog artifacts are counted separately and make the aggregate fail closed. No such evidence is converted into a fresh runtime or regenerated material.
- Selected inputs remain immutable, their canonical digest is authenticated by the outer record, and tombstones are monotonic and bound to the exact outpoint, input digest, disposition, and committed transaction hash when spent.

## Environment

- Apple Silicon Mac running macOS 27.0 build `26A5416b`.
- Xcode 27.0 build `27A5237l` from `/Applications/Xcode-beta.app/Contents/Developer` with Apple Swift 6.4 and the matching Metal Toolchain.
- All package and Wallet validation was local except ordinary Git reads needed to retrieve the exact recorded dependency commits. No Tor process, Mosaic relay, Fulcrum service, transaction reader, broadcaster, credential, or value-moving endpoint was used.

## Commands And Results

From exact OpalCrypto `8db85b6853c360105f2baf37fc83be48a0ef92da`:

```text
swift test --only-use-versions-from-resolved-file --filter 'PublicAPIAuthenticatedEncryptionValidator|PublicAPIKeyDerivationValidator'
```

Result: 17 tests in two suites passed in 0.002 seconds after a 12.98-second exact-lock build. The suite includes the NIST AES-256-GCM authenticated-data vector, authentication and size failures, key and nonce redaction, RFC 5869 HKDF vectors and bounds, and existing PBKDF2 facade coverage. A preceding warm-cache-only attempt failed before compilation because the local SwiftPM Git object store did not contain the already-pinned OpalDiagnostics commit; exact-lock resolution fetched that recorded commit, changed no source or lock file, and the rerun passed.

From exact OpalBase `3eeeb86d41a609f081c1e32e31d0d21ac6ff52e7`:

```text
swift test --only-use-versions-from-resolved-file --filter 'AccountMosaicAttemptJournalValidator|AccountMosaicPrivateAlphaJournalCreationRecoveryValidator|AccountMosaicPrivateAlphaJournalRecoveryValidator|AccountMosaicPrivateAlphaJournalCleanupValidator|AccountMosaicPrivateAlphaRecoveryOwnerValidator|AccountMosaicPrivateAlphaRuntimeAdapterValidator'
```

Result: 33 tests in six suites passed in 7.735 seconds after the first 64.92-second exact-lock build. The fetched checkouts resolved OpalCrypto `8db85b6`, OpalFusion `1481948`, SwiftFulcrum `24b44bb`, and OpalDiagnostics `7cd2e38`. Coverage includes frozen journal compatibility, authenticated fresh creation and recovery, exact binding rejection, wallet reconciliation cuts, linear cleanup authority, fresh-input reload, and terminal cleanup without reconstructing the journal key. No live-network test was selected.

From exact Wallet `4eb09a88742d3aeb9efa4a56d031ad15458c87ce`, the ordinary signed macOS scheme lane used the tracked lock and existing exact checkouts:

```text
xcodebuild -project Wallet.xcodeproj -scheme Wallet -destination 'platform=macOS' -derivedDataPath .codex-cache/DerivedData -clonedSourcePackagesDirPath .codex-cache/SourcePackages -packageCachePath .codex-cache/PackageCache -disablePackageRepositoryCache -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates -skipPackagePluginValidation test -only-testing:WalletTests/MosaicPrivateAlphaRecordCodecValidator -only-testing:WalletTests/MosaicPrivateAlphaPersistenceActorValidator -only-testing:WalletTests/MosaicPrivateAlphaAttemptRepositoryValidator -only-testing:WalletTests/MosaicPrivateAlphaFileClientValidator -only-testing:WalletTests/MosaicPrivateAlphaKeyClientValidator
```

Result: 38 tests across five suites passed. This covers canonical authenticated records, graph and policy binding, G1 transport-field exclusion, exclusive creation and compare-and-replace, injected pre-commit and commit-then-error faults, old-file and new-file pending recovery, every authorized deletion boundary, unknown evidence refusal, OpalBase cleanup integration, filesystem hardening, independent file clients, and the live Keychain lifecycle.

The repository-owned standalone process lane then built the same signed test products and ran the parent suite under the standalone macOS `xctest` runner:

```text
./scripts/run-mosaic-g1-fresh-process.sh --repo-root "$PWD"
```

Result: two orchestrator tests passed in 7.192 seconds. Fifteen scenarios each used a distinct prepare process and recovery process over the production file and live Keychain clients. They covered committed state; root-only, complete-secret, pending-anchor, and pending-envelope creation cuts; old-envelope and new-envelope replacement cuts; deletion and missing-key quarantine; rollback detection; every deleting cut; durable terminal authority; exact OpalBase completion; and physical absence. A separate child process remained blocked on the production scope `flock` until the parent released it. The specialized suite is explicitly skipped inside the sandboxed Wallet application test host, which cannot launch child test runners; the standalone script is the required execution lane rather than a passing synthetic substitute.

The Wallet macOS production build and generic iOS build passed at the implementation parent `78f216b8a2321e7a5f287cb36061406dffa4df11`; the final `4eb09a88` follow-up changes only tests, the validation script, and this evidence wording, and its `build-for-testing` step recompiles the final exact production graph. Role-first structure, intent-capability boundaries, plan metadata, shell syntax, whitespace, prohibited production crypto or transport surfaces, exact resolved checkout parity, and remote integration-head parity passed. Wallet `draft`, `develop`, their remote refs, and the published G1 task ref all equal `4eb09a88742d3aeb9efa4a56d031ad15458c87ce`.

## Closure Findings

- The production owner missing at package closeout now exists in Wallet and is compiled against one exact first-party graph.
- The complete G1 outer state is authenticated and replaced atomically under one revision; separate Fusion and Base files cannot be mistaken for an atomic attempt.
- Keychain and filesystem changes are intentionally not described as one hardware transaction. The four anchor phases enumerate the permitted crash states, exact readback resolves uncertainty, and every other state fails closed.
- A new operating-system process can enumerate, recover, quarantine, resume deletion, reload OpalBase cleanup authority, and complete physical erasure without rebuilding or resigning attempt material.
- OpalFusion and OpalBase restoration remain the semantic authorities. Wallet preserves and binds their state without parsing or weakening it, and the absence of a Wallet runtime constructor prevents partial state from starting a session before G3.
- G1 therefore satisfies its durable backend, exact state, rollback/deletion, cross-process, restart, inventory/tombstone, and erasure requirements without enabling G2 transport or G3 composition.

## Approvals And Promotion

The repository owner explicitly authorized direct work in the existing Opal repositories, commits, pushes, and validated `draft -> develop` promotion for this Mosaic goal. OpalCrypto, OpalBase, and Wallet were promoted through those authorized lanes after validation. No `main` promotion, tag, release, new repository, external production dependency, public feature enablement, deployment publication, paid operation, credential use, external Mosaic networking, broadcast, value movement, or canary was authorized or performed.

## Residual Risks And Disable Procedure

The Keychain anchor and synchronized file are independent storage systems, so power loss and operating-system failures can still produce a quarantined attempt that requires operator review; the implementation never guesses across such evidence. Physical overwrite of copy-on-write or flash storage is not claimed. `WhenUnlockedThisDeviceOnly` makes recovery intentionally device-local and unavailable while the Keychain is locked. The current schema rejects G2 transport state and G5 broadcast intent; later gates must extend the record without weakening G1 compatibility, authentication, or cleanup.

Disable remains structural. Wallet has no Mosaic bootstrap composition or public session, the generic mainnet driver still rejects the profile, and no route or broadcaster configuration exists. If G1 evidence is invalidated, keep Mosaic disabled, preserve affected records and Keychain anchors for conservative recovery, quarantine uncertain wallet inputs, revert or forward-fix through the integration lanes, and rerun the exact producer, Wallet, and fresh-process lanes before reopening G1. Erase state only after OpalBase-authorized terminal disposition and verified outer absence.

## Non-Proofs

This record does not prove a live OpalFusion runtime restore, a supervised Wallet Mosaic session, a live reservation-to-PlayerCommit execution, Tor routing, DNS or clearnet exclusion, circuit or operator independence, relay delivery, authenticated recipient-key distribution, transport timing privacy, external chain reconciliation, broadcast safety, canary safety, multi-device reliability, independent review, anonymity, Sybil resistance, production readiness, public release readiness, or G2 through G6 closure. Package recovery tests plus application durability are not represented as an integrated G3 rehearsal; that separate gate remains mandatory.
