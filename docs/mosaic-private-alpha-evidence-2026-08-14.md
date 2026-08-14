# Mosaic Private-Alpha Evidence — 2026-08-14

Status: Historical G0 in-progress evidence captured on 2026-08-14. This record does not close G0 or any later gate. The Wallet task composition recorded below was explicitly reverted on 2026-08-15 and is not current evidence; see the [package-layer checkpoint](mosaic-package-layer-checkpoint-2026-08-15.md).

## Scope And Environment

The inspection covered OpalFusion, OpalBase, OpalCrypto, SwiftFulcrum, OpalDiagnostics, the Wallet application, and OpalHedge solely to disqualify it as the application owner. Each repository was routed through its authoritative policy and fetched before its state was recorded. OpalFusion, OpalBase, OpalCrypto, SwiftFulcrum, OpalDiagnostics, and OpalHedge route as Class D product lanes; Wallet routes as a Class P product lane and its repository-local policy owns that exception. Wallet's `Wallet/App/(Bootstrap)/WalletApp.swift` and `WalletAppComposition.swift` establish Wallet as the application composition owner.

The local environment was arm64 macOS 27.0 build `26A5406e`, Xcode 27.0 build `27A5237l`, and Apple Swift 6.4 `swiftlang-6.4.0.30.4`. Package manifests select Swift tools 6.2. Xcode selected `/Applications/Xcode-beta.app/Contents/Developer`.

## Fresh Starting Revisions

| Repository | Starting revision | Starting lane | State |
| --- | --- | --- | --- |
| OpalFusion | `51ebd6b0ffc3ea38b6948bfddf8b64270afc94f9` | `private/draft` | Clean and exact after fetch. |
| OpalBase | `f6219cad06517924cddb45e9bb9b95c0a6e2e47d` | `private/draft` | Clean and exact after fetch; task worktree attached to `wip/mosaic-private-alpha-20260814-1351`. |
| OpalCrypto | `e4886e2fdf2c4c25fa3ae7eead576dfd87cb4fb2` | `private/draft` | Clean and exact after fetch. |
| SwiftFulcrum | `66a5a8ba9381b21881ad074d3a8dec3dc473ba0f` | `private/draft` | Clean and exact after fetch. |
| OpalDiagnostics | `8c42eeb40d64776789e70694e4e5006d2afa400c` | `private/draft` | Clean and exact after fetch. |
| Wallet | `543927b36fa4dae839719e7ab356f01ad863220e` | `origin/draft` | Clean and exact after fetch; isolated task worktree attached to `wip/mosaic-private-alpha-20260814-1409`. |
| OpalHedge | `a945ab1cb1402bd5e28d813c258036b2ad022bbd` | `private/draft` | Clean and exact after fetch; inspected only to confirm it is not the app owner. |

The OpalFusion implementation branch was created from the recorded exact base as `wip/mosaic-private-alpha-20260814-1406`. Branch names are workflow facts, not compatibility evidence.

## Starting Resolved Graphs

OpalBase's tracked `Package.resolved` does not resolve the inspected private-alpha source set:

| Dependency | Resolved revision |
| --- | --- |
| OpalFusion | `2e657d6e1ef8b879cfa2f12d5b9f7c08b892d505` |
| OpalCrypto | `cdbadf398bcfdb0d9a3c7cd655a0f65089337f80` |
| SwiftFulcrum | `66a5a8ba9381b21881ad074d3a8dec3dc473ba0f` |
| OpalDiagnostics | `8c42eeb40d64776789e70694e4e5006d2afa400c` |

Wallet's tracked Xcode `Package.resolved` is older still:

| Dependency | Resolved revision |
| --- | --- |
| OpalBase | `606c188fea5a139a178fa38d962c61b80baa3a27` |
| OpalFusion | `d39ca2827278bd2be39543a78f31466b360d90d0` |
| OpalCrypto | `8171809112037fa4ffc877ebfe587ae068ac75b4` |
| SwiftFulcrum | `0777e384a05beed9491ac50b8ce11858d061f04f` |
| OpalDiagnostics | `c3556731176e2be04c90d5542cf7049c8abe1f79` |
| OpalHedge | `24f1627ae716438c3ddee314c0f3006bc79bf088` |

