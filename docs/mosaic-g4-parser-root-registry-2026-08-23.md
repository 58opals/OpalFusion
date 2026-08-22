# Mosaic G4 Parser-Root Registry — 2026-08-23

Status: `partial`. OpalFusion's low-level parser implementation-file surface and its reviewed 41-covered / 3-partial-variant / 8-closure-budget disposition are machine-checked, and the first-party mutation campaign covers 75 positive seeds across twelve focused test bodies. Composite byte entrypoints and cross-repository parser roots still require reconciliation before the G4 every-parser requirement can close.

## Registry Boundary

[`mosaic-g4-parser-implementation-files-2026-08-23.txt`](mosaic-g4-parser-implementation-files-2026-08-23.txt) records the 52 Mosaic production files that directly invoke `CanonicalDecoder.decode` or `JSONDecoder().decode`. [`../scripts/check-mosaic-g4-parser-root-registry.sh`](../scripts/check-mosaic-g4-parser-root-registry.sh) regenerates that sorted file set and fails on addition, removal, or rename. This prevents a new low-level parser implementation file from bypassing root review.

[`mosaic-g4-parser-root-map-2026-08-23.txt`](mosaic-g4-parser-root-map-2026-08-23.txt) assigns every registered implementation file one reviewed disposition, deterministic target, and root description. The checker requires exact one-to-one path parity and freezes the current counts at 41 `covered`, three `partial-variants`, and eight `closure-budget`. `covered` means the named passing deterministic body reaches the file's root; it does not imply every enum variant in a different file. `partial-variants` names a reached recovery root with open positive discriminants. `closure-budget` identifies the transport-bootstrap family that cannot fit the ordinary fixture lane.

The earlier source diagnostic found 93 declarations containing `func decode`. That declaration count is not the registry: it includes private helpers and non-byte accessors, while it misses parsers exposed through names such as `load`, `restore`, `open`, and `validate`. The 52-file gate is likewise a freshness boundary rather than an every-parser proof. Root accounting must follow externally reachable untrusted-byte entrypoints and map private helper decoders transitively to them.

## Current Root Accounting

| Root family | Current deterministic campaign | Root effect |
| --- | --- | --- |
| Signed and unsigned Nostr event codecs, padded envelope, and relay server frames | 8 seeds / 1 test body | Covers the direct JSON and padded-envelope roots plus all supported relay server-frame variants |
| Opal v0 canonical wire | 13 seeds / 1 test body | Covers authorization request, response, and token; commitment forms; component forms; acknowledgement; aggregate sets; and aggregate fragment roots |
| Mainnet-alpha post-manifest canonical wire | 15 seeds / 1 test body | Covers manifest core and manifest, envelopes, aggregate values, authorization response set and token, anonymous component, acknowledgement and BCH-signature forms, and complete transaction payload |
| Private-deployment canonical documents | 17 seeds / 1 test body | Covers discovery, formation, role, manifest, abort, completion, and payload document roots |
| Typed private-deployment Nostr mapping | 11 seeds / 2 test bodies | Covers every typed event decoder plus the context-validating manifest-proposal-candidate root; each path also traverses the generic envelope/context decoder and its nested canonical document decoder |
| Runtime recovery | 2 seeds / 2 test bodies | Covers fresh/forming/uninitialized and validated-manifest/initialized-journal positive states plus invalid phase, abort-cause, manifest, journal, publication, and terminal tags; positive abort, publication, and authorized-terminal variants remain open |
| Post-manifest NIP-59 composite opens | 2 seeds / 1 test body | Covers control and anonymous parent roots through gift-wrap and seal opening, rumor decoding, padded application-content extraction, canonical envelope parsing, identity binding, and timing validation |
| Private event and terminal recovery | 4 seeds / 1 test body | Covers event recovery, both terminal-record discriminants, and terminal evidence |
| Durable admission journal | 1 seed / 1 test body | Covers the recovery readback root with both control and anonymous records, including private context, record, and source helpers |
| Durable publication journal | 2 seeds / 1 test body | Covers drained control and anonymous recovery readbacks with prepared, publication-permitted, attempted, acknowledged, and completed records, including private context, record, and batch helpers |

The seed count is corpus accounting, not a coverage fraction. A seed may traverse several private helpers and discriminants, while two seeds may exercise different variants of one root.

## Open OpalFusion Root Queue

- Cover the three `partial-variants` recovery files with remaining positive runtime discriminants: pre-manifest abort causes, formation and terminal publication state, authorized terminal state, and post-manifest terminal state. The manifest-proposal-candidate root and validated-manifest plus initialized-journal recovery discriminants are covered.
- Cover the eight `closure-budget` transport-bootstrap implementation files through their public parent roots: authorization key; control claim and set; blind response set; anonymous request; registration and set; assignment; acknowledgement and set; consensus-envelope opens; and publication restoration. Three ordinary-lane shapes crossed 60 seconds because the runtime-generated RSA fixture dominates; do not repeat them. Use a digest-pinned first-party fixture or the single 600-second closure lane, recording fixture and parser time separately.
- Reconcile any remaining composite validation and relay-restoration byte entrypoints that call an already-registered low-level parser but impose additional canonical, authority, time, route, or binding checks.

## Cross-Repository Queue

OpalCrypto raw cryptographic inputs, OpalBase authenticated journals and facade recovery inputs, and Wallet outer records, anchors, and persisted application records remain application-owned registry work. Their existing positive and negative tests may supply seeds, but they require explicit root-to-target mapping and first-party mutation evidence before the cross-repository every-parser stage can close.

## Closure Rule

This registry becomes complete only when every externally reachable untrusted-byte root in the frozen first-party graph has one of two reviewed dispositions: directly exercised by a deterministic seed and the closure fuzz lane, or transitively exercised through a named parent root with an explicit mapping. `Fuzzing must cover every parser before any live profile is enabled` remains unchanged. A passing registry freshness check, a stable canonical round trip, or a large seed count cannot waive that requirement.
