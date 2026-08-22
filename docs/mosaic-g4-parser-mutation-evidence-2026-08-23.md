# Mosaic G4 Parser-Mutation Evidence — 2026-08-23

Status: `partial`. A bounded first-party deterministic mutation campaign now covers an initial set of Mosaic parsers, but the G4 requirement for fuzzing to cover every parser remains open.

## Exact Boundary

| Boundary | Exact revision or object | Meaning |
| --- | --- | --- |
| Public OpalFusion runtime | `79ba5f91449b2c0d5cd6ec73c38fafd58cae0b46` | Production implementation consumed by the frozen Wallet graph |
| Private test-only harness | `8ba234e7a841cee6e5ccbf14dd37068f53dcd6e5` | First-party deterministic mutation helper, focused parser campaign, and test-fixture visibility change |
| `Sources` tree at both revisions | `a66eeb7da5fe12f93988b557a02b34e77e44eba1` | Production source is byte-identical |
| `Package.swift` blob at both revisions | `3d209c7927066513c01f0c7bc2dae76e4d251a01` | Product and dependency declarations are byte-identical |
| `Package.resolved` blob at both revisions | `71253f8b2053c0e7c2aaded796c822ed926119fe` | Exact dependency pins are byte-identical |

`git diff --name-only public/develop..8ba234e7a841cee6e5ccbf14dd37068f53dcd6e5 -- Sources Package.swift Package.resolved` is empty. This private checkpoint does not promote a new OpalFusion runtime or require a Wallet dependency repin.

## First-Party Design

The campaign adds no package or external fuzzing dependency. For each nonempty positive seed, it applies fixed truncations, zero and maximum-byte prefixes and suffixes, boundary deletions, boundary replacements using `0x00`, `0x01`, `0x7f`, `0x80`, and `0xff`, and 64 deterministic seeded byte-XOR mutations. Failure messages include the stable per-vector seed. Canonical round-trip vectors require any accepted mutation to re-encode byte-identically; relay-frame vectors require successful typed decoding. Every seed campaign must exercise at least one rejected mutation.

This is deterministic mutation testing, not a coverage-guided fuzzer, sanitizer campaign, exhaustive input proof, or portable corpus format. It is intentionally small enough for an ordinary focused validation lane and remains test-only.

## Covered Seeds

| Family | Positive seeds exercised |
| --- | --- |
| Nostr event coding | One official signed NIP-13 event and one unsigned kind-78 rumor |
| Padded application envelope | One canonical fixed-width padded envelope |
| Relay server framing | Canonical `NOTICE`, `EOSE`, `CLOSED`, `OK`, and `EVENT` frames |
| Post-manifest canonical wire | Round manifest, control envelope, anonymous envelope, aggregate reservation, player commit, aggregate fragment, authorization token, pre-sign acknowledgement submission and set, BCH signature submission and set |
| Private runtime recovery | One fresh-attempt recovery snapshot bound to exact attempt, generation, and material identifiers |

The current campaign therefore contains 20 positive seeds across three focused tests. Existing targeted positive, negative, and deterministic parser-mutation tests elsewhere in the package remain valid evidence, but they are not relabeled as part of this campaign.

## Focused Validation

The final evidence command ran with live-network and Electron Cash interop controls absent, used the resolved first-party dependency graph, disabled parallel test execution, selected only this suite, and did not fall back to a full package run:

```sh
env -u OPAL_RUN_LIVE_NETWORK_TESTS -u OPAL_FULCRUM_URL -u OPALFUSION_EC_INTEROP swift test --force-resolved-versions --no-parallel --filter MosaicMainnetAlphaParserMutationValidator
```

| Test | Result |
| --- | --- |
| Signed Nostr events and relay server frames | Passed in 0.625 seconds |
| Core post-manifest canonical wire parsers | Passed in 31.680 seconds |
| Private-alpha recovery snapshots | Passed in 0.001 seconds |
| Total | 3 of 3 passed in 32.307 seconds |

The run used Swift Testing library version 2077 on `arm64e-apple-macos14.0`. No external endpoint, credential, paid service, wallet secret, broadcast, or value movement was used. Automatic retry was not enabled.

An initial sandbox failure occurred before SwiftPM could run the tests. Subsequent compiler diagnostics exposed missing `try` propagation and one optional fixture count; those development-only compile failures executed no test. The passing final selector above is the evidence result.

## Remaining Parser Work

This slice does not satisfy “every parser.” Known families not yet represented by this focused harness include remaining pre-manifest typed and document codecs, Opal v0 primitive and aggregate codecs, authorization request, response, and response-set codecs, anonymous-component and complete-transaction codecs, durable admission and publication journals, terminal record and evidence formats, and the corresponding OpalCrypto, OpalBase, and Wallet persistence/parser surfaces. The authoritative cross-repository inventory remains application-owned and must be reconciled before the parser-fuzz manifest stage can become complete.

The next package slice should extend the same first-party helper only where it fits the parser contract, preserve deterministic seeds and focused selectors, and checkpoint before any RSA-heavy construction. Every parser still requires explicit fuzz-coverage evidence; if the bounded deterministic campaign cannot supply that evidence, the project must add a first-party coverage-guided harness or another defensible first-party fuzz lane. Adding an external production dependency is not authorized or necessary.

## Non-Proofs And Gate Effect

This evidence changes the parser-fuzz lane from `Pending implementation` to `Partial`. It does not complete golden vectors, simulator fault injection, exact-graph package CI, supported-environment traffic analysis, multi-device reliability, the signed runbook drill, independent review, G4, G5, or G6. It does not prove memory safety, side-channel resistance, cryptographic correctness, interoperability, anonymity, relay or circuit independence, production readiness, or public profile safety.

Mosaic remains non-live. The public OpalFusion runtime, Wallet graph, protocol profiles, disable boundary, networking authorization, broadcast authority, and value-movement boundary are unchanged.
