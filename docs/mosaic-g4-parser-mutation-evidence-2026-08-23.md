# Mosaic G4 Parser-Mutation Evidence — 2026-08-23

Status: `locally verified for the frozen first-party graph`. Bounded first-party deterministic mutation and positive-variant campaigns cover all 52 registered low-level OpalFusion parser files; a machine-checked transitive map covers all nine public transport composite byte parents; and Wallet's application-owned map accounts for the Wallet, OpalBase, and OpalCrypto roots. This is every-parser root accounting, not coverage-guided or exhaustive-input fuzz proof.

## Exact Boundary

| Boundary | Exact revision or object | Meaning |
| --- | --- | --- |
| Public OpalFusion runtime | `79ba5f91449b2c0d5cd6ec73c38fafd58cae0b46` | Production implementation consumed by the frozen Wallet graph |
| Private test-only harness | `7003e40a695912a0e8d0bf15ca0a2c925327c9fc` | First-party deterministic mutation helper, digest-pinned transport and recovery fixtures, and focused parser campaigns |
| `Sources` tree at both revisions | `a66eeb7da5fe12f93988b557a02b34e77e44eba1` | Production source is byte-identical |
| `Package.swift` blob at both revisions | `3d209c7927066513c01f0c7bc2dae76e4d251a01` | Product and dependency declarations are byte-identical |
| `Package.resolved` blob at both revisions | `71253f8b2053c0e7c2aaded796c822ed926119fe` | Exact dependency pins are byte-identical |

`git diff --name-only public/develop..7003e40a695912a0e8d0bf15ca0a2c925327c9fc -- Sources Package.swift Package.resolved` is empty. This private checkpoint does not promote a new OpalFusion runtime or require a Wallet dependency repin.

## First-Party Design

The campaign adds no package or external fuzzing dependency. For compact positive seeds, it applies fixed truncations, zero and maximum-byte prefixes and suffixes, boundary deletions, boundary replacements using `0x00`, `0x01`, `0x7f`, `0x80`, and `0xff`, and deterministic seeded byte-XOR mutations. Failure messages include the stable per-vector seed. Canonical round-trip vectors require any accepted mutation to re-encode byte-identically; relay-frame vectors require successful typed decoding. The helper's default remains the full generated campaign; cryptographically expensive transport roots may opt into a maximum mutation count that deterministically samples the generated list from first to last, preserving structural and seeded regions. The large validated recovery snapshot separately uses one full positive round trip and six exact invalid discriminant mutations. Every seed campaign must exercise at least one rejected mutation.

This is deterministic mutation testing, not a coverage-guided fuzzer, sanitizer campaign, exhaustive input proof, or portable corpus format. It is intentionally small enough for an ordinary focused validation lane and remains test-only.

## Covered Seeds

