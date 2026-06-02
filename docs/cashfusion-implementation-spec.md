# CashFusion Implementation Spec

This document is the canonical public-safe technical specification for OpalFusion.
It defines what the package must implement for the first interoperable CashFusion slice, while keeping private execution planning outside this repository.

## 1. Package Purpose, Boundaries, and Non-Goals

OpalFusion is the CashFusion protocol and runtime package for the Opal Bitcoin Cash stack.
It exists to isolate coordinator connectivity, covert transport, round-state handling, commitments, blind-signature flow, and blame handling inside one focused Swift package.

### Purpose

- Provide a dedicated CashFusion client/runtime layer for Bitcoin Cash.
- Expose host integration seams that allow downstream packages to supply reserved transaction outputs, construct transaction signatures, and observe round progress.
- Keep CashFusion-specific behavior out of app-facing packages and product layers.

### Boundaries

- `OpalFusion` owns CashFusion protocol/runtime behavior and interoperability.
- `OpalCrypto` owns reusable Bitcoin Cash cryptographic primitives.
- `OpalBase` owns app-facing orchestration, wallet policy, and product-facing integration.
- `SwiftFulcrum` owns Fulcrum transport responsibilities.
- The current package support contract is `macOS 26` only; the live covert transport and Tor SOCKS5 runtime path are macOS-only in this first slice.
- Coordinator host, coordinator port, primary-channel TLS policy, Tor SOCKS5 settings, join tiers, pool tags, and product retry policy are app-owned inputs. OpalFusion validates and consumes them, but does not provide production coordinator defaults.

### Non-goals

- Wallet UI, product-shell behavior, and end-user policy.
- Coordinator/server implementation.
- Multi-coordinator compatibility beyond the Electron Cash reference behavior defined here.
- Generic Bitcoin Cash networking unrelated to CashFusion coordinator or covert transport behavior.

## 2. Normative Upstream References and Pinned Baseline

### Normative Baseline

The first interoperability slice targets Electron Cash CashFusion compatibility, pinned to Electron Cash `4.4.3` published on March 5, 2026.

Normative upstream references:

