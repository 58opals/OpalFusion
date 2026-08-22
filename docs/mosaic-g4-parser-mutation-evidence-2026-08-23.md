# Mosaic G4 Parser-Mutation Evidence — 2026-08-23

Status: `partial`. A bounded first-party deterministic mutation campaign now covers an initial set of Mosaic parsers, but the G4 requirement for fuzzing to cover every parser remains open.

## Exact Boundary

| Boundary | Exact revision or object | Meaning |
| --- | --- | --- |
| Public OpalFusion runtime | `79ba5f91449b2c0d5cd6ec73c38fafd58cae0b46` | Production implementation consumed by the frozen Wallet graph |
| Private test-only harness | `836dd517efc12f12c5f348caf7031a4520c1032c` | First-party deterministic mutation helper, expanded focused parser campaign, and test-fixture visibility change |
| `Sources` tree at both revisions | `a66eeb7da5fe12f93988b557a02b34e77e44eba1` | Production source is byte-identical |
| `Package.swift` blob at both revisions | `3d209c7927066513c01f0c7bc2dae76e4d251a01` | Product and dependency declarations are byte-identical |
| `Package.resolved` blob at both revisions | `71253f8b2053c0e7c2aaded796c822ed926119fe` | Exact dependency pins are byte-identical |

`git diff --name-only public/develop..836dd517efc12f12c5f348caf7031a4520c1032c -- Sources Package.swift Package.resolved` is empty. This private checkpoint does not promote a new OpalFusion runtime or require a Wallet dependency repin.

## First-Party Design

The campaign adds no package or external fuzzing dependency. For each nonempty positive seed, it applies fixed truncations, zero and maximum-byte prefixes and suffixes, boundary deletions, boundary replacements using `0x00`, `0x01`, `0x7f`, `0x80`, and `0xff`, and 64 deterministic seeded byte-XOR mutations. Failure messages include the stable per-vector seed. Canonical round-trip vectors require any accepted mutation to re-encode byte-identically; relay-frame vectors require successful typed decoding. Every seed campaign must exercise at least one rejected mutation.

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
| Private runtime recovery | One fresh-attempt recovery snapshot bound to exact attempt, generation, and material identifiers |

The current campaign therefore contains 54 positive seeds across five focused test bodies in two suites: 8 Nostr, padded-envelope, and relay-frame seeds; 13 Opal v0 seeds; 15 post-manifest wire seeds; 17 private-deployment document seeds; and 1 runtime-recovery seed. Existing targeted positive, negative, and deterministic parser-mutation tests elsewhere in the package remain valid evidence, but they are not relabeled as part of this campaign.

A simple source inventory finds 93 declarations containing `func decode` under `Sources/OpalFusion/Mosaic`. That number is only an implementation-level upper bound: overloaded functions, context-specific variants, and private helper decoders can share one externally reachable parser root, while some parsing entrypoints do not use that spelling. G4 still needs a reviewed parser-root registry that maps every reachable root to a fuzz target and corpus; the 54 seeds are not claimed as 54 of 93 complete coverage.

## Focused Validation

The evidence commands ran with live-network and Electron Cash interop controls absent, used the resolved first-party dependency graph, disabled parallel test execution, selected only affected test bodies, and did not fall back to a full package run. The initial combined selector was:

```sh
env -u OPAL_RUN_LIVE_NETWORK_TESTS -u OPAL_FULCRUM_URL -u OPALFUSION_EC_INTEROP swift test --force-resolved-versions --no-parallel --filter 'MosaicMainnetAlphaParserMutationValidator|MosaicMainnetAlphaPrivateCanonicalContractValidator/rejectMalformedCanonicalDocumentsWithDeterministicBounds'
```

The first run exposed a test-fixture round-identifier mismatch in the expanded post-manifest body. After that localized correction, only the failed body was rerun. A later test-only helper refactor produced compile diagnostics for overloaded decoder references before any test executed; after explicit closures corrected those diagnostics, only the changed Opal v0 body was rerun. The unaffected passing results from the combined run were retained.

| Test body | Passing result | Evidence origin |
| --- | --- | --- |
| Signed Nostr events, padded envelope, and relay server frames | Passed in 0.629 seconds | Initial combined selector; unchanged afterward |
| Opal v0 canonical wire parsers | Passed in 19.686 seconds | Final affected-selector rerun after the test-helper refactor |
| Core post-manifest canonical wire parsers | Passed in 31.645 seconds | Affected-selector rerun after the fixture correction |
| Private-deployment canonical documents | Passed in 36.261 seconds | Initial combined selector; unchanged afterward |
| Private-alpha recovery snapshot | Passed in 0.001 seconds | Initial combined selector; unchanged afterward |

All five selected test bodies therefore have passing evidence at `836dd517efc12f12c5f348caf7031a4520c1032c`. They were not rerun as one final combined command, so no combined elapsed time or single-run `5/5` result is claimed. This follows the cost-bounded validation policy: preserve still-valid passes and rerun only a failed or subsequently changed selector.

The runs used Swift Testing library version 2077 on `arm64e-apple-macos14.0`. No external endpoint, credential, paid service, wallet secret, broadcast, or value movement was used. Automatic retry was not enabled. An earlier sandbox failure occurred before SwiftPM could run tests, and development-only compiler diagnostics executed no tests; neither is counted as execution evidence.

## Remaining Parser Work

This slice does not satisfy “every parser.” Known families not yet fully represented by the focused campaign include pre-manifest Nostr outer-event and typed-payload roots, remaining bootstrap documents, durable admission and publication journals, terminal record and terminal-evidence formats, event-recovery records, and the corresponding OpalCrypto, OpalBase, and Wallet persistence/parser surfaces. Private helper decoders covered transitively through a root still need an explicit mapping rather than another redundant seed. The authoritative cross-repository inventory remains application-owned and must be reconciled before the parser-fuzz manifest stage can become complete.

The next package slice should extend the same first-party helper only where it fits the parser contract, preserve deterministic seeds and focused selectors, and checkpoint before any RSA-heavy construction. Every parser still requires explicit fuzz-coverage evidence; if the bounded deterministic campaign cannot supply that evidence, the project must add a first-party coverage-guided harness or another defensible first-party fuzz lane. Adding an external production dependency is not authorized or necessary.

## Non-Proofs And Gate Effect

This evidence changes the parser-fuzz lane from `Pending implementation` to `Partial`. It does not complete golden vectors, simulator fault injection, exact-graph package CI, supported-environment traffic analysis, multi-device reliability, the signed runbook drill, independent review, G4, G5, or G6. It does not prove memory safety, side-channel resistance, cryptographic correctness, interoperability, anonymity, relay or circuit independence, production readiness, or public profile safety.

Mosaic remains non-live. The public OpalFusion runtime, Wallet graph, protocol profiles, disable boundary, networking authorization, broadcast authority, and value-movement boundary are unchanged.
