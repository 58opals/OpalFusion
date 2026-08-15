# OpalFusion Architecture Guide

This guide maps the current package and its intended two-engine architecture. The normative hierarchy is [Opal Fusion Specification](opal-fusion-specification.md); protocol behavior is owned separately by [CashFusion Implementation Spec](cashfusion-implementation-spec.md) and [Mosaic Protocol Specification](mosaic-protocol-specification.md). The frozen non-live mainnet contract and separately versioned deployment decisions are owned by the [Mosaic Mainnet-Alpha Profile](mosaic-mainnet-alpha-profile.md) and [Mosaic Mainnet-Alpha Private-Deployment Profile](mosaic-mainnet-alpha-private-deployment.md). The bounded private-alpha implementation status and remaining gates are recorded in [Mosaic Mainnet-Alpha Progress](mosaic-mainnet-alpha-progress.md).

## Product Hierarchy

- Opal Wallet owns user intent, settings, progress presentation, and product lifecycle.
- OpalBase owns automatic scheduling, wallet policy, UTXO eligibility, reservation leases, output generation, transaction validation, signing authority, persistence, broadcast, and post-fusion coin policy.
- OpalFusion owns collaborative-transaction protocol execution and privacy-safe protocol state.
- OpalCrypto owns reusable Bitcoin Cash and protocol cryptographic primitives.
- SwiftFulcrum owns Fulcrum transport responsibilities unrelated to either fusion protocol.

OpalFusion contains two named engines: CashFusion for coordinator-based Electron Cash compatibility and Mosaic for a peer-conducted protocol with one ephemeral, non-contributing conductor per attempt. They share a facade and host boundary, not a wire protocol.

## Mosaic Ownership Map

| Concern | Authoritative owner | Boundary |
| --- | --- | --- |
| Phase semantics | Attempt/session reducers and the selected contributor or conductor coordinator | Transport forwards authenticated inputs and effects; it does not advance protocol phases independently. |
| Admission and replay | `AdmissionLedger` for semantic admission; one attempt-bound post-manifest journal for accepted digest, sequence, wrapper, mailbox, and original acceptance-time replay facts | The journal appends before coordinator effects and merges relay copies. Private-alpha restoration canonical-decodes, re-authenticates, and replays the exact ordered snapshot into the existing coordinator before live ingress; partial, reordered, mismatched, or unauthenticated recovery fails closed. |
| Wallet lifecycle | OpalBase's host lifecycle and write-ahead attempt journal | OpalFusion's reservation coordinator owns one in-memory pending disposition and returns exact release, commit, or recovery requirements; it does not persist or execute wallet recovery. |
| Outbound publication | One peer-local attempt transport owner allocates mailbox-bound route groups and rejects connection or isolation-lease reuse across that owner's purposes; control/anonymous bridges seal exact context; batch and relay publishers own publication | The injected provisioner owns cross-peer allocation plus endpoint-to-connection and Tor-isolation attestation. The publication journal owns byte-identical continuation over an app-owned backend, but publication owns neither semantic loopback, autonomous retry scheduling, nor in-place regeneration. |
| Inbound fan-in | The attempt transport owner issues one role-complete inbound-runtime provisioning capability; fan-in consumes its single claim and passes one unforgeable immutable token through ingress to the specialized driver | Private-alpha construction restores the exact role coordinator, admission/publication state, mailbox projection, and terminal record before routes; the injected application still owns durable storage, authoritative Tor provisioning, cross-process exclusion, and outer lifecycle supervision. |

## Current Public Surface

- `OpalFusion.Client.Session` is the only runnable session. It executes the CashFusion pilot.
- `OpalFusion.CashFusion.Configuration` aggregates the values consumed by that live client and prepares an engine-specific configuration boundary.
- `OpalFusion.Mosaic.Configuration` selects one authoritative `.draft1`, `.opalV0`, or `.opalMainnetAlpha` profile. Opal v0 retains the chipnet conformance and generic internal runtime-driver path. Mainnet-alpha remains rejected by that generic driver, while the separate macOS-only `MosaicPrivateAlphaRuntime` SPI owns signed pre-manifest formation, canonical recovery snapshots, contributor/conductor construction over the existing coordinator path, exact admission and publication replay, deterministic terminal reconstruction, and linear protocol terminal evidence. It accepts only injected durable-store, signing, mailbox, timing, Tor-route, and wallet-host capabilities; it does not expose a public Mosaic session, generate application keys, prove concrete Tor isolation, authorize broadcast, or erase Base wallet state.
- `OpalFusion.Session.Mode` defines `.cashFusion`, `.mosaic`, and ordered `.automatic` selection.
- `OpalFusion.Session.AutomaticConfiguration` rejects an empty candidate set and duplicate engines and makes fallback policy explicit.
- `OpalFusion.Session` intentionally has no public initializer or runtime methods until engine selection and wallet reservation can be enforced as one safe operation.

