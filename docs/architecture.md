# OpalFusion Architecture Guide

This guide maps the current package and its intended two-engine architecture. The normative hierarchy is [Opal Fusion Specification](opal-fusion-specification.md); protocol behavior is owned separately by [CashFusion Implementation Spec](cashfusion-implementation-spec.md) and [Mosaic Protocol Specification](mosaic-protocol-specification.md). The bounded private-alpha implementation status and remaining gates are recorded in [Mosaic Mainnet-Alpha Progress](mosaic-mainnet-alpha-progress.md).

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
| Admission and replay | `AdmissionLedger` for semantic admission; one attempt-bound post-manifest journal for accepted digest, sequence, wrapper, and mailbox replay facts | The journal appends before coordinator effects and merges relay copies. A restored nonempty journal fails closed because complete runtime/coordinator restoration is not yet implemented. |
| Wallet lifecycle | OpalBase's host lifecycle and write-ahead attempt journal | OpalFusion's reservation coordinator owns one in-memory pending disposition and returns exact release, commit, or recovery requirements; it does not persist or execute wallet recovery. |
| Outbound publication | One peer-local attempt transport owner allocates mailbox-bound route groups and rejects connection or isolation-lease reuse across that owner's purposes; control/anonymous bridges seal exact context; batch and relay publishers own publication | The injected provisioner owns cross-peer allocation plus endpoint-to-connection and Tor-isolation attestation. Publication owns neither semantic loopback nor retry persistence. |
| Inbound fan-in | The attempt transport owner issues one role-complete inbound-runtime provisioning capability; the owner-provisioned relay fan-in path consumes its single attempt binding, starts and drains the mailboxes, and ingress authenticates recipients before typed delivery | The capability carries no admission, wallet, or broadcast authority. Fan-in still has a raw internal route-group constructor for component tests, so owner provisioning is not yet the sole module-level construction authority; concrete Tor proof, durable storage, and full runtime recovery also remain external. |

## Current Public Surface

- `OpalFusion.Client.Session` is the only runnable session. It executes the CashFusion pilot.
- `OpalFusion.CashFusion.Configuration` aggregates the values consumed by that live client and prepares an engine-specific configuration boundary.
- `OpalFusion.Mosaic.Configuration` selects one authoritative `.draft1`, `.opalV0`, or `.opalMainnetAlpha` profile. Opal v0 supplies the chipnet conformance and generic internal runtime-driver path. Mainnet-alpha.4 adds exact 23-slot local material, salt and Pedersen openings, dual purpose-separated authorization, typed control/anonymous admission, canonical signature/transaction documents, and internal contributor and conductor executors without adding a runnable public session. `LocalContributionMaterial` is constructible only through its validated builder and can mint reservation-publication and transcript-inclusion facts for its exact attempt, generation, material, contributor, manifest, and lease; production live-lease ownership, persistence, freshness across retries, and erasure remain an external material-owner responsibility. `AdmissionLedger` admits component sequence zero and BCH-signature sequence one at a local conductor using one-time x-only sender and recipient-mailbox identities. The paired `OpalMainnetAlpha.RuntimeSession` consumes exact acknowledgement, signature-set, complete-payload, and previous-output-backed completion validations. The frozen `nostr-tor/0-opal-mainnet-alpha.5` adapter maps canonical post-manifest envelopes into regular NIP-59 gift wraps with exact encoded NIP-44 payload-content widths. Its ingress owns the lifecycle boundary and resolves the sole outer recipient identity against an immutable attempt-scoped capability set; the internal `PostManifestRuntimeDriver` then derives the bootstrap context, authenticates and decrypts each event with the selected channel and key, constructs the mainnet runtime, and selects the roster-derived role. A sender-global internal publication bridge binds one local control and event signing authority plus one exact recipient key per roster identity, starts its sequence at zero, preclaims every aggregate fragment run, creates one recipient-bound gift wrap per peer, and advances only after a whole-batch acknowledgement-aware handoff. One internal attempt transport owner validates a caller-authenticated role projection, exposes only each contributor's anonymous public identities while holding the conductor's complete anonymous private set without contributor labels, provisions the complete inbound allocation once, and returns one opaque attempt-bound runtime capability while rejecting connection, isolation-lease, or subscription reuse across all local purposes. The owner adapts the existing control and purpose-aware anonymous batch providers without receiving publication bytes. A one-shot internal relay publisher validates the frozen outer shape and injected manifest-relay-digest endpoint identifiers, attempts one byte-identical event on exactly three opaque injected Tor-only routes, requires two accepted acknowledgements, and closes every route without reconnect or fallback. The bounded multi-recipient fan-in consumes that capability once before constructing ingress and the specialized mainnet driver, then starts every mailbox's three globally distinct injected subscriptions, serializes signed EVENT copies through a bounded FIFO while preserving each route's source order, and treats source loss as terminal. One attempt-bound journal records only semantically admitted control digest/sequence and anonymous wrapper/mailbox replay facts before coordinator effects; exact relay copies create one store append, and a restored nonempty journal fails closed rather than pairing partial replay state with a fresh runtime. Authenticated cross-peer mailbox distribution, recipient-key generation and encrypted persistence, authoritative relay selection, concrete endpoint-to-connection and Tor-isolation attestation, full runtime/coordinator crash restoration, acknowledgement persistence, and reconnect remain outside that adapter, and the generic `RuntimeSessionDriver` still rejects mainnet-alpha.
- `OpalFusion.Session.Mode` defines `.cashFusion`, `.mosaic`, and ordered `.automatic` selection.
- `OpalFusion.Session.AutomaticConfiguration` rejects an empty candidate set and duplicate engines and makes fallback policy explicit.
- `OpalFusion.Session` intentionally has no public initializer or runtime methods until engine selection and wallet reservation can be enforced as one safe operation.

