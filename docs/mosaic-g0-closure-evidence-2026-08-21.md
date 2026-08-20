# Mosaic G0 Closure Evidence — 2026-08-21

Status: G0 complete. This record closes contract decisions and exact dependency alignment only. G1 through G6 remain open under [Mosaic Mainnet-Alpha Progress](mosaic-mainnet-alpha-progress.md), and no external Mosaic network, value movement, release, or public claim is authorized.

## Decision And Scope

The [Mosaic Private-Deployment.1 Semantic Decision](mosaic-private-deployment-decision-2026-08-21.md) accepts `nostr-tor/0-opal-mainnet-alpha-private-deployment.1` unchanged for the internal macOS private alpha. It preserves `Mosaic/0-opal-mainnet-alpha.4` and `nostr-tor/0-opal-mainnet-alpha.5` bytes and explicitly accepts the off-commitment accountability limitation, 20-bit admission throttle and non-Sybil posture, exact candidate and role policy, fee and deadline policy, ephemeral discovery mapping, relay restrictions, fresh key and material rules, recovery behavior, and safe-claim boundary.

Wallet commit `67018a420cb1e600afb1a92b15908969b7db722e` records the accepted application plan, pins the exact package graph below, and keeps public Mosaic construction structurally absent. The plan routes cryptographic calculation through OpalCrypto, reusable Mosaic semantics through OpalFusion, wallet and broadcast authority through OpalBase, chain-client correctness through SwiftFulcrum, privacy-safe diagnostics through OpalDiagnostics, and deployment composition through Wallet. No external production package or novel cryptographic construction was selected.

## Exact Resolved Graph

| Repository | Exact revision | Promoted integration lane |
| --- | --- | --- |
| Wallet | `67018a420cb1e600afb1a92b15908969b7db722e` | `origin/draft` and `origin/develop` |
| OpalBase | `b21dc1e69472cb9dfb59a3810cbadf637150df53` | `private/draft` and `public/develop` |
| OpalFusion | `c4ba44e1782eb431972fa4189a739f047f182315` | `private/draft` and `public/develop` |
| OpalCrypto | `246584961096b38b8303a39e66ffb3951f6efcc7` | `private/draft` and `public/develop` |
| SwiftFulcrum | `24b44bb2458822d14121dfbd57321fda7ae539ea` | `private/draft` and `public/develop` |
| OpalDiagnostics | `7cd2e383309821e01903077c1e534174f9c8a964` | `private/draft` and `public/develop` |

OpalBase's tracked `Package.resolved` pins the four package dependencies exactly. Wallet's tracked Xcode `Package.resolved` pins all five package dependencies exactly, including OpalBase and the same transitive revisions. The OpalFusion commit that contains this evidence is documentation-only and does not change the runtime revision consumed by OpalBase or Wallet, so it does not create a circular repinning requirement.

## Environment

- Apple Silicon Mac running macOS 27.0 build `26A5416b`.
- Xcode 27.0 build `27A5237l` selected from `/Applications/Xcode-beta.app/Contents/Developer`.
- Apple Swift 6.4 `swiftlang-6.4.0.30.4`, target `arm64-apple-macosx27.0.0`.
- Xcode Metal Toolchain 27A5237l installed with `xcodebuild -downloadComponent MetalToolchain` after the first Wallet build exposed the missing required component.
- All Mosaic package tests and builds were local. The dependency remote check used ordinary Git reads only. No Mosaic relay, Tor route, Fulcrum service, transaction reader, broadcaster, credential, or value-moving endpoint was used.

## Commands And Results

From exact OpalFusion `c4ba44e1782eb431972fa4189a739f047f182315`:

```text
swift test --quiet --filter MosaicMainnetAlphaPrivate
```

Result: 34 tests in 7 suites passed in 135.264 seconds. This aggregate includes the accepted private-deployment policy and exact profile, discovery, recovery, publication, route, and drift behavior covered by the filter.

From exact OpalBase `b21dc1e69472cb9dfb59a3810cbadf637150df53`, every SwiftPM command used one lane:

```text
sh ~/.codex/skills/ops-swiftpm-lane-consistency/scripts/deps-doctor.sh --repo-root "$PWD" --resolved-path Package.resolved --checkouts-root .swiftpm-cache/swiftpm/build/checkouts --lock-mode pinned --remote-check
swift build --quiet --scratch-path .swiftpm-cache/swiftpm/build --cache-path .swiftpm-cache/swiftpm/cache --config-path .swiftpm-cache/swiftpm/config --security-path .swiftpm-cache/swiftpm/security --only-use-versions-from-resolved-file --skip-update
swift test --quiet --scratch-path .swiftpm-cache/swiftpm/build --cache-path .swiftpm-cache/swiftpm/cache --config-path .swiftpm-cache/swiftpm/config --security-path .swiftpm-cache/swiftpm/security --only-use-versions-from-resolved-file --skip-update --filter 'AccountMosaicPrivateAlpha|AccountMosaicProfileTransactionPolicyValidator|AccountMosaicTransactionBroadcastCoordinatorValidator'
```

