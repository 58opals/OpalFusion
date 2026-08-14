# Mosaic Package-Layer Checkpoint — 2026-08-15

Status: Package-only implementation is paused at clean local/private `draft` parity and is ready for the next package work session. No roadmap gate is complete.

## Goal

Continue Mosaic private-alpha work only through OpalBase, OpalFusion, and OpalCrypto. Preserve the disabled generic mainnet driver and public Mosaic session. Application persistence, Keychain, Tor provisioning, lifecycle, controls, and product policy are explicitly deferred to a later Wallet-repository session.

## Current State

OpalFusion and OpalBase package commits were fast-forwarded onto their local Class D `draft` branches after a fresh `private/draft` fetch and ahead-only landing check, then pushed by explicit approval to their `private/draft` branches. OpalCrypto was already at exact local and private draft parity and its explicit push was a no-op. The prescribed post-push checks verified clean `0/0` local/private parity in all three repositories. No public lane moved, no application repository was landed, and no external Mosaic network or value-moving operation ran.

| Repository | Published package revision | State after publication |
| --- | --- | --- |
| OpalFusion | Implementation `37266a4f6da86289c5042e8b4c081125a2310953`; package checkpoint `be503b4320863cace0208d872b00c15ea8211994`; this document's containing revision adds only the publication-status follow-up | Local `draft` and `private/draft` exact; clean. |
| OpalBase | `af1007dbe5d35a5f65d6ed90f56801519b7e70b0` | Local `draft` and `private/draft` exact; clean. |
| OpalCrypto | `e4886e2fdf2c4c25fa3ae7eead576dfd87cb4fb2` | Local `draft` and `private/draft` exact; clean. |

The earlier Wallet task commit `24721909fe901ffe3018cb368690c9536e8128e6` was reversed by local task-branch commit `1be8018dc5db9575c2005d56815920bb45b0fc92`. The resulting Wallet tree exactly matches its original `543927b36fa4dae839719e7ab356f01ad863220e` baseline. Untracked Wallet Mosaic drafts were removed and are not recoverable from Git. Wallet is not current evidence and must not be touched in the next package-only session.

## Decisions And Constraints

- The active scope is OpalBase, OpalFusion, and OpalCrypto only. SwiftFulcrum and OpalDiagnostics remain unchanged transitive dependencies; the application layer is deferred.
- `nostr-tor/0-opal-mainnet-alpha-private-deployment.1` remains a separately versioned proposal. Its identifier, 20-leading-zero-bit throttle, event kinds, timing, relay policy, and authority choices require explicit semantic approval before G0 can close.
- Alpha.4 protocol bytes and alpha.5 post-manifest transport bytes remain unchanged.
- The generic mainnet driver, public Mosaic session, public release lanes, live network, broadcast, canary, and production or anonymity claims remain disabled.
- Internal implementation review is not the independent external assurance required by G4.
- The tracked package locks intentionally remain on fetchable public `develop` revisions. Private draft commits cannot be written as honest public-URL pins until a separately approved public integration promotion makes them reachable.

## Work Completed

### OpalBase

- Added owner-and-generation-scoped outpoint quarantine, including missing-input tombstones reconstructed from the authenticated journal and exact-owner release APIs.
- Added a macOS-only `@_spi(MosaicPrivateAlpha)` authenticated journal boundary with opaque fresh, loaded-recovery, authenticated-empty abandonment, cleanup-correlation, and cleanup-requirement values.
- Added exact-CAS two-phase abandoned-attempt erasure. Phase one durably authorizes the exact scope and encrypted-envelope SHA-256 and releases OpalBase key-bearing journal state; phase two requires the outer owner to confirm ciphertext, root/field-key, and related-material cleanup.
- Added commit-then-error and commit-then-cancellation reconciliation, restart readback without the journal key, stale-attempt rejection, and persistence-closure lifetime tests.

### OpalFusion

- Added the proposed canonical private-deployment discovery, admission, roster, relay-selection, nonce-allocation, manifest, abort, completion, Nostr mapping, and authority contracts with selector-bound golden and negative parser coverage.
- Added one complete outbound relay-publication journal for batch preparation, recipient permits, relay attempts, acknowledgements, and terminal completion.
- Added exact durable readback after uncertain appends, recovery-time acknowledgement-derived accepted or rejected terminalization before any new route provisioning, stop/cancellation outcome preservation, and zero-start failure handling.
- Integrated the journal through control, anonymous, and contributor publication bridges without changing alpha.5 scheduling or canonical bytes.

