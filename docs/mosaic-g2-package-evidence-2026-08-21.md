# Mosaic G2 Package Producer Evidence — 2026-08-21

Status: the OpalFusion package-owned G2 transport-bootstrap producer and its recovery-safe application consumer surface are complete at `85635672603832ce9f1e8e62d69e6d4600571440`, extending the original producer at `e07151af7a4f5208153ed37b9533b3de7d8e0628`. G2 remains in progress until Wallet supplies authenticated encrypted persistence, application-owned secret custody, authoritative relay configuration, a concrete Tor-only WebSocket adapter, and the required production-adapter loopback. This record authorizes no external Mosaic network, application session, broadcast, value movement, release, or public claim.

## Decision And Scope

OpalFusion now owns the deterministic protocol and injected-capability boundary between one complete `nostr-tor/0-opal-mainnet-alpha-private-deployment.1` formation and the existing alpha.5 post-manifest runtime. The additive contract is `nostr-tor/0-opal-mosaic-private-alpha-bootstrap.1`, with Nostr selector `nostr-tor/0-opal-mosaic-boot.1`. It leaves all alpha.4, alpha.5, and private-deployment.1 bytes and authorities unchanged.

The package authenticates blind-authorized mailbox distribution, complete-roster consensus, exact NIP-59 publication and recovery, and replay-restored three-source inbox behavior. It receives storage, key custody, relay routes, durable acknowledgement, and replay capabilities from the application; it does not hide application durability behind an in-memory package substitute and does not construct a network stack or a second runtime.

## Exact Package Graph

| Repository | Exact revision | Promoted integration lane |
| --- | --- | --- |
| OpalFusion implementation | `85635672603832ce9f1e8e62d69e6d4600571440` | Recovery-safe consumer accessor extending producer `e07151af7a4f5208153ed37b9533b3de7d8e0628`; promoted on `private/draft` and `public/develop`, with this evidence as a documentation-only successor |
| OpalCrypto | `23425db04075a48405d65cf6a3e2254911e626eb` | `private/draft` and `public/develop` |
| OpalDiagnostics | `7cd2e383309821e01903077c1e534174f9c8a964` | `private/draft` and `public/develop` |

OpalFusion's tracked `Package.resolved` pins OpalCrypto and OpalDiagnostics exactly. Its production package dependencies remain first-party. OpalCrypto owns the new RFC 9474 RSABSSA blind-request restoration and verification, NIP-44, BIP-340, SHA-256, and secure key calculations; OpalFusion owns protocol binding, sequencing, and capability consumption. No external production cryptographic calculation library or direct cryptographic implementation was added above OpalCrypto.

The broader G1 application graph remains Wallet `4eb09a88742d3aeb9efa4a56d031ad15458c87ce`, OpalBase `3eeeb86d41a609f081c1e32e31d0d21ac6ff52e7`, SwiftFulcrum `24b44bb2458822d14121dfbd57321fda7ae539ea`, and the same OpalDiagnostics revision. Wallet does not yet pin this G2 producer revision; that downstream integration is the next G2 slice.

## Implemented Package Boundary

- One complete private-deployment proof binds every bootstrap document to the exact profile pair, deployment selector, mainnet genesis hash, round, relay-set digest, phase start, and wallet-reservation deadline.
- The conductor uses one attempt-exclusive OpalCrypto RSABSSA authorization capability. Contributors expose only blinded requests through their authenticated control claims and redeem finalized tokens through anonymous-return identities. No mailbox private key crosses a canonical document, Nostr event, route capability, or diagnostic boundary.
- The conductor locally generates exactly 23 anonymous recipient capabilities per accepted registration, sends only their public identities, commits six unlabeled bundles, and mints a role-appropriate post-manifest mailbox capability only after all seven roster members acknowledge one complete registration-set digest.
- Canonical decoders reject missing, extra, duplicate, differently bound, noncanonical, expired, incorrectly signed, spent, split-view, or identity-reusing material. Consensus restoration verifies the complete role-appropriate assignment inventory and exact public/private correspondence.
- Every standalone bootstrap role seals and opens through the exact alpha.5 NIP-59 mapping with a caller-owned fresh wrapper key. The publication operation identifier binds authenticated sender and recipient, canonical document and event digests, attempt material, and the exact three endpoints.
- Outbound publication persists the sealed event before route provisioning, requires durable acceptance from at least two of three relays, restores the byte-identical wrapper after restart, opens only unaccepted routes, and closes every route on rejection, source loss, cancellation, or failure.
- Inbound fan-in opens exactly three sources, persists bijective wrapper/message replay facts before semantic admission, deduplicates identical relay copies, restores the exact replay set, and fails closed on source loss, bounded-buffer loss, connection completion, conflicting replay, or cancellation.
- Public Tor connection capabilities require idempotent close behavior that unblocks and joins connection work. The package remains transport-injected; Wallet must still prove that the concrete production adapter cannot fall back to clearnet or local DNS.
- The sole recovered runtime owner exposes the opaque private-deployment proof only after recovery resumes at wallet reservation with a validated manifest and no terminal disposition. Early or incomplete recovery requests fail closed; Wallet no longer needs an internal constructor or `@testable` access to consume the bootstrap producer.