Matching branch labels or profile identifiers cannot repair these revision mismatches. The final exact-set evidence must include OpalDiagnostics in addition to OpalFusion, OpalBase, OpalCrypto, SwiftFulcrum, and Wallet.

## Commands And Results

Repository policy routing used `resolve-repo-policy.sh --cwd <repository>` for every repository. Each route returned `status=ok`; Wallet returned Class P with its local `AGENTS.md`, while the other in-scope implementation repositories returned Class D. Freshness used `git fetch --prune --all` followed by the class-default `check-branch-freshness.sh` or `safe-start-worktree.sh`/`ensure-task-branch.sh` before mutation. Every recorded starting checkout was clean and stash-free.

OpalBase and OpalFusion dependency refresh used the same SwiftPM lane for each package command:

```text
swift package --scratch-path .swiftpm-cache/swiftpm/build --cache-path .swiftpm-cache/swiftpm/cache --config-path .swiftpm-cache/swiftpm/config --security-path .swiftpm-cache/swiftpm/security resolve
sh ~/.codex/skills/ops-swiftpm-lane-consistency/scripts/deps-doctor.sh --repo-root <repository> --lock-mode pinned --resolved-path Package.resolved --checkouts-root .swiftpm-cache/swiftpm/build/checkouts --remote-check
```

Both resolves completed without changing their tracked lockfiles. Both dependency-doctor runs passed resolved-checkout parity and public branch-head checks for the starting public graph. That result proves only the stale starting pins; it does not prove the private-alpha revision set.

The RSA-free OpalFusion filter was attempted with the same scratch, cache, configuration, and security paths, `--disable-sandbox` as already declared by the repository validation script, maximum parallel width four, and filter `MosaicMainnetAlphaPostManifestRelayFanInRouteValidationValidator|MosaicMainnetAlphaPostManifestContributorTransportBridgeValidator`. Compilation stopped before test execution because the selected Xcode installation lacked its optional Metal Toolchain component. The diagnostic was `cannot execute tool 'metal' due to missing Metal Toolchain`. This was an environment precondition, not a passing test and not evidence of a source defect. The expensive filter was not looped.

After narrow approval, `xcodebuild -downloadComponent MetalToolchain` installed matching build `27A5237l`. `xcodebuild -showComponent MetalToolchain -json` reported status `installed` and identifier `com.apple.dt.toolchain.Metal.32023.921.1`. The beta Xcode's default lookup still failed, while `env TOOLCHAINS=com.apple.dt.toolchain.Metal.32023.921.1 xcrun metal --version` succeeded with Apple Metal `32023.921`. Subsequent validation must record and use that explicit toolchain selector; the download itself does not convert the earlier test attempt into a pass.

## G0 Contract Implementation Validation

OpalFusion revision `b5f60b07ccc1437acc5ec74cede26e49b8319ad7`, based on `51ebd6b0ffc3ea38b6948bfddf8b64270afc94f9`, is the immutable proposed G0 implementation. Documentation-only follow-up revision `34b1cfcea45cc113fda1287eeca8c5bf6d88830c` carries that implementation and is the exact OpalFusion revision in the Wallet composition below. The final package-local validation used one isolated SwiftPM lane with the Metal toolchain selector above, SwiftPM sandbox disabled under the repository's documented exception, and no network or value-moving service. The lane's workspace state recorded OpalCrypto as an editable checkout whose Git HEAD was exactly `e4886e2fdf2c4c25fa3ae7eead576dfd87cb4fb2`; its resolved OpalDiagnostics checkout was exactly `8c42eeb40d64776789e70694e4e5006d2afa400c`. The editable path was local validation state only. The tracked `Package.resolved` was restored byte-for-byte afterward and contains no path or private-remote substitution.

