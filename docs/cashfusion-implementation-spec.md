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
2. Gather reserved participant inputs from the host boundary.
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
- `StateObserver` is the public async seam for session-wide state transitions, including pre-round connection failures and terminal outcomes.

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

### `OpalFusion.Host`

Responsibilities:

- Provide the participant inputs and outputs the host is willing to reserve for the round.
- Finalize the transaction implied by the server-shared components so OpalFusion can validate the result and derive the required signatures.
- Observe coarse round events.

Current scaffold alignment:

- `ParticipantInputProvider` supplies a round-scoped `ParticipantReservation`.
- `TransactionAssembler` finalizes a transaction from a round-scoped proposal.
- `EventObserver` receives round-scoped events.
- `ParticipantInput`, `ParticipantOutput`, `ParticipantReservation`, `TransactionFinalizationProposal`, `FinalizedTransaction`, and `Event` provide the current host-facing value surface.

OpalFusion-specific choice:

- The host boundary remains the place where wallet-owned signing material is applied; OpalFusion must not absorb product-wallet policy or UI concerns.

### `OpalFusion.Commitment`

Responsibilities:

- Own future public types for initial commitments, amount commitments, salted hashes, and related validation surfaces.

### `OpalFusion.BlindSignature`

Responsibilities:

- Own future public types for blind signature request/response handling tied to the pinned protocol behavior.

### `OpalFusion.Blame`

Responsibilities:

- Own future public types for proof relay, blame submission, and blame outcome modeling.

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
- Keep the public state model coarse and stable even if internal state is more detailed.
- Surface host rejection distinctly from coordinator rejection.
- Keep reusable Bitcoin Cash cryptography outside this package when it belongs in `OpalCrypto`.
- Avoid dependency cycles into downstream app-facing packages.

### Error Categories to Preserve

The implementation phase should preserve at least these top-level outcome categories:

- invalid configuration
- transport unavailable
- host rejected
- protocol rejected or incompatible
- round failed and entered blame handling
- round completed successfully
- not yet implemented or unsupported path

### Terminal Outcomes

- Successful fusion result.
- Clean coordinator rejection or fatal error.
- Host refusal to continue.
- Protocol incompatibility.
- Transport failure that prevents round completion.
- Blame-capable round failure.

## 7. Phased Implementation Roadmap

### Phase 1: Canonical Specification

- Add this document.
- Reduce `README.md` to package overview plus links.
- Treat this spec as the source of truth for later implementation work.

### Phase 2: Public API Alignment

- Reconcile public scaffolding with the responsibilities in this spec.
- Expand coarse error and event surfaces where needed.
- Preserve public-safe documentation boundaries.

### Phase 3: Protocol and State Modeling

- Add typed message models and round-state machinery required for the pinned baseline.
- Keep wire compatibility anchored to Electron Cash `4.4.3`.

### Phase 4: Runtime Interoperability

- Implement primary-channel and covert-channel client behavior.
- Integrate host boundaries for reserved inputs and transaction finalization.
- Prove one successful Electron Cash-compatible round.

### Phase 5: Hardening

- Add broader failure-path coverage.
- Strengthen blame handling and restart behavior.
- Add interop-focused regression tests.

## 8. Acceptance Checklist for Future Implementation Work

This documentation phase is complete only if future implementers can answer these questions from this repository alone:

- What exact upstream behavior is normative for the first interoperability slice?
- Which parts of the round lifecycle are mandatory to interoperate?
- Which timing rules are privacy-sensitive rather than advisory?
- How do the current public namespaces map to concrete responsibilities?
- Which failures are transport failures, host failures, protocol failures, and blame outcomes?
- Which items are intentionally out of scope for the first slice?

Future implementation work should be considered aligned only if:

- it preserves Electron Cash `4.4.3` interoperability for the targeted flow
- it cites the relevant section of this spec when adding or changing behavior
- it does not introduce private execution/process material into this repository