## Environment

- Apple Silicon Mac running macOS 27.0 build `26A5416b`.
- Xcode 27.0 build `27A5237l` from `/Applications/Xcode-beta.app/Contents/Developer`.
- Apple Swift 6.4 `swiftlang-6.4.0.30.4`, target `arm64-apple-macosx27.0.0`.
- Validation was local. No Tor daemon, external relay, Fulcrum service, BCH node, wallet secret, credential, broadcaster, or value-moving endpoint was used.

## Commands And Results

The exact pinned dependency lane passed resolved revision, checkout HEAD, and remote `develop` parity for OpalCrypto `23425db04075a48405d65cf6a3e2254911e626eb` and OpalDiagnostics `7cd2e383309821e01903077c1e534174f9c8a964`:

```text
sh ~/.codex/skills/ops-swiftpm-lane-consistency/scripts/deps-doctor.sh --repo-root "$PWD" --resolved-path Package.resolved --checkouts-root .build/checkouts --lock-mode pinned --remote-check
```

The repository-owned build and focused RSA-free feedback lanes passed on the consumer-surface follow-up:

```text
./scripts/run-validation-loop.sh build
./scripts/run-validation-loop.sh mosaic-fast
```

Result: the exact package build passed. The final-tree `mosaic-fast` rerun passed six tests in two suites in 12.663 seconds after a 0.53-second incremental build.

The new public-consumer gate rejects `@testable import OpalFusion` statically and compiles the exact loaded-owner continuation, resume, and proof-call path:

```text
./scripts/run-validation-loop.sh mosaic-private-alpha-consumer-surface
```

Result: the final-tree rerun passed four tests in one suite in 0.001 seconds after a 0.53-second incremental build. An early-phase proof request failed closed as required; the authoritative SPI aggregate retains successful post-manifest proof restoration.

The original producer's transport-bootstrap aggregate ran serially:

```text
./scripts/run-validation-loop.sh mosaic-private-alpha-transport
```

Result: five tests in one suite passed in 994.479 seconds. The suite canonicalized the relay policy, completed blind registration and role-specific mailbox minting, sealed and opened all seven bootstrap document roles, persisted and recovered one byte-identical publication, and proved exact-three-source fan-in, replay deduplication, source-loss failure, and cleanup.

The original producer's authoritative complete SPI gate ran the existing runtime suite and the new transport suite in one unchanged process:

```text
./scripts/run-validation-loop.sh mosaic-private-alpha-spi
```

Result: 23 tests in two suites passed in 4,976.404 seconds. The existing 18-test SPI composition suite passed in 4,005.622 seconds, including exhaustive signed-formation restoration in 1,697.468 seconds. The five-test transport-bootstrap suite passed in 970.781 seconds, including authenticated blind registration in 824.527 seconds and all-document seal/open coverage in 138.020 seconds.

The recovery-safe consumer follow-up then exercised the same aggregate selection with the runtime/SPI and transport suites isolated in serial SwiftPM processes. All 18 runtime/SPI tests passed in 4,048.211 seconds, including exhaustive signed formation in 1,719.558 seconds. The transport process passed its RSA-free relay-policy case but this macOS 27/Xcode 27 host rejected all four RSA-using cases with `OpalCrypto.RSABSSA.Error.keyGenerationFailed`. A fresh targeted process reproduced the failure after 49.085 seconds, and a direct Security.framework probe rejected an otherwise valid ephemeral RSA-2048 request with `NSOSStatusErrorDomain` code `-50`. Repeating an unchanged hour-long path was therefore stopped.

The smallest remediation was test-only: `RFC9500RSATestKeyFixture` imports RFC 9500's publicly known `testRSA2048` key through Security, then hands the `SecKey` to OpalCrypto for validation and every blind-sign calculation. The fixture is visibly licensed, confined to the test target, and explicitly has no security properties. No production source, API, dependency, algorithm, application key-generation policy, or first-party ownership boundary changed. The validation wrapper now statically rejects direct signing-key generation in this transport lane before starting the expensive aggregate and runs the transport suite in its own process.

The affected final-tree gate then passed:

```text
./scripts/run-validation-loop.sh mosaic-private-alpha-transport
```