- Electron Cash `4.4.3` release:
  [github.com/Electron-Cash/Electron-Cash/releases/tag/4.4.3](https://github.com/Electron-Cash/Electron-Cash/releases/tag/4.4.3)
- CashFusion protobuf schema:
  [fusion.proto](https://raw.githubusercontent.com/Electron-Cash/Electron-Cash/4.4.3/electroncash_plugins/fusion/protobuf/fusion.proto)
- Primary framing layer:
  [connection.py](https://raw.githubusercontent.com/Electron-Cash/Electron-Cash/4.4.3/electroncash_plugins/fusion/connection.py)
- Protocol constants and timing windows:
  [protocol.py](https://raw.githubusercontent.com/Electron-Cash/Electron-Cash/4.4.3/electroncash_plugins/fusion/protocol.py)
- Reference server defaults:
  [server.py](https://raw.githubusercontent.com/Electron-Cash/Electron-Cash/4.4.3/electroncash_plugins/fusion/server.py)

Detailed conformance tracking lives in [`cashfusion-official-protocol-matrix.md`](cashfusion-official-protocol-matrix.md). The public native Swift support boundary and remaining proof gates are summarized in [`cashfusion-native-support-statement.md`](cashfusion-native-support-statement.md).

### Baseline Rules

- Electron Cash `4.4.3` behavior wins when this document and upstream `master` differ.
- Production hostnames are not part of the interoperability contract.
- OpalFusion must follow upstream-required wire behavior and timing expectations exactly enough to interoperate with the pinned baseline.
- OpalFusion-specific architecture and API choices may differ internally so long as observable interoperability stays compatible.

### Upstream-Required Protocol Facts

- Protocol version baseline: `alpha13`.
- Primary message framing is:
  - 8-byte magic prefix `765be8b4e4396dcf`
  - 4-byte big-endian message length
  - serialized protobuf payload
- Framed primary messages must reject oversized payloads above 200 KiB.
- Primary handshake and round messages use the protobuf message families defined in `fusion.proto`.

## 3. First-Slice Interoperability Target and Scope

### Target

OpalFusion must implement the client side of one Electron Cash-compatible CashFusion round flow against the pinned baseline.

### In Scope

- Connect to a coordinator over the primary channel.
- Negotiate server parameters and join eligible tier pools.
- Receive `FusionBegin` and establish covert connections using the server-provided covert host, port, and SSL flag.
- Participate in one round through commitments, blind-signature response handling, covert component submission, signature submission, and result handling.
- Handle restart and blame-phase entry without violating protocol semantics.
- Surface enough state and events for a host package to integrate the feature safely.

### Out of Scope for the First Slice

- Running or embedding a coordinator.
- Supporting multiple coordinator implementations.
- Product policy such as when to fuse, how often to fuse, or which tiers a user should prefer.
- Wallet UI and transaction-history presentation.

## 4. End-to-End CashFusion Round Lifecycle

This section defines the required external behavior. Internal implementation structure may differ, but message ordering, validation, and timing must preserve interoperability.

### 4.1 Primary Connection and Handshake

1. Open a primary connection to the configured coordinator host and port.
2. Send `ClientHello` with the pinned protocol version and, when available, the expected Bitcoin Cash genesis hash.
3. Receive `ServerHello`.
4. Record the server-advertised:
   - tiers
   - `num_components`
   - `component_feerate`
   - `min_excess_fee`
   - `max_excess_fee`
   - optional donation CashAddr
5. Send `JoinPools` for the tiers the host wishes to join, including any pool tags used to avoid self-fusions.
6. Process `TierStatusUpdate` messages until the server begins a fusion.

### 4.2 Fusion Start and Warmup

1. Receive `FusionBegin` with:
   - tier
   - covert domain
   - covert port
   - optional covert SSL requirement
   - server time
2. Validate server clock skew against the upstream maximum discrepancy of 5 seconds.
3. Begin covert-channel preparation during the warmup window.
4. Expect `StartRound` roughly 30 seconds after `FusionBegin`, subject to the upstream slop allowance.

### 4.3 StartRound and Player Commit

1. Receive `StartRound` with:
   - round public key
   - blind nonce points
   - server time
2. Gather reserved participant inputs from the host boundary using the round identifier, selected tier, component count, component fee rate, and excess-fee bounds.
3. Build the player's initial commitments and blind signature requests.
4. Send `PlayerCommit` before the upstream commitment deadline.

Upstream-required timing:

- Server expects commitments by approximately `+3s` from `StartRound`.

### 4.4 Blind Signatures and Full Commitment Set

1. Receive `BlindSigResponses`.
2. Receive `AllCommitments`.
3. Verify that the returned commitments are structurally consistent with the round and sufficient to continue.
4. Use the warm covert submission schedule defined by the upstream protocol rather than ad hoc timing.

Upstream-required timing:

- Covert component submission nominally starts at `+5s`.
- Server rejects covert components after `+15s`.

### 4.5 Covert Component Submission

1. Establish one or more covert connections using the server-provided covert endpoint.
2. Respect the upstream covert strategy:
   - up to 6 spare covert connections
   - 15-second covert connect timeout/window
   - 3-second submit timeout
   - 5-second covert submit window
3. Submit `CovertComponent` messages signed for the round.
4. Treat covert submission timing as privacy-sensitive behavior, not merely best-effort networking.

### 4.6 Shared Components and Local Finalization

1. Receive `ShareCovertComponents`.
2. Validate the shared components and session hash if provided.
3. If `skip_signatures` is set, do not continue into signature submission as though the round were healthy.
4. Build the unsigned transaction proposal implied by the shared components.
5. Pass that proposal to the host transaction-finalization boundary.
6. Confirm that the finalized transaction is consistent with the round template before extracting or deriving the input signatures needed for server submission.

Upstream-required timing:

- Signature submission nominally starts at `+20s`.
- Server rejects covert signatures after `+30s`.

### 4.7 Signature Submission and Result

1. Submit `CovertTransactionSignature` messages for the relevant inputs.
2. Await `FusionResult`.
3. Treat `FusionResult.ok = true` as the successful terminal round outcome.
4. Treat `FusionResult.ok = false` as a transition into blame-capable failure handling, not as a generic transport error.
5. Expect the round conclusion by approximately `+35s` from `StartRound`.

### 4.8 Proof Relay, Blame, and Restart

1. If the round fails, send `MyProofsList` with the committed random number and any encrypted proofs required by the protocol.
2. Receive `TheirProofsList`.
3. Validate relayed proofs and construct any warranted `Blames`.
4. Distinguish protocol blame from host rejection or transport failure.
5. Handle `RestartRound` as a protocol continuation signal that may reuse the connection while starting a fresh round state.

## 5. OpalFusion Subsystem Mapping

This section maps the current public scaffold to the required behavior.

### `OpalFusion.Client`

Responsibilities:

- Own coordinator configuration, high-level client state, and the conservative public session activation wrapper.
- Track whether the primary connection is established.
- Surface the current round snapshot when a round exists.
- Report high-level error categories that distinguish configuration, transport, host, protocol, and blame outcomes.
- Provide session-scoped snapshot observation without exposing internal runtime or transport controls.

Current scaffold alignment:

- `Configuration` already models coordinator host, coordinator port, covert channel configuration, and optional Tor SOCKS5 configuration.
- `State` already models connection state plus an optional round snapshot.
- `Error` remains intentionally coarse and still maps configuration, transport, host, protocol, and round-completion outcomes into a stable public surface.
- `Session` is the conservative public activation wrapper over the internal live runtime.
- `Session.Snapshot` exposes the current coarse `State` plus the last surfaced `Error`.
- `Session.Snapshot.lastErrorSummary` is a sanitized diagnostic string for app logging and support flows. It must not expose raw operating-system, transport, or coordinator error text to user-facing surfaces.
- `StateObserver` is the public async seam for session-wide state transitions, including pre-round connection failures and terminal outcomes.
- The current real Electron Cash proof target is session-level eventual success rather than first-round success, so a blame/restart attempt may be followed by a later successful round inside one session.

### `OpalFusion.Round`

Responsibilities:

- Represent round identity and externally visible progress.
- Stay aligned to protocol milestones rather than internal implementation details.

Current scaffold alignment:

- `Identifier` is the public round token.
- `Phase` is currently a coarse observable state machine:
  - `idle`
  - `connecting`
  - `registeringInputs`
  - `awaitingCommitments`
  - `awaitingBlindSignatures`
  - `assemblingTransaction`
  - `blame`
  - `completed`
- `State` captures the identifier, current phase, optional participant count, and terminality.

OpalFusion-specific choice:

- Internal substates may be more detailed than the public `Phase` enum so long as the public surface remains coherent with the round lifecycle above.

### `OpalFusion.Transport`

Responsibilities:

- Own primary-channel framing and configuration.
- Own covert-channel configuration and optional Tor SOCKS5 proxy usage.
- Enforce timing-sensitive connection and submission behavior required for interoperability.

Current scaffold alignment:

- `CovertChannelConfiguration` models entry path, payload sizing, and request timeout.
- `TorSocks5Configuration` models proxy host, port, and remote hostname resolution behavior.
- Tor SOCKS5 applies to the covert HTTP(S) transport path only. The primary coordinator connection stays direct unless a future product requirement explicitly asks for coordinator-over-Tor.

### `OpalFusion.Host`

Responsibilities:

- Provide the participant inputs and outputs the host is willing to reserve for the round.
- Finalize the transaction implied by the server-shared components so OpalFusion can validate the result and derive the required signatures.
- Observe coarse round events.

Current scaffold alignment:

- `ParticipantReservationSource` supplies a `ParticipantReservation` from a round-scoped `ParticipantReservationContext`.
- `TransactionAssembler` finalizes a transaction from a round-scoped proposal.
- `EventObserver` receives round-scoped events.
- `ParticipantInput`, `ParticipantOutput`, `ParticipantReservation`, `ParticipantReservationContext`, `TransactionFinalizationProposal`, `FinalizedTransaction`, and `Event` provide the current host-facing value surface.

OpalFusion-specific choice:

- The host boundary remains the place where wallet-owned signing material is applied; OpalFusion must not absorb product-wallet policy or UI concerns.
- The currently supported live input/signing path is intentionally narrow: each reserved local input must be a compressed-key standard P2PKH input, and the finalized transaction must preserve a standard Schnorr P2PKH unlocking script for each local input.

### `OpalFusion.Commitment`

Current scaffold alignment:

- `Commitment` already exposes public value models for component payloads, input/output/blank components, full components, and initial commitments.
- Commitment generation, coordinator submission ordering, and execution-specific bookkeeping remain internal runtime concerns.

### `OpalFusion.BlindSignature`

Current scaffold alignment:

- `BlindSignature` already exposes public request and response value models tied to the pinned protocol behavior.
- Blind-signature material generation, unblinding, and round sequencing remain internal runtime concerns.

### `OpalFusion.Blame`

Current scaffold alignment:

- `Blame` already exposes public proof, encrypted-proof, relayed-proof, decrypter, and blame-proof value models.
- Blame sequencing, proof validation, and restart handling remain internal runtime concerns.

## 6. Required Behavior and Failure Handling

### Upstream-Required Behavior

- Reject protocol framing with bad magic, invalid length, or oversized messages.
- Enforce the pinned protocol version until this document is intentionally revised.
- Treat clock skew beyond the upstream tolerance as a protocol failure, not a recoverable cosmetic warning.
- Respect covert submission timing as privacy-critical.
- Preserve round ordering and transaction-template consistency when deriving signatures.
- Treat `skip_signatures`, `FusionResult.ok = false`, and blame messages as protocol-semantic outcomes.

### OpalFusion-Specific Required Behavior

- Validate configuration before opening the primary connection.
- Validate the optional genesis hash and requested join-pool tiers/tags before opening the primary connection.
- Keep the public state model coarse and stable even if internal state is more detailed.
- Surface host rejection distinctly from coordinator rejection.
- Surface coordinator rejection without exposing raw coordinator failure text.
- Treat explicit `stop()` as an idempotent, non-error terminal session action. Unexpected primary EOF or transport failure remains a transport failure.
- Keep public diagnostics and OSLog public fields privacy-safe; raw OS, TLS, socket, and coordinator errors must not become public summaries.
- Keep reusable Bitcoin Cash cryptography outside this package when it belongs in `OpalCrypto`.
- Avoid dependency cycles into downstream app-facing packages.
- Fail unsupported local input/signing forms deterministically and early, rather than letting them surface late in the round after deeper execution work has already proceeded.
- Keep the current real-interoperable pilot path intentionally narrow and prove it at the session level: intermediate blame/restart rounds are acceptable, but a coordinator-backed proof run should only pass when one round in the session completes successfully.

### Error Categories to Preserve

The implementation phase should preserve at least these top-level outcome categories:

- invalid configuration
- transport unavailable
- host rejected
- protocol rejected or incompatible
- round failed and entered blame handling
- unresolved blame terminal outcome
- round completed successfully
- not yet implemented or unsupported path

### Terminal Outcomes

- Successful fusion result.
- Clean coordinator rejection or fatal error.
- Host refusal to continue.
- Protocol incompatibility.
- Transport failure that prevents round completion.
- Blame-capable round failure.
- Explicit app-requested stop, which is non-error and clears nonterminal round state.

### App-Facing Runtime Contract

Wallet and OpalBase should consume OpalFusion through `OpalFusion.Client.Session` with app-owned configuration:

- Supported platform: macOS 26 for the live runtime in this first slice.
- Required configuration: non-empty coordinator host, nonzero coordinator port, explicit primary TLS flag, valid covert entry path, positive covert payload and timeout settings, optional valid Tor SOCKS5 host/port, optional 32-byte BCH genesis hash, and non-empty positive unique join-pool tiers.
- Optional pool tags must have a non-empty identifier and positive limit.
- Primary TLS follows `coordinatorRequiresTLS`; covert HTTP(S) follows `FusionBegin.covert_ssl`; Tor SOCKS5 is used only by covert HTTP(S) requests.
- Primary transport may retry transient Network.framework waiting states before startup failure, but TLS failures are terminal. Product-level coordinator retry cadence remains app-owned.
- Terminal round statuses are `success`, `coordinatorRejected`, `hostRejected`, `protocolIncompatible`, `transportFailed`, and `blameRequired`.
- Public user-safe error categories are `invalidConfiguration`, `transportUnavailable`, `coordinatorRejected`, `hostRejected`, `protocolIncompatible`, `blameRequired`, and `notImplemented`.
- `lastErrorSummary` and host event summaries are sanitized integration diagnostics, not raw coordinator or OS error text.

## 7. Current Pilot Status

- The canonical specification, public session surface, typed protocol/domain models, live runtime/transport stack, and `OpalCrypto`-backed execution materialization are now present on `develop`.
- `develop` is the public pilot lane for Opal Fusion. `main` remains intentionally behind it until the current public pilot path is proven repeatedly against a real Electron Cash `4.4.3` coordinator.
- The current live support envelope remains intentionally narrow: compressed-key standard P2PKH reserved inputs and matching standard Schnorr P2PKH unlocking scripts for local finalized inputs.
- The current coordinator-backed proof target is session-level eventual success rather than first-round success. Intermediate blame or restart rounds are acceptable as long as one round in the session completes successfully before the overall smoke timeout.
- The current pilot-confidence exit target is three consecutive successful runs of `./scripts/run-electron-cash-interop-smoke.sh 3` on the supported path; `docs/cashfusion-live-pilot-confidence.md` documents the opt-in runner and redacted summary path. Broader BCH script support stays deferred until after that gate.
- Reviewed pinned transcript replay is prepared through `docs/cashfusion-transcript-capture.md` and `./scripts/run-electron-cash-transcript-capture.sh`, which keep captured byte candidates outside the repository until manual review.
- The current public native Swift support statement is [`cashfusion-native-support-statement.md`](cashfusion-native-support-statement.md); it must not claim final 100% official CashFusion support until pinned replay and repeated live smoke pass.

## 8. Acceptance Checklist for Future Changes

Future maintainers and contributors should still be able to answer these questions from this repository alone:

- What exact upstream behavior is normative for the first interoperability slice?
- Which parts of the round lifecycle are mandatory to interoperate?
- Which timing rules are privacy-sensitive rather than advisory?
- How do the current public namespaces map to concrete responsibilities?
- Which failures are transport failures, host failures, protocol failures, and blame outcomes?
- Which items are intentionally out of scope for the first slice?
- Does the native Swift support statement still match the conformance matrix, dependency graph, pinned transcript status, and live smoke evidence?

Future implementation work should be considered aligned only if:

- it preserves Electron Cash `4.4.3` interoperability for the targeted flow
- it cites the relevant section of this spec when adding or changing behavior
- it does not introduce private execution/process material into this repository