### OpalCrypto

- No source change was required. Exact revision `e4886e2fdf2c4c25fa3ae7eead576dfd87cb4fb2` compiled in the package-only lane. Constant-time hardening and independent cryptographic or side-channel review remain open assurance work rather than a Mosaic workflow change.

## Validation

The validation host was arm64 macOS 27.0 build `26A5406e`, Xcode 27.0 build `27A5237l`, Apple Swift 6.4 `swiftlang-6.4.0.30.4`, and `/Applications/Xcode-beta.app/Contents/Developer`. All commands selected `TOOLCHAINS=com.apple.dt.toolchain.Metal.32023.921.1`. A temporary lane at `/private/tmp/opal-package-lane.ygTAjn` cloned and detached the exact three package revisions, changed only those temporary manifests to local path dependencies, and was removed after validation. No product manifest, lock, local path, or private remote substitution was committed. The first four commands below ran from `/private/tmp/opal-package-lane.ygTAjn/OpalBase`; the final three ran from `/private/tmp/opal-package-lane.ygTAjn/OpalFusion`.

```text
env TOOLCHAINS=com.apple.dt.toolchain.Metal.32023.921.1 swift package --scratch-path /private/tmp/opal-package-lane.ygTAjn/swiftpm/build --cache-path /private/tmp/opal-package-lane.ygTAjn/swiftpm/cache --config-path /private/tmp/opal-package-lane.ygTAjn/swiftpm/config --security-path /private/tmp/opal-package-lane.ygTAjn/swiftpm/security resolve
sh /Users/junecho/.codex/skills/ops-swiftpm-lane-consistency/scripts/deps-doctor.sh --repo-root /private/tmp/opal-package-lane.ygTAjn/OpalBase --lock-mode pinned --resolved-path /private/tmp/opal-package-lane.ygTAjn/OpalBase/Package.resolved --checkouts-root /private/tmp/opal-package-lane.ygTAjn/swiftpm/build/checkouts
env TOOLCHAINS=com.apple.dt.toolchain.Metal.32023.921.1 swift build --scratch-path /private/tmp/opal-package-lane.ygTAjn/swiftpm/build --cache-path /private/tmp/opal-package-lane.ygTAjn/swiftpm/cache --config-path /private/tmp/opal-package-lane.ygTAjn/swiftpm/config --security-path /private/tmp/opal-package-lane.ygTAjn/swiftpm/security
env TOOLCHAINS=com.apple.dt.toolchain.Metal.32023.921.1 swift test --scratch-path /private/tmp/opal-package-lane.ygTAjn/swiftpm/build --cache-path /private/tmp/opal-package-lane.ygTAjn/swiftpm/cache --config-path /private/tmp/opal-package-lane.ygTAjn/swiftpm/config --security-path /private/tmp/opal-package-lane.ygTAjn/swiftpm/security --filter 'AccountMosaicPrivateAlphaJournal|AccountMosaicAttempt(RecoveryPlanner|Journal|RecoveryGate)Validator|AccountMosaicTransactionBroadcastCoordinatorValidator'
env TOOLCHAINS=com.apple.dt.toolchain.Metal.32023.921.1 swift package --scratch-path /private/tmp/opal-package-lane.ygTAjn/fusion-swiftpm/build --cache-path /private/tmp/opal-package-lane.ygTAjn/fusion-swiftpm/cache --config-path /private/tmp/opal-package-lane.ygTAjn/fusion-swiftpm/config --security-path /private/tmp/opal-package-lane.ygTAjn/fusion-swiftpm/security resolve
sh /Users/junecho/.codex/skills/ops-swiftpm-lane-consistency/scripts/deps-doctor.sh --repo-root /private/tmp/opal-package-lane.ygTAjn/OpalFusion --lock-mode pinned --resolved-path /private/tmp/opal-package-lane.ygTAjn/OpalFusion/Package.resolved --checkouts-root /private/tmp/opal-package-lane.ygTAjn/fusion-swiftpm/build/checkouts
env TOOLCHAINS=com.apple.dt.toolchain.Metal.32023.921.1 swift test --scratch-path /private/tmp/opal-package-lane.ygTAjn/fusion-swiftpm/build --cache-path /private/tmp/opal-package-lane.ygTAjn/fusion-swiftpm/cache --config-path /private/tmp/opal-package-lane.ygTAjn/fusion-swiftpm/config --security-path /private/tmp/opal-package-lane.ygTAjn/fusion-swiftpm/security --filter 'MosaicMainnetAlphaPostManifestRelay(Publisher|PublicationRecovery)Validator'
```

