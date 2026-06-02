# CashFusion Native Swift Support Statement

This statement defines the current OpalFusion CashFusion support claim and the evidence still required before claiming complete official CashFusion support.

## Current Support Claim

OpalFusion currently provides a native Swift client implementation for the Electron Cash `4.4.3` CashFusion `alpha13` protocol baseline. The supported scope is the client-side package surface: native protobuf wire handling, primary/covert protocol envelopes, client runtime lifecycle, production workflow materialization, blame/restart handling, and the live transport profile documented in the implementation spec.

This is not yet a final 100% official CashFusion support claim. That final claim remains blocked until reviewed pinned Electron Cash transcript replay is committed and repeated env-gated live coordinator smoke passes on the supported pilot profile.

## Dependency Contract

The `OpalFusion` package target depends only on `OpalCrypto` and `OpalDiagnostics`. The former external Swift protobuf runtime, generated protobuf source files, protoc output, and protobuf code generation are not part of the production target or the test target.

Current protobuf support is implemented through native Swift reader/writer primitives and native CashFusion schema codecs. The conformance matrix tracks the official message, field, timing, and transport coverage in [`cashfusion-official-protocol-matrix.md`](cashfusion-official-protocol-matrix.md).

## Supported Native Swift Surfaces

- Protobuf wire and schema support for the official CashFusion message set, including required fields, optional fields, repeated fields, map entries, oneofs, packed numeric fields, fixed-width scalars, length-delimited values, UTF-8 validation, and unknown-field skipping.
- Primary and covert envelope encoding/decoding through native `CashFusion*Codec` implementations, with active runtime bridges no longer backed by generated protobuf types.
- Runtime lifecycle support for primary handshake, pool joining, fusion warmup, round start, commitment submission, covert component/signature submission, result handling, restart continuation, and close-start covert cleanup.
- Production workflow support for component ordering, input/output/blank component semantics, salt commitments, initial commitments, proof material, signature extraction, transaction assembly boundaries, and blame proof generation/validation.
- Local conformance evidence from pinned protobuf byte fixtures, official manual fixtures, runtime semantic tests, production workflow tests, and env-gated live-smoke infrastructure.

## Remaining Proof Gates

- Reviewed pinned Electron Cash transcript replay: a sanitized capture from `scripts/run-electron-cash-transcript-capture.sh` must be committed as test-only fixture data and replayed through native codecs/runtime tests.
- Repeated live coordinator smoke: `scripts/run-electron-cash-interop-smoke.sh 3` must pass on the supported pilot profile with a real Electron Cash `4.4.3`-compatible coordinator before the package should claim complete live compatibility.
- `STANDARD_TIMEOUT` gathered-response owner: the current matrix keeps this row `Partial` until pinned transcript replay or live evidence identifies the exact non-critical/gathered-response runtime state that should own the remaining official `3s` timeout.

## Intentional Exclusions

- Coordinator/server implementation remains outside this client package.
- Broad Bitcoin Cash script support beyond the current compressed-key standard P2PKH pilot profile remains deferred.
- Production coordinator defaults, multi-coordinator selection, app retry policy, wallet UI, and product-facing user policy remain app-owned.

## Related Documents

- Canonical implementation spec: [`cashfusion-implementation-spec.md`](cashfusion-implementation-spec.md)
- Official conformance matrix: [`cashfusion-official-protocol-matrix.md`](cashfusion-official-protocol-matrix.md)
- Env-gated live pilot confidence: [`cashfusion-live-pilot-confidence.md`](cashfusion-live-pilot-confidence.md)
- Transcript capture and review flow: [`cashfusion-transcript-capture.md`](cashfusion-transcript-capture.md)
