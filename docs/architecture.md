# OpalFusion Architecture Guide

This guide maps the current package and its intended two-engine architecture. The normative hierarchy is [Opal Fusion Specification](opal-fusion-specification.md); protocol behavior is owned separately by [CashFusion Implementation Spec](cashfusion-implementation-spec.md) and [Mosaic Protocol Specification](mosaic-protocol-specification.md).

## Product Hierarchy

- Opal Wallet owns user intent, settings, progress presentation, and product lifecycle.
- OpalBase owns automatic scheduling, wallet policy, UTXO eligibility, reservation leases, output generation, transaction validation, signing authority, persistence, broadcast, and post-fusion coin policy.
- OpalFusion owns collaborative-transaction protocol execution and privacy-safe protocol state.
- OpalCrypto owns reusable Bitcoin Cash and protocol cryptographic primitives.
- SwiftFulcrum owns Fulcrum transport responsibilities unrelated to either fusion protocol.

OpalFusion contains two named engines: CashFusion for coordinator-based Electron Cash compatibility and Mosaic for a peer-conducted protocol with one ephemeral, non-contributing conductor per attempt. They share a facade and host boundary, not a wire protocol.

## Current Public Surface

- `OpalFusion.Client.Session` is the only runnable session. It executes the CashFusion pilot.
- `OpalFusion.CashFusion.Configuration` aggregates the values consumed by that live client and prepares an engine-specific configuration boundary.
- `OpalFusion.Mosaic.Configuration` selects one authoritative `.draft1` or `.opalV0` profile and derives its protocol, roster, and transport contracts. Internal aggregate and peer-local reducers enforce the bounded phase, roster, reservation, transcript, generation, and terminal rules. The reducer also enforces the complete role-commitment barrier and derives the roster itself from a profile-bound validated 32-byte role seed using explicit big-endian selection; no caller supplies roles or a conductor. Canonical Section 8 primitives, Opal v0 commitment/component/set and bounded message documents, bounded aggregate fragmentation and terminal reassembly, strict NIP-01 signed-event and relay-frame validation, a close-once one-relay session over an injected Tor-only WebSocket capability, an outer-authenticated NIP-44 encrypted-event boundary, BIP340 manifest-round and contributor pre-sign acknowledgement validation, deterministic Opal v0 unsigned-transaction construction with exact ordering and aggregate-fee validation, locally derived transcript-root gating, a contributor-local exact-attempt/material/transcript inclusion gate, replay guards, a three-relay/two-acceptance publication tracker, wallet-host contracts, an ordered post-admission runtime-session driver, and the deterministic Opal v0 issuance, bounded RFC 9474 execution, transcript, padding, tag, kind, and strict-sequence contracts are implemented. Opal v0 role-commitment and role-seed hash documents, a production commitment-opening/inclusion validator, discovery wire messages, complete manifests and BCH-signature messages, previous-output-backed wallet validation, fragment-to-authenticated-envelope integration, proof/blame payloads, a concrete Tor/WebSocket connection, production effect execution, independent cryptographic review, and a public live round runtime are not.
- `OpalFusion.Session.Mode` defines `.cashFusion`, `.mosaic`, and ordered `.automatic` selection.
- `OpalFusion.Session.AutomaticConfiguration` rejects an empty candidate set and duplicate engines and makes fallback policy explicit.
- `OpalFusion.Session` intentionally has no public initializer or runtime methods until engine selection and wallet reservation can be enforced as one safe operation.

The package currently uses one Swift target. This keeps the existing CashFusion implementation source-compatible while the common facade is stabilized.

The Mosaic attempt reducers consume authenticated canonical aggregate publications, validated signature and generation-bound host facts, and contributor-local validation tokens, then emit peer-local effects for reservation eligibility, transcript inclusion validation, contributor pre-sign acknowledgement, signing eligibility, reservation release or commit, and terminal outcomes. A narrow profile-owned role-seed validation seam binds the exact normalized control roster, commitments, and reveals before the reducer derives one conductor; no production validator exists until the missing profile domains and canonical pair document are frozen. After enforcing the elected contributor roster, exact aggregate cardinality, canonical component structure, aggregate BCH money range, and aggregate fee—but not commitment-opening linkage or previous-output ownership—the reducer deterministically constructs the unsigned version-2 transaction and derives the transcript root locally. Before emitting the contributor's acknowledgement request, the peer-local reducer requires a validation sealed to its exact attempt, generation, control identity, material identifier, commitment set, component set, transaction, and transcript root. The production validator that resolves local material and proves complete commitment/component inclusion remains deferred because its commitment-opening contract is not frozen. Signing eligibility carries that exact prepared transcript and is emitted only after every contributor acknowledges its root. The package also validates transcript-bound host requests, rejects executable `.draft1` transcript bindings, canonical primitive encodings, bounded aggregate fragmentation and terminal reassembly, NIP-01 event identifiers, signatures, client/relay frame shapes, per-connection subscription and publication correlation, NIP-44 encrypted content after outer-event authentication, generic draft replay behavior, Opal v0 strict per-sender runtime sequences, one-time authorization reuse and issuance accounting, bounded blind-authorization execution, relay acceptance quorum, and ordered runtime effect emission with source-loss cleanup. The relay session accepts only an injected Tor-only capability and has no default socket implementation, while the runtime driver accepts only already-validated merged inputs and delegates asynchronous host execution to a later failure-aware adapter. The package does not define the remaining role hash documents, manifest, BCH-signature, or proof/blame messages or the fragment-to-authenticated-envelope sequence integration, fetch or verify previous outputs, execute wallet effects, open a concrete Mosaic network route, provide an independently reviewed production cryptographic deployment, or make the public `OpalFusion.Session` runnable.