The internal post-manifest control-batch publisher binds a bridge-minted batch to its exact bootstrap context, complete roster recipient allocation, and manifest relay selection; preflights every recipient route group using only recipient event identities; rejects connection reuse across groups; and drains every delegated exact-three-route/two-accepted-ACK publisher. Endpoint provisioning, endpoint-to-capability proof, concrete Tor circuits, persistence, reconnect, durable delivery state, retry, and semantic loopback admission remain outside this boundary.

The internal anonymous-batch publisher is the corresponding bounded handoff for one bridge-minted component or local-signature batch. It validates the sealed purpose and material binding, preflights every recipient route group before publication, rejects batch-wide connection reuse, awaits one injected per-recipient publication permit, and drains every delegated exact-three-route/two-accepted-ACK publisher. It is not a timing scheduler, endpoint or Tor provisioner, persistence or retry owner, semantic loopback, or live transport.

The internal contributor transport bridge is one attempt-scoped binding above those publishers. It derives the control context from the validated bootstrap and manifest, accepts either its source-compatible direct test seam or the single managed attempt transport owner, installs the anonymous path only after the exact lease-backed local material returns, preserves the coordinator's PlayerCommit → components → acknowledgement → signatures publication order, and separates a reentrancy-safe stop request from the lifecycle owner's termination wait. The managed path obtains control and purpose-aware anonymous route providers from that owner and rejects raw inbound route injection; the surrounding private composition obtains one inbound-runtime provisioning capability from the same owner. The bridge owns no wallet operation, fan-in startup or supervision, automatic source-loss wiring, timing policy, semantic loopback, persistence, retry, or public session.

A test-only minimum-roster composition constructs six contributor roots and one conductor root from the existing `PostManifestRelayFanIn` → ingress → runtime-driver ownership chain. It proves that one shared attempt and manifest, seven distinct control recipients, twenty-one distinct injected route capabilities, role-matched dependencies, fan-in shutdown, and contributor-bridge drain compose without another production lifecycle actor or any wallet, material, publication, or RSA signing authority. It deliberately stops before manifest admission and does not create a public session, a production route allocator, semantic completion evidence, or a mainnet execution path.

The private mainnet rehearsal is a paired, explicitly slow test path over the existing conductor and contributor executors, not another production supervisor. The conductor half completes the six-contributor authorization and canonical-publication sequence; the contributor half completes exact local BCH signing and `MosaicCompleteTransactionHost` commit. Commit is OpalFusion's terminal wallet boundary: the package exposes no transaction-broadcast callback, and the rehearsal injects only in-memory host and publication seams. Consequently it proves the internal mainnet-profile phase and commit contracts without contacting a wallet, relay, Tor process, or BCH node and without authorizing value movement.

Private mainnet composition has one owner-provisioned runtime path. Only a successfully initialized attempt transport owner can mint its opaque inbound-runtime provisioning value; fan-in alone can request its one claim, and the resulting immutable construction token is required by ingress and the specialized driver. Foreign bootstrap or role substitution does not consume the claim, a second exact claim fails, and any ingress-construction failure closes every transferred route before returning. Focused component tests use either a pure route-plan validator or an inert runtime endpoint that cannot construct ingress. The generic `RuntimeSessionDriver` remains disabled for `.opalMainnetAlpha`, `OpalFusion.Session` remains privately initialized, and neither path can carry transaction bytes or reach a broadcaster. After an exact host commit, OpalBase separately derives a committed candidate and retains its existing security-profile, network-binding, persisted app-approval, persisted broadcast-intent, and network-client gates; none is satisfied by OpalFusion runtime authorization.

The package currently uses one Swift target. This keeps the existing CashFusion implementation source-compatible while the common facade is stabilized.

The Mosaic reducers consume validated aggregate publications, generation-bound host facts, and contributor-local validation tokens, while `RuntimeCoordinator` preserves reservation release, post-sign recovery, exact commit, and terminal ordering against injected seams. Private-alpha recovery reconstructs the same contributor or conductor coordinator, authenticates the exact admission snapshot and original acceptance times before provisioning routes, replays coordinator and wallet callbacks behind an ordered barrier, restores pending outbound publication, and validates write-ahead abort or completion records on a zero-route terminal path. Missing, partial, reordered, substituted, oversized, or inconsistent snapshots fail closed. The generic transport-facing mainnet driver remains disabled. The application still owns durable backends, state cataloging, rollback/deletion detection, cross-process exclusion, recipient-key persistence and distribution, authoritative route allocation, concrete Tor isolation, lifecycle supervision, and composition with Base wallet/chain cleanup evidence.

The control-batch publisher is the bounded handoff between a complete bridge batch and the existing per-recipient relay publishers: it proves context and allocation equality, route preflight, batch-global connection uniqueness, sibling cancellation, and all-route closure without becoming a transport, retry, or loopback owner.

The anonymous-batch publisher applies the same route-preflight, sibling-cancellation, and closure boundary to a sealed anonymous purpose batch, with a distinct injected publication permit immediately before each recipient's relay operation. The permit is caller authority, not proof of scheduling privacy, and connection-object uniqueness is not proof of independent Tor circuits.

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