From the OpalFusion repository root, the exact commands were:

```text
env TOOLCHAINS=com.apple.dt.toolchain.Metal.32023.921.1 swift test --disable-sandbox --scratch-path .swiftpm-cache/mosaic-exact/build --cache-path .swiftpm-cache/mosaic-exact/cache --config-path .swiftpm-cache/mosaic-exact/config --security-path .swiftpm-cache/mosaic-exact/security --filter MosaicMainnetAlphaPrivate
env TOOLCHAINS=com.apple.dt.toolchain.Metal.32023.921.1 OPALFUSION_SPM_SCRATCH_PATH=.swiftpm-cache/mosaic-exact/build OPALFUSION_SPM_CACHE_PATH=.swiftpm-cache/mosaic-exact/cache OPALFUSION_SPM_CONFIG_PATH=.swiftpm-cache/mosaic-exact/config OPALFUSION_SPM_SECURITY_PATH=.swiftpm-cache/mosaic-exact/security OPALFUSION_SPM_MODULE_CACHE_PATH=.swiftpm-cache/mosaic-exact/module-cache ./scripts/run-validation-loop.sh mosaic-fast
env TOOLCHAINS=com.apple.dt.toolchain.Metal.32023.921.1 swift test --disable-sandbox --scratch-path .swiftpm-cache/mosaic-exact/build --cache-path .swiftpm-cache/mosaic-exact/cache --config-path .swiftpm-cache/mosaic-exact/config --security-path .swiftpm-cache/mosaic-exact/security --filter 'MosaicMainnetAlphaMinimumRosterCompositionValidator|MosaicMainnetAlphaPostManifestMailboxRouteProvisioningValidator|MosaicMainnetAlphaExecutionGateValidator'
```

For `mosaic-fast`, the script additionally supplied `--manifest-cache local`, set `OPALFUSION_EC_INTEROP` to the empty string, resolved `CLANG_MODULE_CACHE_PATH` to the named repository-relative module cache, passed `--experimental-maximum-parallelization-width 4`, and selected `MosaicMainnetAlphaPostManifestRelayFanInRouteValidationValidator|MosaicMainnetAlphaPostManifestContributorTransportBridgeValidator`. No command supplied `SWIFTPM_MAX_PARALLELISM` or `--jobs`; the other two commands supplied no explicit module-cache or test-width override.

The exact-leaf candidate lane produced these results:

| Command | Result |
| --- | --- |
| `MosaicMainnetAlphaPrivate` command above | Build passed in 21.48 seconds; 34 tests in 7 suites passed in 125.905 seconds. |
| `mosaic-fast` command above | Build passed in 0.52 seconds; 6 tests in 2 suites passed in 12.546 seconds, within the 15-second warm test budget. |
| Three-filter command above | Build passed in 0.48 seconds; 4 tests in 3 suites passed in 37.555 seconds. The execution-gate suite retained generic-driver rejection and one private owner-authorized construction path. |

The private suite includes fixed canonical and domain goldens, strict parser positives and negatives, deterministic mutation bounds, exact protocol/genesis drift, discovery/control identity separation, decoded-event-only manifest assembly, proof-derived signer authority, nonce-allocation publication, and signed-manifest plus previous-output-backed completion validation. `git diff --check`, exact filename-header inspection, the strict API/naming audit, validation-script syntax and absolute module-cache override checks, and changed-document relative-link validation passed. The five files above the naming skill's 199-line target are recorded as advisory split debt; the skill defines no blocking line-count finding, and there is no unresolved `BlockingRename` or `BlockingNonRename` finding.

These results prove package-local contract behavior for exact committed OpalFusion `b5f60b07ccc1437acc5ec74cede26e49b8319ad7` against the exact newer OpalCrypto and OpalDiagnostics leaves. They do not prove semantic approval of the new private-deployment profile, durable recovery, concrete transport, Mosaic application-session integration, external review, or any later gate.