| Validation | Result |
| --- | --- |
| Exact OpalBase build with OpalFusion `37266a4` and OpalCrypto `e4886e2` | Passed in 18.14 seconds. |
| Focused OpalBase journal, recovery, quarantine, and broadcast suites | 35 tests in 10 suites passed in 5.022 seconds after a 17.16-second test build. |
| Focused OpalFusion relay publication and durable-continuation suites | 18 tests in 2 suites passed in 18.107 seconds after a 33.83-second test build. |
| Dependency doctor | Local parity passed for OpalDiagnostics `8c42eeb40d64776789e70694e4e5006d2afa400c` and SwiftFulcrum `66a5a8ba9381b21881ad074d3a8dec3dc473ba0f`; remote heads were not checked. |

The OpalFusion test build emitted pre-existing deprecation warnings from legacy test call sites. This evidence proves current package-head compatibility and focused component behavior only. It does not prove fetchable resolved locks, a production durable backend, isolated-process application recovery, Keychain or physical erasure, complete runtime restoration, concrete Tor execution, chain reconciliation, external assurance, or private-alpha readiness.

## Open Questions And Blockers

### OpalBase-owned

- Add a deliberate private orchestration facade that consumes `FreshAttempt` and `LoadedRecovery` into the live host, recovery, approval, and concrete broadcast boundaries without enabling a public Mosaic session.
- Execute release, signing, commit, and recovery plans exactly once; release quarantine only from the exact terminal owner.
- Add exact transaction-presence reconciliation for ambiguous broadcast, confirmation and reorganization handling, chain-proven terminal disposition, and erasure authority for nonempty completed attempts.

### OpalFusion-owned

- Bind production construction to an approved private-deployment validation proof rather than caller-supplied deadlines or reservation expiry.
- Execute and restore pre-manifest discovery, candidate agreement, admission, role election, nonce allocation, manifest agreement, abort, and completion.
- Restore admission phase, coordinator operations, mailbox bindings, and inbound runtime around the implemented outbound publication continuation; add deterministic reconnect and terminal material-erasure semantics.
- Define a private package composition boundary and canonical recovery encoding without exposing the generic public runtime driver.

### Cross-package and governance

- Obtain explicit semantic approval for the proposed private-deployment.1 values or keep the proposal disabled.
- Do not rewrite `Package.resolved` to unreachable private commits. A fetchable exact lock requires separately approved public `draft -> develop` promotion of the relevant dependency commits, followed by exact lock refresh and validation.
- Keep G3 and all application-owned work deferred until a later Wallet-repository task. G4 external assurance, G5 network/value approval, and G6 acceptance remain absent.

## Next Steps

1. Start the next package-only session by rerouting OpalBase, OpalFusion, and OpalCrypto, fetching `private/draft`, and requiring exact local/private draft parity before new mutations.
2. Decide whether the next bounded slice is the OpalBase private recovery executor and chain-reconciliation boundary or the OpalFusion complete runtime-recovery envelope; keep ownership disjoint.
3. Apply the required Swift API, naming, concurrency, testing, and security reviews before changing interfaces.
4. Rebuild the exact temporary three-package lane and update this checkpoint or a dated successor with exact commands and non-proofs.
5. Request separate approval before any later private-draft push, public promotion, external network use, value movement, or application-repository mutation.

## Resume Prompt

```text
Resume Mosaic as a package-only task. Do not touch Wallet or implement application-owned persistence, Keychain, Tor provisioning, lifecycle, UI, controls, or policy. First route and fetch OpalBase, OpalFusion, and OpalCrypto; read OpalFusion docs/mosaic-package-layer-checkpoint-2026-08-15.md and the authoritative roadmap/profile/security/specification; verify local draft versus private/draft and the exact current commits. Preserve the disabled generic mainnet driver and public Mosaic session, the unapproved private-deployment.1 status, and the alpha.4/alpha.5 bytes. Then choose and implement one bounded package-owned slice: either OpalBase's private loaded-recovery/chain-reconciliation executor or OpalFusion's complete runtime-recovery envelope and pre-manifest execution. Use exact temporary cross-package validation, keep local paths and private remotes out of commits, and make no readiness, anonymity, mainnet, or gate-closure claim without the required evidence.
```