The internal post-manifest control-batch publisher binds a bridge-minted batch to its exact bootstrap context, complete roster recipient allocation, and manifest relay selection; preflights every recipient route group using only recipient event identities; rejects connection reuse across groups; and drains every delegated exact-three-route/two-accepted-ACK publisher. Endpoint provisioning, endpoint-to-capability proof, concrete Tor circuits, persistence, reconnect, durable delivery state, retry, and semantic loopback admission remain outside this boundary.

The internal anonymous-batch publisher is the corresponding bounded handoff for one bridge-minted component or local-signature batch. It validates the sealed purpose and material binding, preflights every recipient route group before publication, rejects batch-wide connection reuse, awaits one injected per-recipient publication permit, and drains every delegated exact-three-route/two-accepted-ACK publisher. It is not a timing scheduler, endpoint or Tor provisioner, persistence or retry owner, semantic loopback, or live transport.

The internal contributor transport bridge is one attempt-scoped binding above those publishers. It derives the control context from the validated bootstrap and manifest, accepts either its source-compatible direct test seam or the single managed attempt transport owner, installs the anonymous path only after the exact lease-backed local material returns, preserves the coordinator's PlayerCommit → components → acknowledgement → signatures publication order, and separates a reentrancy-safe stop request from the lifecycle owner's termination wait. The managed path obtains control and purpose-aware anonymous route providers from that owner and rejects raw inbound route injection; the surrounding private composition obtains one inbound-runtime provisioning capability from the same owner. The bridge owns no wallet operation, fan-in startup or supervision, automatic source-loss wiring, timing policy, semantic loopback, persistence, retry, or public session.

A test-only minimum-roster composition constructs six contributor roots and one conductor root from the existing `PostManifestRelayFanIn` → ingress → runtime-driver ownership chain. It proves that one shared attempt and manifest, seven distinct control recipients, twenty-one distinct injected route capabilities, role-matched dependencies, fan-in shutdown, and contributor-bridge drain compose without another production lifecycle actor or any wallet, material, publication, or RSA signing authority. It deliberately stops before manifest admission and does not create a public session, a production route allocator, semantic completion evidence, or a mainnet execution path.

The private mainnet rehearsal is a paired, explicitly slow test path over the existing conductor and contributor executors, not another production supervisor. The conductor half completes the six-contributor authorization and canonical-publication sequence; the contributor half completes exact local BCH signing and `MosaicCompleteTransactionHost` commit. Commit is OpalFusion's terminal wallet boundary: the package exposes no transaction-broadcast callback, and the rehearsal injects only in-memory host and publication seams. Consequently it proves the internal mainnet-profile phase and commit contracts without contacting a wallet, relay, Tor process, or BCH node and without authorizing value movement.