## Exact OpalBase Cross-Package Validation

An ephemeral source archive of exact OpalBase `f6219cad06517924cddb45e9bb9b95c0a6e2e47d` was validated against the same clean dependency checkouts used by the Wallet composition: OpalFusion `34b1cfcea45cc113fda1287eeca8c5bf6d88830c`, OpalCrypto `e4886e2fdf2c4c25fa3ae7eead576dfd87cb4fb2`, SwiftFulcrum `66a5a8ba9381b21881ad074d3a8dec3dc473ba0f`, and OpalDiagnostics `8c42eeb40d64776789e70694e4e5006d2afa400c`. Only the archive's manifest used local path substitutions; every production source and test file came byte-for-byte from the exact commit. `swift package show-dependencies --format json` resolved each identity to the intended clean checkout, and direct Git inspection matched every checkout HEAD to the revision above. No local path, private remote, credential, or configuration change entered any repository commit. The authoritative OpalBase worktree remained clean and its tracked `Package.resolved` remained byte-identical with SHA-256 `425d942518709d09da021292123224d40ca5701b67865ba171e860e6f9f1b5d4`.

Every command used this working-directory-relative lane and the same explicit Metal selection:

```text
env TOOLCHAINS=com.apple.dt.toolchain.Metal.32023.921.1 swift build --disable-sandbox --scratch-path .swiftpm-cache/mosaic-g0-final/build --cache-path .swiftpm-cache/mosaic-g0-final/cache --config-path .swiftpm-cache/mosaic-g0-final/config --security-path .swiftpm-cache/mosaic-g0-final/security
env TOOLCHAINS=com.apple.dt.toolchain.Metal.32023.921.1 swift test --disable-sandbox --scratch-path .swiftpm-cache/mosaic-g0-final/build --cache-path .swiftpm-cache/mosaic-g0-final/cache --config-path .swiftpm-cache/mosaic-g0-final/config --security-path .swiftpm-cache/mosaic-g0-final/security --filter AccountMosaicAttemptRecoveryPlannerValidator
env TOOLCHAINS=com.apple.dt.toolchain.Metal.32023.921.1 swift test --disable-sandbox --scratch-path .swiftpm-cache/mosaic-g0-final/build --cache-path .swiftpm-cache/mosaic-g0-final/cache --config-path .swiftpm-cache/mosaic-g0-final/config --security-path .swiftpm-cache/mosaic-g0-final/security --filter AccountMosaicAttemptJournalValidator
env TOOLCHAINS=com.apple.dt.toolchain.Metal.32023.921.1 swift test --disable-sandbox --scratch-path .swiftpm-cache/mosaic-g0-final/build --cache-path .swiftpm-cache/mosaic-g0-final/cache --config-path .swiftpm-cache/mosaic-g0-final/config --security-path .swiftpm-cache/mosaic-g0-final/security --filter AccountMosaicAttemptRecoveryGateValidator
env TOOLCHAINS=com.apple.dt.toolchain.Metal.32023.921.1 swift test --disable-sandbox --scratch-path .swiftpm-cache/mosaic-g0-final/build --cache-path .swiftpm-cache/mosaic-g0-final/cache --config-path .swiftpm-cache/mosaic-g0-final/config --security-path .swiftpm-cache/mosaic-g0-final/security --filter AccountMosaicTransactionBroadcastCoordinatorValidator
env TOOLCHAINS=com.apple.dt.toolchain.Metal.32023.921.1 swift test --disable-sandbox --scratch-path .swiftpm-cache/mosaic-g0-final/build --cache-path .swiftpm-cache/mosaic-g0-final/cache --config-path .swiftpm-cache/mosaic-g0-final/config --security-path .swiftpm-cache/mosaic-g0-final/security
```