| Family | Positive seeds exercised |
| --- | --- |
| Nostr event coding | One official signed NIP-13 event and one unsigned kind-78 rumor |
| Padded application envelope | One canonical fixed-width padded envelope |
| Relay server framing | Canonical `NOTICE`, `EOSE`, `CLOSED`, `OK`, and `EVENT` frames |
| Opal v0 canonical wire | Authorization request, authorization response, authorization token, component commitment, grouped commitment, input component, output component, blank component, anonymous component, pre-sign acknowledgement, commitment set, component set, and aggregate fragment |
| Post-manifest canonical wire | Round-manifest core, round manifest, control envelope, anonymous envelope, aggregate reservation, player commit, authorization response set, aggregate fragment, authorization token, anonymous component, pre-sign acknowledgement submission and set, BCH signature submission and set, and complete-transaction payload |
| Private-deployment canonical documents | Opaque pool, relay registration, relay set, availability-beacon core and document, candidate-set acknowledgement and set, candidate admission, contributor nonce allocation, role commitment, role reveal, manifest proposal, manifest signature, abort context and document, completion document, and pre-manifest Nostr payload |
| Typed private-deployment Nostr mapping | Availability beacon, candidate-set acknowledgement, candidate admission, role commitment, role reveal, context-validating manifest-proposal candidate, typed manifest proposal, manifest signature, contributor nonce allocation, abort, and completion events |
| Private runtime recovery | Fresh-attempt and validated-manifest snapshots plus positive equivocation, invalid-authenticated-message, formation-publication, terminal-publication, pre-manifest authorized-terminal, post-manifest publication-terminal, and post-manifest authorized-terminal snapshots; the base campaigns also reject invalid phase, abort-cause, manifest, journal, publication, and terminal discriminants |
| Post-manifest NIP-59 composite opens | One control and one anonymous deterministic gift wrap traversing outer event decoding, NIP-59 seal and rumor opening, fixed application-content padding, canonical envelope decoding, identity binding, and timing validation |
| Private event and terminal recovery | One private-deployment event recovery record, abort and completion terminal-record variants, and one terminal-evidence value |
| Durable post-manifest journals | One admission snapshot containing control and anonymous records, plus drained control and anonymous publication snapshots containing prepared, publication-permitted, attempted, acknowledged, and completed records |
| Transport bootstrap | Authorization key, control claim and set, blind-response set, anonymous request input, registration and set, assignment, acknowledgement, and acknowledgement set restored against a digest-pinned production-graph proof |

The current OpalFusion campaign therefore contains 92 positive seeds across 24 focused parser test bodies: the prior 75 seeds across twelve mutation bodies, ten transport-bootstrap seeds across nine mutation bodies, and seven recovery-variant seeds across three positive-discriminant bodies. Existing targeted positive, negative, and deterministic parser-mutation tests elsewhere in the package remain valid evidence, but they are not relabeled as part of this campaign.

A simple source inventory finds 93 declarations containing `func decode` under `Sources/OpalFusion/Mosaic`, but that spelling-based number includes helpers and misses byte entrypoints named `load`, `restore`, `open`, or `validate`. The [parser-root registry](mosaic-g4-parser-root-registry-2026-08-23.md) freezes the 52 production files that directly invoke the canonical or JSON decoder substrate, and the machine-checked [root map](mosaic-g4-parser-root-map-2026-08-23.txt) assigns all 52 to covered with zero partial-variant and zero closure-budget dispositions. That map is not cross-repository or composite closure: overloaded functions, context-specific parent entrypoints, and raw cryptographic or application envelopes still require reviewed accounting. The 92 seeds are not claimed as a coverage fraction.

## Focused Validation

The evidence commands ran with live-network and Electron Cash interop controls absent, used the resolved first-party dependency graph, disabled parallel test execution, selected only affected test bodies, and did not fall back to a full package run. The initial combined selector was:

```sh
env -u OPAL_RUN_LIVE_NETWORK_TESTS -u OPAL_FULCRUM_URL -u OPALFUSION_EC_INTEROP swift test --force-resolved-versions --no-parallel --filter 'MosaicMainnetAlphaParserMutationValidator|MosaicMainnetAlphaPrivateCanonicalContractValidator/rejectMalformedCanonicalDocumentsWithDeterministicBounds'
```

The first run exposed a test-fixture round-identifier mismatch in the expanded post-manifest body. After that localized correction, only the failed body was rerun. A later test-only helper refactor produced compile diagnostics for overloaded decoder references before any test executed; after explicit closures corrected those diagnostics, only the changed Opal v0 body was rerun. A subsequent terminal-recovery selector initially reused an event outside that codec's tag-element limit; after replacing it with a deterministic first-party signed event matching the contract, only that failed selector was rerun. The unaffected passing results were retained.

