# OpalFusion Architecture Guide

This guide is the compact maintainer map for the current OpalFusion package. The normative protocol behavior remains in [CashFusion Implementation Spec](cashfusion-implementation-spec.md).

## Layer Map

- Public facade: `OpalFusion.Client`, `OpalFusion.Round`, `OpalFusion.Transport`, `OpalFusion.Host`, `OpalFusion.Commitment`, `OpalFusion.BlindSignature`, and `OpalFusion.Blame` expose the supported integration surface.
- Client session: `OpalFusion.Client.Session` owns high-level lifecycle, reconnect policy, snapshot delivery, and the bridge from app-owned host callbacks into the runtime.
- Runtime: primary and covert runtime sessions coordinate live transport, clock ticks, host operations, stale-result suppression, and snapshot projection.
- Transport: live primary transport owns framed coordinator TCP/TLS I/O; live covert transport owns HTTP(S) covert requests and optional Tor SOCKS5 proxy usage for the covert path.
- Wire: native CashFusion protobuf reader/writer and message codecs encode/decode the official schema without generated protobuf code in the production target.
- Round engine: deterministic state machine that validates primary/covert message ordering, timing windows, deadline behavior, restart/blame flow, and terminal outcomes.
- Production workflow: OpalCrypto-backed materialization for commitments, blind-signature requests, covert components, transaction proposals, local signature extraction, proof material, and blame construction.
- Host boundary: reservation, transaction finalization, event observation, wallet policy, signing authority, persistence, broadcast, and product retry cadence stay outside OpalFusion.
- Diagnostics: OpalDiagnostics integration records stable typed events and privacy-safe fields without raw wallet, coordinator, OS, socket, script, or transaction payload leakage.

## Runtime Data Flow

1. `Client.Session.start()` creates a live runtime driver from app-owned configuration and host callbacks.
2. The primary transport connects, sends `ClientHello`, receives `ServerHello`, and sends `JoinPools`.
3. `FusionBegin` creates warmup state and starts covert preparation from the coordinator-provided covert endpoint.
4. `StartRound` creates the public round identifier and requests host participant reservation with round-scoped constraints.
5. The production workflow builds `PlayerCommit`, blind-signature material, component ordering, and proof material.
6. The round engine waits for the official covert component window and submits signed components through the covert runtime.
7. Shared components produce an unsigned transaction proposal for the host transaction assembler.
8. The host returns signed fusion transaction bytes; OpalFusion verifies and extracts local signatures for covert submission.
9. `FusionResult.ok = true` completes the round; `FusionResult.ok = false` enters blame-capable proof relay and restart handling.

## Ownership Rules

- Put CashFusion wire, timing, round-state, covert transport, and protocol-semantic validation in OpalFusion.
- Put reusable BCH cryptography in OpalCrypto, then consume it through stable OpalCrypto APIs.
- Put app-facing wallet orchestration, UTXO policy, secret authority, persistence, user approval, and broadcast in OpalBase or the app.
- Keep coordinator/server implementation out of this client package unless package scope is explicitly revised.
- Keep new public API additive and facade-owned; do not expose internal runtime or wire implementation types unless the integration contract requires them.

## Maintainer Checklist

- Preserve Electron Cash `4.4.3` `alpha13` interoperability unless the normative baseline is intentionally revised.
- Keep the public round phase model coarse even when internal substates become more detailed.
- Keep unsupported live input/signing forms deterministic and early, currently through `.notImplemented`.
- Treat covert timing as privacy-sensitive protocol behavior, not best-effort networking.
- Update [Validation Guide](validation.md), [CashFusion Official Protocol Matrix](cashfusion-official-protocol-matrix.md), and [CashFusion Native Swift Support Statement](cashfusion-native-support-statement.md) when tests, conformance evidence, or support claims change.