| Command or filter | Result |
| --- | --- |
| `swift build` | Passed; build completed in 19.29 seconds. |
| `AccountMosaicAttemptRecoveryPlannerValidator` | 5 tests in 1 suite passed in 1.033 seconds. |
| `AccountMosaicAttemptJournalValidator` | 2 tests in 1 suite passed in 1.125 seconds. |
| `AccountMosaicAttemptRecoveryGateValidator` | 5 tests in 1 suite passed in 1.163 seconds. |
| `AccountMosaicTransactionBroadcastCoordinatorValidator` | 10 tests in 1 suite passed in 2.593 seconds. |
| Full `swift test` | The network-test product reported 37 tests in 10 suites passed in its default no-live-network configuration, and the local-test product reported 1,003 tests in 101 suites passed in 98.000 seconds. No external endpoint, credential, or value movement was authorized or used. |

The four focused filters therefore passed 22 tests against one exact OpalBase/OpalFusion/OpalCrypto/SwiftFulcrum/OpalDiagnostics set, and the full package suite passed on that same set. SwiftPM emitted advisory conflicting-identity warnings because the uncommitted root path substitutions overrode matching transitive public-URL identities; the resolved graph still selected only the exact root checkouts. The tracked Wallet lock was separately checked in pinned mode with `deps-doctor.sh`: all six dependency pins, including OpalHedge, equaled their checkout HEADs. Remote checking was intentionally omitted because the focused local commits have not been approved for push, so public-remote availability remains unproved.

## Exact Application Dependency Composition

Wallet task commit `24721909fe901ffe3018cb368690c9536e8128e6`, based on `543927b36fa4dae839719e7ab356f01ad863220e`, records the exact application composition owner and its resolved dependency graph. `Wallet/App/(Bootstrap)/WalletApp.swift` is the `@main` application, while `WalletAppBootstrap+ContainerAssembly.swift` constructs the app container and connects secret storage, cleanup, and access. The tracked Xcode `Package.resolved` has SHA-256 `f16b44e23fb5e5bdb8390be3e353c8c73651c029f517c51dcf0fb5585e3727e0` and retains public package URLs with no path or private-remote substitution.

| Repository | Exact revision | Composition role |
| --- | --- | --- |
| Wallet | `24721909fe901ffe3018cb368690c9536e8128e6` | Application owner and exact lock. |
| OpalBase | `f6219cad06517924cddb45e9bb9b95c0a6e2e47d` | Wallet, recovery, approval, and broadcast boundary. |
| OpalFusion | `34b1cfcea45cc113fda1287eeca8c5bf6d88830c` | Proposed private-deployment contract plus alpha.4/alpha.5 runtime and transport semantics. |
| OpalCrypto | `e4886e2fdf2c4c25fa3ae7eead576dfd87cb4fb2` | Cryptographic primitives. |
| SwiftFulcrum | `66a5a8ba9381b21881ad074d3a8dec3dc473ba0f` | Chain client dependency; no live endpoint was contacted. |
| OpalDiagnostics | `8c42eeb40d64776789e70694e4e5006d2afa400c` | Privacy-typed diagnostics. |
| OpalHedge | `24f1627ae716438c3ddee314c0f3006bc79bf088` | Existing Wallet dependency, not the Mosaic application owner. |

The six dependency checkout HEADs, including OpalHedge, matched the tracked revisions exactly. Validation used ephemeral Git URL rewrites only to make the unlanded local task commits resolvable through their unchanged public package URLs; those rewrites, local repository paths, credentials, and private remotes are absent from the commit. This proves a local exact revision composition, not public-remote availability or landing.

The exact graph required compatible construction-bound mnemonic persistence policy and explicit diagnostic-field privacy. Wallet binds Secure Enclave stores to `.requireSecureEnclave`, derives legacy policy separately, rejects alternate secure factories without their app-owned direct wipe operation, invalidates secret generations before erasure, and cancels and awaits overlapping legacy migration writes before direct Keychain cleanup. Deterministic tests cover a stale read captured before wipe, a cancellation-ignoring write that must not resurrect ciphertext, migration round-trip mismatch that must leave the legacy mnemonic readable, and fail-closed alternate storage configuration. Diagnostic amounts, wallet-derived indices, high-cardinality timestamps, observer identity, and dynamic Keychain context are private; bounded operational counts, booleans, durations, retries, stable error codes, and chain heights remain public.