## Current CashFusion Layer Map

- Public facade: `OpalFusion.Client`, `Round`, `Transport`, `Host`, `Commitment`, `BlindSignature`, and `Blame` expose the pilot integration surface.
- Client session: `OpalFusion.Client.Session` owns lifecycle, reconnect policy, snapshot delivery, and the bridge from host callbacks into the runtime.
- Runtime: primary and covert runtime sessions coordinate live transport, clock ticks, host operations, stale-result suppression, and snapshot projection.
- Transport: live primary transport owns framed coordinator TCP/TLS I/O; live covert transport owns HTTP(S) requests and optional Tor SOCKS5 usage for the covert path.
- Wire: native CashFusion protobuf reader/writer and message codecs implement the pinned schema without generated protobuf code in the production target.
- Round engine: a deterministic state machine validates primary/covert ordering, timing windows, deadlines, restart/blame flow, and terminal outcomes.
- Production workflow: OpalCrypto-backed code materializes commitments, blind requests, covert components, transaction proposals, local signature extraction, proof material, and blame.
- Diagnostics: OpalDiagnostics records stable typed events and privacy-safe fields without raw wallet, coordinator, socket, script, or transaction payloads.

## Current CashFusion Data Flow

1. `Client.Session.start()` creates a live runtime driver from app-owned configuration and host callbacks.
2. The primary transport connects, sends `ClientHello`, receives `ServerHello`, and sends `JoinPools`.
3. `FusionBegin` creates warmup state and starts covert preparation from the coordinator-provided endpoint.
4. `StartRound` creates the public round identifier and requests a host participant reservation with round-scoped constraints.
5. The production workflow builds `PlayerCommit`, blind-signature material, component ordering, and proof material.
6. The round engine submits authorized components during the official covert window.
7. Shared components produce an unsigned transaction proposal for the host transaction assembler.
8. The host validates and signs its inputs; OpalFusion verifies and extracts local signatures for covert submission.
9. `FusionResult.ok = true` completes the round; `FusionResult.ok = false` enters blame-capable proof relay and restart handling.

## Intended Mosaic Data Flow

1. One-time discovery identities publish privacy-minimized availability beacons through the configured anonymous relay transport.
2. Candidates agree on a candidate set, bind fresh control keys, and use commit-reveal randomness to select one conductor.
3. The conductor and contributors sign one immutable round manifest. The conductor contributes no inputs or outputs.
4. Only after manifest agreement does each contributor ask OpalBase for one attempt-scoped reservation lease.
5. Contributors send grouped commitments, then submit blind-authorized components through unlinkable mailboxes.
6. Every contributor constructs the same canonically ordered unsigned transaction, verifies its complete local material is present through the profile-owned inclusion validator, verifies the exact aggregate fee, and acknowledges the locally derived transcript root.
7. Only after all contributor acknowledgements does OpalBase validate the exact transaction and sign its own inputs.
8. Peers assemble the complete transaction; any peer may hand it to its host for a separately reported broadcast decision.
9. Failure releases the reservation and ends the attempt. Retry creates fresh outputs, identities, keys, commitments, nonces, salts, mailboxes, and anonymous paths.

## Intended Module Boundaries

```text
OpalFusionCore
CashFusionEngine
MosaicEngine
OpalFusion
```

The eventual split must preserve one `import OpalFusion` integration surface. Only engine identity, mode selection, coarse lifecycle/result values, genuinely shared host contracts, diagnostics, and reusable OpalCrypto adapters belong in the core. CashFusion coordinator state and wire types stay out of Mosaic; Mosaic discovery, election, manifest, transcript, and mailbox types stay out of CashFusion.

## Ownership Rules

- Keep reusable cryptography in OpalCrypto and consume it through reviewed APIs.
- Keep wallet secrets, UTXO policy, reservation persistence, transaction broadcast, product retry, and user approval in OpalBase or the app.
- Keep the CashFusion coordinator/server implementation outside this client package.
- Permit the future Mosaic runtime to execute either contributor or conductor behavior without giving either role wallet authority.
- Select one engine before reserving wallet material and never switch engines during an active reservation.
- Keep engine-specific fields engine-specific; do not force CashFusion tiers, component counts, excess-fee bounds, or coordinator state into Mosaic.
- Do not expose internal runtime or wire types merely to avoid adapter work.

## Maintainer Checklist

- Preserve Electron Cash `4.4.3` `alpha13` interoperability unless its normative baseline is intentionally revised.
- Treat `Mosaic/1-draft.1` as non-interoperable design work until every release gate is complete.
- Treat `Mosaic/0-opal.1` as chipnet conformance work, not live or privacy-ready support.
- Preserve the conductor-does-not-contribute and all-contributors-acknowledge-before-signing invariants.
- Keep the public lifecycle coarse while retaining engine-tagged detail where needed.
- Treat covert timing and anonymous transport as privacy-sensitive protocol behavior.
- Update [Validation Guide](validation.md), the appropriate protocol specification, and the matching support/security statement when implementation evidence or claims change.