Result: five tests in one suite passed in 1,006.535 seconds after a 13.75-second build. Authenticated blind registration passed in 860.148 seconds, all-document seal/open coverage passed in 138.144 seconds, byte-identical publication passed in 7.297 seconds, and exact-three-source fan-in passed in 0.942 seconds. The already successful 18-test runtime/SPI process was not repeated because the remediation changed only test fixture setup, the validation wrapper, and documentation; the original producer's complete 23-test aggregate remains the all-in-one production-path baseline.

Supporting regression runs passed 26 NIP-59 codec and private-envelope tests across three suites in 40.842 seconds; two publication/inbox lifecycle tests in 169.760 seconds; and the all-document bootstrap envelope case in 299.493 seconds. These focused runs covered cancellation while provisioning and awaiting acknowledgement, restoration under the wrong sender, wrapper-identity reuse, invalid timestamps, complete assignment inventory, and route cleanup without false durable acceptance.

Final static checks passed:

```text
git diff --check
zsh -n scripts/run-validation-loop.sh
sh ~/.codex/skills/git-branch-freshness/scripts/check-class-d-public-boundary.sh --repo-root "$PWD"
```

The production dependency scan found only first-party package dependencies and only Foundation, OpalCrypto, and existing first-party imports in the new source. Searches found no unfinished marker or direct production cryptographic calculation. A complexity audit found the canonical validation and capability types proportional to the security contract rather than an accidental abstraction layer. A documentation consistency audit found the profile, deployment contract, protocol specification, security model, README, and progress record aligned on the package/application boundary and remaining G2 obligations.

## Producer Findings

- OpalFusion now supplies the complete package-owned bootstrap protocol needed by a downstream application; Wallet need not invent mailbox-distribution semantics or directly calculate cryptography.
- Blind authorization removes an explicit transcript mapping from contributor control identity to redeemed anonymous-return identity. It does not prevent timing, route, host, or traffic correlation.
- The complete acknowledgement barrier prevents a successfully acknowledged registration-set split view only if Wallet durably enforces authorization-spent identifiers and one acknowledged digest per round under the authenticated G2 record.
- Wrapper freshness, durable publication acceptance, replay state, and application secret custody remain explicit injected capabilities. The package cannot silently weaken or simulate them.
- Package cancellation and restoration paths close routes, preserve exact accepted state, and never mint a mailbox capability around partial or unauthenticated material.
- The OpalFusion producer slice is therefore complete, but G2 is not complete until the application implements and proves the injected production responsibilities.

## Approvals And Promotion

The repository owner explicitly authorized direct work in the existing Opal repositories, commits, pushes, and validated `draft -> develop` promotion for this Mosaic goal. This implementation and its documentation-only evidence successor were promoted through those authorized OpalFusion integration lanes after validation. No `main` promotion, tag, release, new repository, external production dependency, public feature enablement, deployment publication, paid operation, credential use, external Mosaic networking, broadcast, value movement, or canary was authorized or performed.

## Residual Risks And Disable Procedure

Wallet still lacks the G2 schema and authenticated encrypted transport-material persistence, conductor RSA `SecKey` lifecycle, contributor blind-request recovery state, local mailbox and anonymous-return key custody, authorization-spent and single-acknowledged-digest compare-and-set ledgers, sealed-wrapper and per-endpoint acknowledgement journals, replay inventory, authoritative three-operator endpoint registry, and concrete Tor-only WebSocket implementation. It must prove remote DNS, distinct SOCKS authentication or reviewed equivalent isolation, disabled failover, no direct fallback, restart, reconnect, source loss, deadline cancellation, and bounded cleanup through the production adapter in a local loopback under 30 seconds.

Disable remains structural. Wallet does not consume this producer, the generic mainnet driver rejects the private-alpha profile, and no configured relay or public Mosaic session exists. If the producer evidence is invalidated, keep Mosaic disabled, preserve authenticated G1 state and wallet quarantine, stop and join any future route owner, revert or forward-fix through the integration lanes, and rerun the exact producer, downstream pin, persistence, and loopback gates before reopening G2.

## Non-Proofs

This record does not prove application persistence or erasure of G2 secrets, live Keychain custody, a concrete Tor adapter, DNS or clearnet exclusion, circuit or operator independence, relay durability, external relay interoperability, timing privacy, traffic-analysis resistance, anonymity, Sybil resistance, a supervised Wallet session, restart across an application process, wallet safety, chain reconciliation, broadcast safety, canary safety, multi-device reliability, independent review, production readiness, public release readiness, or G2 through G6 closure. Scripted route capabilities and local package cryptography are package evidence only and cannot substitute for the Wallet production-adapter loopback or later assurance gates.
