# Mosaic G4 Parser-Mutation Evidence — 2026-08-23

Status: `partial`. A bounded first-party deterministic mutation campaign now covers an initial set of Mosaic parsers, but the G4 requirement for fuzzing to cover every parser remains open.

## Exact Boundary

| Boundary | Exact revision or object | Meaning |
| --- | --- | --- |
| Public OpalFusion runtime | `79ba5f91449b2c0d5cd6ec73c38fafd58cae0b46` | Production implementation consumed by the frozen Wallet graph |
| Private test-only harness | `103c85918e84328600b876647c4c17f8951d0dc4` | First-party deterministic mutation helper, expanded focused parser campaign, and test-fixture visibility change |
| `Sources` tree at both revisions | `a66eeb7da5fe12f93988b557a02b34e77e44eba1` | Production source is byte-identical |
| `Package.swift` blob at both revisions | `3d209c7927066513c01f0c7bc2dae76e4d251a01` | Product and dependency declarations are byte-identical |
| `Package.resolved` blob at both revisions | `71253f8b2053c0e7c2aaded796c822ed926119fe` | Exact dependency pins are byte-identical |

`git diff --name-only public/develop..103c85918e84328600b876647c4c17f8951d0dc4 -- Sources Package.swift Package.resolved` is empty. This private checkpoint does not promote a new OpalFusion runtime or require a Wallet dependency repin.

## First-Party Design

The campaign adds no package or external fuzzing dependency. For compact positive seeds, it applies fixed truncations, zero and maximum-byte prefixes and suffixes, boundary deletions, boundary replacements using `0x00`, `0x01`, `0x7f`, `0x80`, and `0xff`, and 64 deterministic seeded byte-XOR mutations. Failure messages include the stable per-vector seed. Canonical round-trip vectors require any accepted mutation to re-encode byte-identically; relay-frame vectors require successful typed decoding. The large validated recovery snapshot instead uses one full positive round trip and six exact invalid discriminant mutations because the generic loop exceeded the ordinary 60-second budget. Every seed campaign must exercise at least one rejected mutation.

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
| Private runtime recovery | One fresh-attempt recovery snapshot plus one validated-manifest, initialized-journal snapshot bound to exact attempt, generation, and material identifiers; the latter also rejects invalid phase, abort-cause, manifest, journal, publication, and terminal discriminants |
| Post-manifest NIP-59 composite opens | One control and one anonymous deterministic gift wrap traversing outer event decoding, NIP-59 seal and rumor opening, fixed application-content padding, canonical envelope decoding, identity binding, and timing validation |
| Private event and terminal recovery | One private-deployment event recovery record, abort and completion terminal-record variants, and one terminal-evidence value |
| Durable post-manifest journals | One admission snapshot containing control and anonymous records, plus drained control and anonymous publication snapshots containing prepared, publication-permitted, attempted, acknowledged, and completed records |

The current campaign therefore contains 75 positive seeds across twelve focused test bodies in six suites: 8 Nostr, padded-envelope, and relay-frame seeds; 13 Opal v0 seeds; 15 post-manifest wire seeds; 17 private-deployment document seeds; 11 typed pre-manifest and completion Nostr seeds; 2 runtime-recovery seeds; 2 post-manifest NIP-59 composite seeds; 4 private event and terminal-recovery seeds; and 3 durable journal seeds. Existing targeted positive, negative, and deterministic parser-mutation tests elsewhere in the package remain valid evidence, but they are not relabeled as part of this campaign.

A simple source inventory finds 93 declarations containing `func decode` under `Sources/OpalFusion/Mosaic`, but that spelling-based number includes helpers and misses byte entrypoints named `load`, `restore`, `open`, or `validate`. The [parser-root registry](mosaic-g4-parser-root-registry-2026-08-23.md) freezes the 52 production files that directly invoke the canonical or JSON decoder substrate, and the machine-checked [root map](mosaic-g4-parser-root-map-2026-08-23.txt) assigns them 41 covered, three partial-variant, and eight closure-budget dispositions. That map is not cross-repository closure: overloaded functions, context-specific variants, composite parents, and raw cryptographic or application envelopes still require reviewed accounting. The 75 seeds are not claimed as a coverage fraction.

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

All twelve selected test bodies therefore have passing evidence at `103c85918e84328600b876647c4c17f8951d0dc4`. They were not rerun as one final combined command, so no combined elapsed time or single-run `12/12` result is claimed. This follows the cost-bounded validation policy: preserve still-valid passes and rerun only a failed or subsequently changed selector. The static registry command `scripts/check-mosaic-g4-parser-root-registry.sh` also passed for its frozen 52-file implementation surface and exact 41-covered / 3-partial-variant / 8-closure-budget root-map disposition.

The runs used Swift Testing library version 2077 on `arm64e-apple-macos14.0`. No external endpoint, credential, paid service, wallet secret, broadcast, or value movement was used. Automatic retry was not enabled. SwiftPM sandbox failures occurred before tests could run and are not counted as execution evidence. The first generic validated-recovery mutation attempt was manually stopped after approximately 70 seconds; it was not rerun unchanged. The focused six-discriminant replacement is the recorded result.

## Remaining Parser Work

This slice does not satisfy “every parser.” The manifest-proposal-candidate root, validated-manifest plus initialized-journal recovery discriminants, control and anonymous NIP-59 composite opens, application-content extraction, and publication-permit journal record are now covered. Known OpalFusion work still includes positive pre-manifest abort, publication formation and terminal, and authorized terminal recovery discriminants; transport-bootstrap document and envelope roots; and remaining composite validation or relay-restoration byte entrypoints. The corresponding OpalCrypto, OpalBase, and Wallet persistence/parser surfaces remain open. Private helper decoders covered transitively through a root still need an explicit mapping rather than another redundant seed. The authoritative cross-repository inventory remains application-owned and must be reconciled before the parser-fuzz manifest stage can become complete.

The next package slice should extend the same first-party helper only where it fits the parser contract, preserve deterministic seeds and focused selectors, and checkpoint before any RSA-heavy construction. Every parser still requires explicit fuzz-coverage evidence; if the bounded deterministic campaign cannot supply that evidence, the project must add a first-party coverage-guided harness or another defensible first-party fuzz lane. Adding an external production dependency is not authorized or necessary.

A subsequent transport-bootstrap experiment confirmed that its existing runtime-generated RSA fixture does not fit the ordinary 60-second parser lane. A nine-root positive-plus-trailing body, a nine-root positive-only body, and a three-root authority-only body were each manually stopped after crossing the ceiling; none produced a test result, none was retried unchanged, and the unvalidated test edits were removed. Do not repeat those shapes. Bootstrap parser closure must instead consume a digest-pinned fixture generated by the first-party stack or run once inside the existing 600-second closure campaign, with its fixture-generation and parser timings separated.

## Non-Proofs And Gate Effect

This evidence changes the parser-fuzz lane from `Pending implementation` to `Partial`. It does not complete golden vectors, simulator fault injection, exact-graph package CI, supported-environment traffic analysis, multi-device reliability, the signed runbook drill, independent review, G4, G5, or G6. It does not prove memory safety, side-channel resistance, cryptographic correctness, interoperability, anonymity, relay or circuit independence, production readiness, or public profile safety.

Mosaic remains non-live. The public OpalFusion runtime, Wallet graph, protocol profiles, disable boundary, networking authorization, broadcast authority, and value-movement boundary are unchanged.