| Test body | Passing result | Evidence origin |
| --- | --- | --- |
| Signed Nostr events, padded envelope, and relay server frames | Passed in 0.629 seconds | Initial combined selector; unchanged afterward |
| Opal v0 canonical wire parsers | Passed in 19.686 seconds | Final affected-selector rerun after the test-helper refactor |
| Core post-manifest canonical wire parsers | Passed in 31.645 seconds | Affected-selector rerun after the fixture correction |
| Private-deployment canonical documents | Passed in 36.261 seconds | Initial combined selector; unchanged afterward |
| Private-alpha recovery snapshot | Passed in 0.001 seconds | Initial combined selector; unchanged afterward |
| Private event and terminal recovery parsers | Passed in 2.776 seconds | Final affected-selector rerun after the localized fixture correction |
| Durable admission recovery parser | Passed in 4.395 seconds | New affected selector |
| Durable control and anonymous publication recovery parser | Passed in 6.848 seconds | Affected selector rerun after adding the publication-permit record |
| Ten typed pre-manifest Nostr parser roots | Passed in 20.003 seconds | Affected selector rerun after adding the manifest-proposal-candidate root |
| Typed completion Nostr parser | Passed in 19.812 seconds | New isolated affected selector |
| Validated-manifest runtime recovery discriminants | Passed in 58.999 seconds | Shortened affected selector after the generic mutation loop exceeded budget |
| Control and anonymous NIP-59 composite open roots | Passed in 5.371 seconds | New isolated affected selector |

The transport closure uses `Tests/Fixtures/MosaicG4PinnedParserFixture.json`, SHA-256 `061ae11cc5415bbe414ab6745f65389b2eab009424c89389eac45eda577a307f`. Its metadata binds public OpalFusion revision `79ba5f91449b2c0d5cd6ec73c38fafd58cae0b46` and source fixture SHA-256 `ec6755c6cf6a736ddf8538d32e0fa48afc247342fe6a4a424d826a0a62f2ee7a`. The checked fixture restores the exact proof and verifies the component and BCH-signature RSA public keys without regenerating RSA material, networking, or value-bearing state. Its independent restore selector passed in 12.592 seconds.

| Transport mutation body | Passing result | Mutation budget |
| --- | --- | --- |
| Authorization key and control claim | Passed in 40.426 seconds | Full structural matrix plus 16 seeded mutations per seed |
| Control claim set | Passed in 49.561 seconds | Full structural matrix plus 16 seeded mutations |
| Blind-response set | Passed in 59.231 seconds | Full structural matrix plus 16 seeded mutations |
| Anonymous request input | Passed in 38.326 seconds | Full structural matrix plus 16 seeded mutations |
| Anonymous registration | Passed in 50.575 seconds | Twelve evenly distributed mutations selected from the full generated campaign |
| Registration set | Passed in 51.438 seconds | Twelve evenly distributed mutations selected from the full generated campaign |
| Anonymous assignment | Passed in 52.122 seconds | Twelve evenly distributed mutations selected from the full generated campaign |
| Registration acknowledgement | Passed in 51.226 seconds | Twelve evenly distributed mutations selected from the full generated campaign |
| Registration acknowledgement set | Passed in 49.757 seconds | Fixture-prevalidated positive seed plus empty truncation and a deterministic seeded byte mutation |

Recovery-variant closure additionally uses `Tests/Fixtures/MosaicG4PinnedRecoveryEvents.json`, SHA-256 `1270a4fba57549d3a84567cbef4268b9cbfaa463b5d9c3a32343ad0fc7b07f53`. It contains only a public signed conflicting-admission record and its matching public abort record, binds the transport fixture digest above, and contains no private key. A one-time first-party generator constructed and fully validated both records in 87.767 seconds inside the single 600-second closure lane, then was removed from the permanent suite.

| Recovery-variant body | Passing result | Positive discriminants |
| --- | --- | --- |
| Pre-manifest variants | Passed in 32.550 seconds | Equivocation, invalid authenticated message, formation publication, terminal publication, and authorized terminal |
| Post-manifest publication terminal | Passed in 29.272 seconds | Locally published completion evidence with active terminal state |
| Post-manifest authorized terminal | Passed in 29.330 seconds | Locally published completion evidence after publication acknowledgement |