The exact current-tree commands, after local revision resolution into the isolated source-package directory, were:

```text
env TOOLCHAINS=com.apple.dt.toolchain.Metal.32023.921.1 xcodebuild -project Wallet.xcodeproj -scheme Wallet -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath .codex-cache/MosaicG0DerivedData -clonedSourcePackagesDirPath .codex-cache/MosaicG0SourcePackages -onlyUsePackageVersionsFromResolvedFile -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO build
env TOOLCHAINS=com.apple.dt.toolchain.Metal.32023.921.1 xcodebuild -project Wallet.xcodeproj -scheme Wallet -configuration Debug -destination 'platform=macOS' -derivedDataPath .codex-cache/MosaicG0DerivedData -clonedSourcePackagesDirPath .codex-cache/MosaicG0SourcePackages -onlyUsePackageVersionsFromResolvedFile -skipPackagePluginValidation -resultBundlePath .codex-cache/MosaicWalletRemaining-1846.xcresult CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO test -only-testing:WalletTests/WalletSecretInteractorValidator -only-testing:WalletTests/WalletManagementDiscoveryInteractorValidator -only-testing:WalletTests/AccountInteractorValidator
```

| Artifact or lane | Result |
| --- | --- |
| Final generic Wallet application build | Passed for arm64 and x86_64 against the exact resolved graph. |
| `.codex-cache/MosaicWalletRemaining-1846.xcresult` | Current-tree result passed 69 named tests / 72 executions with zero failures or skips in 56.798 seconds: 19 Wallet secret, 46 account, and 4 management-discovery tests. |
| `.codex-cache/MosaicG0Focused-1804.xcresult` | Earlier same-lock broad privacy and storage lane passed 100 named tests / 346 executions with zero failures or skips. |
| `.codex-cache/MosaicWalletRoleSplit-1806.xcresult` | Earlier same-lock app-call-site lane passed 153 named tests / 168 executions across 11 suites with zero failures or skips. |

An initial `.codex-cache/MosaicWalletRemaining-1840.xcresult` attempt stopped before compilation or test execution because Xcode had not enabled the reviewed package build plug-in; it is a non-proof and is excluded. Earlier selector attempts that discovered zero tests are also excluded. The final universal build emitted ten Swift 6.4 isolated-conformance diagnostics from five distinct untouched warning sites in `AddWalletPreviewView.swift`, once for each arm64 and x86_64 compilation; they are existing advisory debt rather than a warning-clean result. Mac Secure Enclave tests may return before their round-trip assertions when hardware or Keychain entitlements are unavailable, so this lane proves compilation, fail-closed policy, simulated fresh-instance behavior, and deterministic lifecycle logic, not hardware-backed encryption or physical key erasure. The internal assurance review found no remaining release-blocking implementation, API, naming, concurrency, testing, security, observability, or claim-accuracy issue, but it is not the independent external review required by G4.

`git grep -n -i mosaic 24721909fe901ffe3018cb368690c9536e8128e6 -- Wallet WalletBrand WalletWatch WalletTests` returned no match. This exact composition therefore contains no Wallet Mosaic session or app-facing Mosaic boundary. It satisfies the G0 dependency-build obligation only; it does not satisfy G1 durability, G2 transport, G3 application-session composition, G4 assurance, G5 canary, or G6 acceptance.

## Discovery Work Benchmark

