# Mosaic G4 Parser-Mutation Evidence — 2026-08-23

Status: `locally verified for the dated package surface`. Bounded first-party deterministic mutation and positive-variant campaigns cover all 52 registered low-level OpalFusion parser files; a machine-checked transitive map covers all nine public transport composite byte parents. This is every-parser root accounting, not coverage-guided or exhaustive-input fuzz proof.

## Exact Boundary

| Boundary | Exact revision or object | Meaning |
| --- | --- | --- |
| Public OpalFusion runtime | `79ba5f91449b2c0d5cd6ec73c38fafd58cae0b46` | Production implementation underlying this dated evidence |
| Test-only harness | `7003e40a695912a0e8d0bf15ca0a2c925327c9fc` | First-party deterministic mutation helper, digest-pinned transport and recovery fixtures, and focused parser campaigns |
| `Sources` tree at both revisions | `a66eeb7da5fe12f93988b557a02b34e77e44eba1` | Production source is byte-identical |
| `Package.swift` blob at both revisions | `3d209c7927066513c01f0c7bc2dae76e4d251a01` | Product and dependency declarations are byte-identical |
| `Package.resolved` blob at both revisions | `71253f8b2053c0e7c2aaded796c822ed926119fe` | Exact dependency pins are byte-identical |

`git diff --name-only 79ba5f91449b2c0d5cd6ec73c38fafd58cae0b46 7003e40a695912a0e8d0bf15ca0a2c925327c9fc -- Sources Package.swift Package.resolved` is empty. The evidence covers a test-only change with identical production source and dependency declarations.

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

Recovery-variant closure additionally uses `Tests/Fixtures/MosaicG4PinnedRecoveryEvents.json`, SHA-256 `1270a4fba57549d3a84567cbef4268b9cbfaa463b5d9c3a32343ad0fc7b07f53`. It contains only a public signed conflicting-admission record and its matching public abort record, binds the transport fixture digest above, and contains no private key. A one-time first-party generator constructed and fully validated both records in 87.767 seconds in a bounded fixture-generation run, then was removed from the permanent suite.

| Recovery-variant body | Passing result | Positive discriminants |
| --- | --- | --- |
| Pre-manifest variants | Passed in 32.550 seconds | Equivocation, invalid authenticated message, formation publication, terminal publication, and authorized terminal |
| Post-manifest publication terminal | Passed in 29.272 seconds | Locally published completion evidence with active terminal state |
| Post-manifest authorized terminal | Passed in 29.330 seconds | Locally published completion evidence after publication acknowledgement |

All 24 selected OpalFusion parser test bodies therefore have preserved or new passing evidence at test harness `7003e40a695912a0e8d0bf15ca0a2c925327c9fc`. They were not rerun as one final combined command, so no combined elapsed time or single-run `24/24` result is claimed. After adding the optional mutation cap, the unchanged full-campaign default path was rechecked through `mutateNostrEventAndRelayParsers` and passed in 0.625 seconds.

The static registry command `scripts/check-mosaic-g4-parser-root-registry.sh` passes both maps: 52 low-level files at 52-covered / 0-partial-variant / 0-closure-budget and nine public transport composite parents. The composite map binds generic NIP-59 mutation coverage, each typed transport-document mutation target, and the positive/negative integration cases in `MosaicPrivateAlphaTransportBootstrapValidator`. Git object comparison proves the three composite production files and that integration test file are byte-identical between passing integration revision `117949b08f354f5a58b78075dbf14b2ec4e4f88f` and frozen runtime `79ba5f91449b2c0d5cd6ec73c38fafd58cae0b46`; the preserved integration results include all-document seal/open in 138.144 seconds and byte-identical publication in 7.297 seconds.

The runs used Swift Testing library version 2077 on `arm64e-apple-macos14.0`, with no live-network or value-moving tests. Pre-execution failures and stopped experiments are excluded from the passing evidence; the tables above identify the passing selectors and their measured results.

## Closure And Future Drift

No known package-owned parser root remains unassigned in the dated OpalFusion maps. Consumer parser roots require separate accounting. Private helper decoders are mapped transitively through named externally reachable parents rather than receiving redundant seeds, and the two freshness maps make new low-level files or public transport composite entrypoints mutation-blocking until reviewed.

Future parser or corpus changes must validate affected selectors and both registry maps, preserving deterministic seeds and the typed rejection or stable-recanonicalization oracle. Add a seed when a parent introduces an independently reachable acceptance boundary. A deterministic campaign that cannot provide defensible evidence for a root needs stronger first-party fuzz coverage before live-profile enablement. See [Validation](validation.md) for the required full and focused package checks.

## Limits Of This Evidence

This is dated deterministic package parser evidence. It does not establish coverage-guided or exhaustive-input fuzzing, memory safety, side-channel resistance, cryptographic correctness, interoperability, anonymity, relay or circuit independence, application recovery, deployment reliability, independent review, or production readiness. Consumer applications must validate their own parser roots and composed dependencies.

Mosaic remains non-live. These tests do not enable a public session or alter protocol profiles, broadcast authority, or value-movement boundaries.
