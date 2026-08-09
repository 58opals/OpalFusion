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
- `OpalFusion.Mosaic.Configuration` selects one authoritative `.draft1`, `.opalV0`, or `.opalMainnetAlpha` profile and derives its protocol, roster, and transport contracts. Internal aggregate and peer-local reducers enforce the bounded phase, roster, reservation, transcript, generation, and terminal rules and derive the conductor from a validated role seed. An internal ordered coordinator executes validated local host effects, drains late reservations to release before signing, converts ambiguous post-sign failures to recovery-required outcomes, and commits only through `MosaicCompleteTransactionHost`; its material builders and complete-transaction provider remain injected seams. Opal v0 supplies the chipnet conformance and internal runtime-driver path. Mainnet-alpha additively freezes the mainnet profile identity, role documents, complete manifest, PlayerCommit, kind-bounded strict aggregate reassembly, authenticated control admission, inner pre-sign signatures, BCH signature sets, exact 100-byte P2PKH unlocking scripts, and complete-transaction payloads. Its driver and legacy host-marker paths remain fail closed. Discovery, commitment-opening/component linkage, lease-to-material construction, previous-output resolution, anonymous BCH-signature authorization, mailbox-to-runtime integration, a concrete Tor connection, production coordinator composition, durable recovery, independent review, and a public live Mosaic runtime are not implemented.
- `OpalFusion.Session.Mode` defines `.cashFusion`, `.mosaic`, and ordered `.automatic` selection.
- `OpalFusion.Session.AutomaticConfiguration` rejects an empty candidate set and duplicate engines and makes fallback policy explicit.
- `OpalFusion.Session` intentionally has no public initializer or runtime methods until engine selection and wallet reservation can be enforced as one safe operation.

The package currently uses one Swift target. This keeps the existing CashFusion implementation source-compatible while the common facade is stabilized.

The Mosaic reducers consume validated aggregate publications, signatures, generation-bound host facts, and contributor-local validation tokens, then emit reservation, inclusion, acknowledgement, signing, disposition, and terminal effects. `RuntimeCoordinator` serially executes those local effects without cancelling in-flight wallet calls: source loss during reservation releases the late lease, cancellation after signing may have begun never releases it, and reducer completion becomes externally complete only after exact complete-transaction commit. Mainnet-alpha control admission seals implemented aggregate reservations and pre-sign documents to the authenticated sender, round, phase, roster, and publisher role, while typed reassembly rejects digest-valid malformed bytes. The package can independently assemble and verify an exact complete P2PKH Schnorr transaction when supplied the acknowledged transcript and ordered previous outputs. It still cannot prove commitment openings, construct production lease material, resolve every previous output, authorize anonymous BCH-signature mailbox submissions, persist or execute crash recovery, or select a live transport. Those missing authorities keep mainnet-alpha outside `RuntimeSessionDriver` and keep `OpalFusion.Session` non-runnable.

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
