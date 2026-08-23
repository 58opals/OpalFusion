# Mosaic G4 Parser-Root Registry — 2026-08-23

Status: `complete for the package-owned parser surface`. OpalFusion's low-level implementation-file surface is machine-checked at 52 covered / 0 partial-variant / 0 closure-budget, with 92 positive seeds across 24 focused parser test bodies. A second machine map accounts for all nine public transport composite byte entrypoints through existing mutation substrates and byte-identical passing integration evidence. The application-owned cross-repository map supplies the remaining Wallet, OpalBase, and OpalCrypto accounting.

## Registry Boundary

[`mosaic-g4-parser-implementation-files-2026-08-23.txt`](mosaic-g4-parser-implementation-files-2026-08-23.txt) records the 52 Mosaic production files that directly invoke `CanonicalDecoder.decode` or `JSONDecoder().decode`. [`../scripts/check-mosaic-g4-parser-root-registry.sh`](../scripts/check-mosaic-g4-parser-root-registry.sh) regenerates that sorted file set and fails on addition, removal, or rename. This prevents a new low-level parser implementation file from bypassing root review.

[`mosaic-g4-parser-root-map-2026-08-23.txt`](mosaic-g4-parser-root-map-2026-08-23.txt) assigns every registered implementation file one reviewed disposition, deterministic target, and root description. The checker requires exact one-to-one path parity and freezes the current counts at 52 `covered`, zero `partial-variants`, and zero `closure-budget`. `covered` means the named passing deterministic body reaches the file's root and its reviewed positive variants; it does not claim that the 52-file inventory includes every composite untrusted-byte entrypoint. The former transport-bootstrap closure budget and recovery partial variants were retired through digest-pinned first-party fixtures.

The earlier source diagnostic found 93 declarations containing `func decode`. That declaration count is not the registry: it includes private helpers and non-byte accessors, while it misses parsers exposed through names such as `load`, `restore`, `open`, and `validate`. The 52-file gate is likewise a freshness boundary rather than an every-parser proof. Root accounting must follow externally reachable untrusted-byte entrypoints and map private helper decoders transitively to them.

## Current Root Accounting

| Root family | Current deterministic campaign | Root effect |
| --- | --- | --- |
| Signed and unsigned Nostr event codecs, padded envelope, and relay server frames | 8 seeds / 1 test body | Covers the direct JSON and padded-envelope roots plus all supported relay server-frame variants |
| Opal v0 canonical wire | 13 seeds / 1 test body | Covers authorization request, response, and token; commitment forms; component forms; acknowledgement; aggregate sets; and aggregate fragment roots |
| Mainnet-alpha post-manifest canonical wire | 15 seeds / 1 test body | Covers manifest core and manifest, envelopes, aggregate values, authorization response set and token, anonymous component, acknowledgement and BCH-signature forms, and complete transaction payload |
| Private-deployment canonical documents | 17 seeds / 1 test body | Covers discovery, formation, role, manifest, abort, completion, and payload document roots |
| Typed private-deployment Nostr mapping | 11 seeds / 2 test bodies | Covers every typed event decoder plus the context-validating manifest-proposal-candidate root; each path also traverses the generic envelope/context decoder and its nested canonical document decoder |
| Runtime recovery | 9 seeds / 5 test bodies | Covers fresh/forming/uninitialized and validated-manifest/initialized-journal states; invalid phase, abort-cause, manifest, journal, publication, and terminal tags; both pre-manifest abort causes; formation and terminal publication; and pre- plus post-manifest authorized-terminal variants |
| Post-manifest NIP-59 composite opens | 2 seeds / 1 test body | Covers control and anonymous parent roots through gift-wrap and seal opening, rumor decoding, padded application-content extraction, canonical envelope parsing, identity binding, and timing validation |
| Private event and terminal recovery | 4 seeds / 1 test body | Covers event recovery, both terminal-record discriminants, and terminal evidence |
| Durable admission journal | 1 seed / 1 test body | Covers the recovery readback root with both control and anonymous records, including private context, record, and source helpers |
| Durable publication journal | 2 seeds / 1 test body | Covers drained control and anonymous recovery readbacks with prepared, publication-permitted, attempted, acknowledged, and completed records, including private context, record, and batch helpers |
| Transport bootstrap | 10 seeds / 9 test bodies | Covers authorization key, control claim and set, blind-response set, anonymous authorization input, registration and set, assignment, acknowledgement, and acknowledgement-set roots through a digest-pinned proof from the exact public production graph; expensive roots use an explicit balanced mutation cap while the helper default retains the full generated matrix |

The seed count is corpus accounting, not a coverage fraction. A seed may traverse several private helpers and discriminants, while two seeds may exercise different variants of one root.

## Composite Parent Reconciliation

[`mosaic-g4-parser-composite-root-map-2026-08-23.txt`](mosaic-g4-parser-composite-root-map-2026-08-23.txt) assigns every public transport-bootstrap byte parent to its generic signed-envelope mutation substrate, typed-document mutation target, and positive/negative integration target. The checker regenerates the exact eight `openTransportBootstrap*` entrypoints plus `restoreTransportBootstrapPublication`, requires one-to-one parity, and verifies that their three production files and `MosaicPrivateAlphaTransportBootstrapValidator` are byte-identical between passing G2 checkpoint `117949b08f354f5a58b78075dbf14b2ec4e4f88f` and frozen runtime `79ba5f91449b2c0d5cd6ec73c38fafd58cae0b46`.

This transitive mapping is deliberate. The composite parents reuse the already-mutated signed NIP-59 envelope, event, and typed bootstrap-document parsers, then add recipient, sender, timestamp, binding, operation-identifier, and exact-byte checks covered by the unchanged integration cases. Duplicating nine RSA-heavy wrapper corpora would add fixture cost without reaching a new decoder substrate.

## Cross-Repository Queue

Wallet and OpalBase have focused first-party mutation evidence for ten additional seeds across four affected test bodies, and OpalCrypto's relevant raw inputs are mapped transitively through existing deterministic matrices. Wallet's application-owned cross-repository root map records those exact parent decisions. Combined corpus accounting is 102 positive seeds across 28 focused bodies; this is not a coverage percentage.

## Closure Rule

The package registry is complete because every package-owned externally reachable untrusted-byte root in the frozen first-party graph is either directly exercised by a deterministic seed or transitively exercised through a named composite parent with an explicit mapping. Wallet's cross-repository registry applies the same rule to the application graph. `Fuzzing must cover every parser before any live profile is enabled` remains unchanged; a future parser or parent entrypoint must fail one of the freshness maps until reviewed. A passing registry check, stable canonical round trip, or large seed count is still not an exhaustive-input or coverage-guided fuzz proof.