All 24 selected OpalFusion parser test bodies therefore have preserved or new passing evidence at private test harness `7003e40a695912a0e8d0bf15ca0a2c925327c9fc`. They were not rerun as one final combined command, so no combined elapsed time or single-run `24/24` result is claimed. This follows the cost-bounded validation policy: preserve still-valid passes and rerun only a failed or subsequently changed selector. After adding the optional mutation cap, the unchanged full-campaign default path was rechecked through `mutateNostrEventAndRelayParsers` and passed in 0.625 seconds.

The static registry command `scripts/check-mosaic-g4-parser-root-registry.sh` passes both maps: 52 low-level files at 52-covered / 0-partial-variant / 0-closure-budget and nine public transport composite parents. The composite map binds generic NIP-59 mutation coverage, each typed transport-document mutation target, and the positive/negative integration cases in `MosaicPrivateAlphaTransportBootstrapValidator`. Git object comparison proves the three composite production files and that integration test file are byte-identical between passing G2 checkpoint `117949b08f354f5a58b78075dbf14b2ec4e4f88f` and frozen runtime `79ba5f91449b2c0d5cd6ec73c38fafd58cae0b46`; the preserved G2 results include all-document seal/open in 138.144 seconds and byte-identical publication in 7.297 seconds. No unchanged RSA-heavy selector was rerun.

Wallet's cross-repository evidence adds ten positive seeds across four passing bodies for Wallet and OpalBase, maps the two remaining OpalBase network-policy roots to existing deterministic matrices, and maps every consumed OpalCrypto parser to a mutated parent or exact contract test. The frozen-graph corpus therefore accounts for 102 positive seeds across 28 focused parser bodies. This number is corpus accounting, not a coverage percentage.

The runs used Swift Testing library version 2077 on `arm64e-apple-macos14.0`. No external endpoint, credential, paid service, wallet secret, broadcast, or value movement was used. Automatic retry was not enabled. SwiftPM sandbox failures occurred before tests could run and are not counted as execution evidence. The first generic validated-recovery mutation attempt was manually stopped after approximately 70 seconds; it was not rerun unchanged. The focused six-discriminant replacement is the recorded result.

## Closure And Future Drift

No known parser root remains unassigned in the frozen Wallet, OpalBase, OpalCrypto, or OpalFusion graph. Private helper decoders are mapped transitively through named externally reachable parents rather than receiving redundant seeds, and the two freshness maps make new low-level files or public transport composite entrypoints mutation-blocking until reviewed.

Future parser or corpus changes must run only their affected selectors and both registry gates, preserving the same deterministic seeds and typed rejection or stable-recanonicalization oracle. Add a new seed only when a parent introduces an independently reachable acceptance boundary. If the bounded deterministic campaign cannot supply defensible evidence for a future root, the project must add a first-party coverage-guided harness or another first-party fuzz lane. Adding an external production dependency is not authorized or necessary.

A transport-bootstrap experiment confirmed that its existing runtime-generated RSA fixture does not fit the ordinary 60-second parser lane. A nine-root positive-plus-trailing body, a nine-root positive-only body, and a three-root authority-only body were each manually stopped after crossing the ceiling; none produced a test result, none was retried unchanged, and the unvalidated test edits were removed. The digest-pinned first-party fixture above replaced those shapes. During selector sizing, multi-root bodies and over-budget acknowledgement-set configurations were likewise stopped once and split or reduced rather than retried unchanged; the final passing budgets are the only positive results claimed.

## Non-Proofs And Gate Effect

This evidence changes the parser-fuzz lane from `Partial` to `Verified Local` for the frozen graph. It does not complete simulator fault injection, exact-graph package CI, supported-environment traffic analysis, multi-device reliability, the signed runbook drill, independent review, G4, G5, or G6. It does not prove memory safety, side-channel resistance, cryptographic correctness, interoperability, anonymity, relay or circuit independence, production readiness, or public profile safety.

Mosaic remains non-live. The public OpalFusion runtime, Wallet graph, protocol profiles, disable boundary, networking authorization, broadcast authority, and value-movement boundary are unchanged.