Private mainnet composition has a separate one-shot owner-provisioned path. Only a successfully initialized attempt transport owner can mint its opaque inbound-runtime provisioning value, and that path rejects a foreign bootstrap, role substitution, or second claim before constructing ingress and the specialized driver. Fan-in still retains a raw internal route-group initializer for focused component tests, so the capability is not yet the sole module-level construction authority. The generic `RuntimeSessionDriver` remains disabled for `.opalMainnetAlpha`, `OpalFusion.Session` remains privately initialized, and neither path can carry transaction bytes or reach a broadcaster. After an exact host commit, OpalBase separately derives a committed candidate and retains its existing security-profile, network-binding, persisted app-approval, persisted broadcast-intent, and network-client gates; none is satisfied by OpalFusion runtime authorization.

The package currently uses one Swift target. This keeps the existing CashFusion implementation source-compatible while the common facade is stabilized.

The Mosaic reducers consume validated aggregate publications, generation-bound host facts, and contributor-local validation tokens, while `RuntimeCoordinator` preserves reservation release, post-sign recovery, exact commit, and terminal ordering against injected seams. The mainnet reservation coordinator keeps one pending disposition: either the first terminal failure or one exact recovery requirement with that failure retained only as its fallback terminal outcome. Alpha.4's admission ledger owns canonical control replay and anonymous collection: it requires complete PlayerCommit and material-bound response-set evidence, rejects same-x communication-key reuse across the aggregate and anonymous paths, admits purpose-zero component tokens at mailbox sequence zero, admits purpose-one BCH-signature tokens at sequence one only after the exact acknowledgement set, and emits a sorted signature set only when every input is present. Authorization is an accounting and replay authority, not a grouped-commitment membership proof; the versioned profile explicitly accepts the off-commitment limitation. The mainnet-alpha runtime binds that set and the published complete transaction to exact previous outputs. Its contributor executor composes the validated material builder, refined host, local signature extraction, publication seams, and byte-exact commit while preserving the pre-sign release and post-sign recovery boundary. Its conductor executor owns both attempt-scoped authorization ledgers, admits anonymous component and signature deliveries through the same runtime, resolves previous outputs once, hands response, commitment, component, acknowledgement, signature, and complete-transaction publications to an injected publisher, and advances only after their later authenticated admission. The control-publication bridge derives its immutable context through the validated runtime bootstrap, accepts only the exact manifest, sealed reservation/transcript validations, or coordinator-minted conductor publications for that attempt, generation, and material, and emits one sender sequence with complete roster-wide recipient batches without owning semantic loopback. The anonymous-publication bridge binds the exact local material before accepting coordinator-minted component or signature validations, maps the same one-time mailboxes to purpose-distinct sender keys at sequences zero and one, and exposes only recipient identities plus sealed gift wraps to an injected whole-batch handoff. The post-manifest ingress owns attempt-lifetime recipient lookup before forwarding each signed event to a driver that derives the bootstrap context, authenticates and decrypts it, and privately routes the typed delivery; it owns no persistent key store. Its injected admission-journal store is the one inbound replay append seam and is durable only when its implementation is durable. Coordinators stage runtime mutation, append only a state-consuming authenticated admission, and install its effects after the append succeeds; inputs that consume no replay state append nothing, exact relay copies append once, and existing terminal rejection rules remain unchanged. A nonempty restored journal is a recovery signal, not a runtime snapshot, so startup fails closed. The one-shot relay publisher owns only the outbound three-route/two-acknowledgement operation over injected Tor-only sessions. The bounded multi-recipient fan-in owns only validation and startup of externally provisioned three-route mailbox groups, one shared ingress/runtime FIFO, serial EVENT forwarding, source-loss closure, and accepted-FIFO drain; it does not allocate mailboxes or prove circuit isolation. Each selected coordinator owns its bounded queue, causal effect drain, source-loss ordering, and terminal disposition. The generic transport-facing mainnet driver remains disabled. Production mailbox and route allocation, complete runtime/coordinator crash restoration, concrete Tor execution, reconnect policy, recipient-key generation, authenticated distribution and encrypted persistence, stateful material ownership, authoritative app composition, durable recovery execution, explicit broadcast approval, and deployment review are not implemented.

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