The unresolved discovery admission throttle was measured before fixing the candidate proposal value, then remeasured after the private-deployment identifier was bound into the canonical work document and digest. The checked-in [benchmark source](../Benchmarks/MosaicPrivateAlphaWorkBenchmark.swift) constructs the exact 364-byte production-shaped SHA-256 preimage: the work domain, direct private-deployment identifier field, canonical selector and alpha.4 identifiers, mainnet genesis hash, aligned epoch, 32-byte pool identifier, valid x-only discovery key, 32-byte relay-set digest, big-endian `u64` nonce, and exact beacon expiry. It varies only the canonical nonce inside each deterministic trial, checks the actual leading-zero count, and runs ten trials per threshold on an Apple M1 Max. Its SHA-256 digest is `01dfb6b8e90ac7cde22e1f05f35c0e05f028b38b2c17a0f261d8c093136bb401`. The reproduced executable digest from the exact command below is `45df48f5222171402e42deab1b278eda88b4b5a1132a70f83aa27b53fee91996`; compiled executables are not tracked and their bytes are not a portability contract. The checked-in [raw reproduced output](mosaic-private-alpha-work-benchmark-2026-08-14.txt) has SHA-256 digest `27604d311a364b0a5145ede70389544fb95fafa8ad25e6b167e08f50c36078ab`.

```text
env TOOLCHAINS=com.apple.dt.toolchain.Metal.32023.921.1 xcrun swiftc -O Benchmarks/MosaicPrivateAlphaWorkBenchmark.swift -o /private/tmp/MosaicPrivateAlphaWorkBenchmark-reproduced
/private/tmp/MosaicPrivateAlphaWorkBenchmark-reproduced
```

| Target | Median time | Aggregate observed rate | Ten-trial attempt counts |
| --- | --- | --- | --- |
| 16 leading-zero bits | 0.0174 seconds | 2.01 million hashes/second | `16163, 67592, 45037, 6415, 66621, 30400, 21766, 44092, 22970, 68839` |
| 18 leading-zero bits | 0.0998 seconds | 2.14 million hashes/second | `198940, 132823, 45037, 516877, 577069, 431115, 26818, 132310, 424326, 227338` |
| 20 leading-zero bits | 0.2939 seconds | 2.13 million hashes/second | `843054, 1365311, 316192, 540396, 1187111, 708689, 26818, 213053, 2394429, 227338` |

Sixteen bits was rejected as a roughly 17-millisecond median throttle on the private alpha's measured Mac class. Twenty bits is the proposed private-deployment minimum: its selector-bound deterministic attempt vector reproduced exactly, its slowest observed trial remained well inside the 60-second beacon window, and the reproduced ten-trial total was 3.68 seconds. This microbenchmark is device- and implementation-specific, does not measure adversarial hardware or network discovery, and does not establish Sybil resistance.

## Proposed G0 Decision Set

The proposed separately versioned [Mosaic Mainnet-Alpha Private-Deployment Profile](mosaic-mainnet-alpha-private-deployment.md) specifies the private discovery and deployment decisions that were previously implementation-defined. It preserves every alpha.4 protocol byte and alpha.5 post-manifest transport byte while fixing the private-deployment identifier, identifier-bound canonical documents and domains, 300-second epoch, 20-bit admission throttle, pre- and post-manifest deadlines, exact reservation-lease expiration, pool source requirements, relay endpoint and registry-digest policy, candidate selection and acknowledgement, globally disjoint discovery/control roles, nonce-allocation publication, event kinds and signer authority, abort/completion mapping, and conservative cross-layer recovery behavior. These values remain proposed until the explicit semantic approval recorded as the G0 blocker is granted.

The fixed fee remains one satoshi per final signed byte with the existing one-to-two-satoshi roster-derived contributor share and ten-satoshi transaction overhead. The accepted off-commitment accountability limitation remains unchanged. The 20-bit work and three registry-label digests are respectively an admission throttle and configured-diversity assertion, not Sybil resistance or operator independence. The private supplement requires no clearnet fallback and grants no broadcast permission.