Results: dependency doctor passed resolved revision, checkout HEAD, and public `develop` remote-head parity for OpalCrypto, OpalDiagnostics, OpalFusion, and SwiftFulcrum; the package build passed; 55 focused tests in 10 suites passed in 12.247 seconds. No live-network test was selected.

Wallet first resolved only the tracked exact lock and disabled automatic package updates:

```text
xcodebuild -project Wallet.xcodeproj -scheme Wallet -clonedSourcePackagesDirPath .codex-cache/SourcePackages-G0 -packageCachePath .codex-cache/PackageCache-G0 -disablePackageRepositoryCache -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -resolvePackageDependencies
```

The resolution checked out OpalBase `b21dc1e`, OpalFusion `c4ba44e`, OpalCrypto `2465849`, SwiftFulcrum `24b44bb`, and OpalDiagnostics `7cd2e38`. The exact application build was:

```text
xcodebuild -project Wallet.xcodeproj -scheme Wallet -configuration Debug -destination 'platform=macOS' -derivedDataPath .codex-cache/G0DerivedData -clonedSourcePackagesDirPath .codex-cache/SourcePackages-G0 -packageCachePath .codex-cache/PackageCache-G0 -disablePackageRepositoryCache -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Result: `BUILD SUCCEEDED`. Xcode compiled the Wallet target and the complete exact dependency graph. The package-plug-in exception was scoped to this command after inspecting pinned OpalCrypto `2465849`: `MetalLibraryBuildPlugin` invokes only its package-owned compiler wrapper, and that wrapper invokes the matching Apple `metal` and `metallib` tools against the declared source and plug-in work directory. No project or machine trust setting was weakened or changed. The local `.app`, DerivedData, source checkouts, and package cache remain ignored validation artifacts rather than release artifacts.

Wallet documentation validation also passed:

```text
scripts/check-doc-plan-metadata.sh --repo-root "$PWD"
git diff --cached --check
```

The accepted Wallet plan records the application authority, role map, state ownership, event and capability boundary, concurrency and cancellation rules, first-party dependency policy, staged G1 through G6 work, validation budgets, external approval boundaries, and unresolved later-gate risks.

## Closure Findings

- Contract semantics are no longer implementation-defined: the private-deployment decision and authoritative profile and security documents agree on the accepted tradeoffs, exact policy, relay restrictions, recovery decisions, and permitted wording.
- The same exact OpalFusion, OpalBase, OpalCrypto, SwiftFulcrum, and OpalDiagnostics revisions are fetchable from their public integration lanes and resolved by the committed Wallet application lock.
- Profile, protocol, transport, network, generation, material, and application-policy drift is rejected by the focused package contracts before wallet, recovery, route, or broadcast mutation.
- The exact graph builds through the Wallet application owner. G0 therefore satisfies its decision, alignment, and local validation requirements.

## Approvals And Promotion

The repository owner explicitly authorized direct work in the existing Opal repositories, commits, pushes, and validated `draft -> develop` promotion for this Mosaic goal. OpalFusion acceptance, OpalBase repinning, and Wallet exact-lock commits were fast-forwarded through those authorized integration lanes. No `main` promotion, tag, release, public feature enablement, deployment publication, paid operation, credential use, external Mosaic networking, broadcast, value movement, or canary was authorized or performed.

## Residual Risks And Disable Procedure

All residual risks accepted by the semantic decision remain active, including candidate capture and selective abort, off-commitment accountability limits, relay and traffic correlation, absent forward secrecy or post-compromise protection in the selected Nostr construction, and the fact that configured relay diversity does not prove operator or circuit independence.

G1 still lacks application-owned atomic outer persistence, Keychain keys and rollback anchors, cross-process exclusion, complete startup enumeration, inventory or tombstones, and verified terminal erasure. G2 still lacks production key distribution, encrypted mailbox lifecycle, authoritative external relay selection, and concrete reviewed Tor isolation. G3 through G6 remain open in full.

Disable remains structural: `.opalMainnetAlpha` is nondefault, the generic mainnet driver rejects it, Wallet commit `67018a42` adds no Mosaic runtime constructor or public session, and no external configuration is active. Rollback is to keep the feature disabled, stop any future discovery and route allocation, preserve quarantine and recovery evidence, reconcile any future approved broadcast through the exact chain authority, and erase attempt material only after package-authorized terminal disposition. The dependency-lock commits may be reverted through normal review if the accepted contract is withdrawn; no live Mosaic state exists at G0.

## Non-Proofs

This record does not prove durable storage or erasure, fresh-process recovery, concrete Tor routing, DNS or clearnet exclusion, circuit or operator independence, relay delivery, authenticated key distribution, application session composition, multi-device reliability, traffic-analysis resistance, independent review, chain reconciliation, broadcast safety, mainnet canary safety, anonymity, Sybil resistance, production readiness, public release readiness, or G1 through G6 closure. The maximum current wording remains “deterministic mainnet-alpha contract foundation.”