On 2026-08-14, recovery decisions were explicit for later implementation: a signing intent without durable signed bytes aborts and releases rather than re-signing; a locally signed state resumes only from its exact stored bytes; an ambiguous broadcast intent performs no dispatch until exact transaction presence is reconciled; corrupt, rolled-back, deleted, stale, or uncertain state remains quarantined; and material erasure waits for terminal wallet and chain disposition. The later package-only checkpoint implements abandoned-journal cleanup authorization and outbound publication continuation components, but complete G1 and G5 execution remains absent.

## Gate Findings

| Gate | Baseline result on 2026-08-14 |
| --- | --- |
| G0 | In progress: revision `b5f60b07ccc1437acc5ec74cede26e49b8319ad7` implements the proposed supplement with freeze-grade vectors and no unresolved internal audit finding; Wallet `24721909fe901ffe3018cb368690c9536e8128e6` proves exact local dependency parity and application compilation; explicit approval of the exact semantic decisions remains incomplete. |
| G1 | Open: OpalBase has an authenticated synthetic journal and recovery planner, and Wallet now has production app-owned wallet-secret wipe behavior, but the app has no Mosaic attempt fsync/Keychain/catalog/rollback backend, complete recovery executor, cross-process attempt owner, attempt-material erasure, or genuine fresh-process proof. |
| G2 | Open: OpalFusion has injected relay/NIP-59 contracts, but no concrete authenticated key lifecycle, authoritative relay policy, persistent acknowledgements, reconnect, or Tor-only production adapter. |
| G3 | Open: Wallet is the composition owner and now locks the exact G0 package graph, but it contains no Mosaic session composition and cannot reach OpalBase's internal Mosaic types without a deliberate private boundary. |
| G4 | Open: exact-set CI, complete parser fuzzing, multi-device and traffic-analysis runs, independent external reviews, app runbooks, and operational evidence are absent. |
| G5 | Open: chain states and same-height reorganization identity are absent, and broadcast exclusion is only process-local. No canary approval was requested or granted. |
| G6 | Open: all predecessor evidence and the private-alpha acceptance record are absent. |

## Approvals, Risks, And Disable Procedure

No relay, Tor, Fulcrum, value-movement, mainnet-canary, merge, push, tag, promotion, or publication approval was used during this historical evidence run. Explicit approval of the exact private-deployment.1 semantic decision set has not yet been granted. One narrow toolchain-installation approval allowed Xcode to download the matching Metal Toolchain component after the required local build reported that environment precondition; the download did not contact any Mosaic, wallet, relay, Tor, or chain service. Other external access was limited to ordinary Git and SwiftPM reads required for local freshness and resolution.

Known baseline risks include the accepted alpha.4 off-commitment accountability limitation; low-cost discovery work that must not be described as Sybil resistance; traffic and relay-operator correlation; absent durable Mosaic recovery and attempt-material erasure evidence; missing cross-process broadcast exclusion; incomplete chain reorganization identity; no affirmative hardware Secure Enclave proof in this environment; and lack of independent external assurance. The only permitted wording remains “deterministic mainnet-alpha contract foundation.”

Rollback at this baseline was to revert or discard Wallet task commit `24721909fe901ffe3018cb368690c9536e8128e6` and the isolated package task commits. The Wallet rollback was completed on 2026-08-15. The OpalFusion and OpalBase package commits were first fast-forwarded to their local private `draft` lanes and were subsequently pushed to `private/draft` under explicit approval; no public promotion occurred. Current publication state and exact package revisions are recorded in the [package-layer checkpoint](mosaic-package-layer-checkpoint-2026-08-15.md). Runtime disable remains structural: `.opalMainnetAlpha` is not a package default, `Profile.supportsRuntimeSessionDriver` remains false, and the generic `RuntimeSessionDriver` rejects it. No public application surface was added.

## Non-Proofs

This record does not prove G0 semantic approval or closure, durable Mosaic recovery, concrete Tor routing, circuit independence, relay delivery, anonymity, Mosaic app-session integration, chain reconciliation, broadcast safety, external review closure, mainnet readiness, or private-alpha readiness.
