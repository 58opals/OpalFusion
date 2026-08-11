# Opal Fusion Specification

Status: Draft architecture contract. CashFusion has a live pilot implementation. Mosaic has internal aggregate and peer-local attempt cores, an internal ordered host coordinator, the chipnet-only `Mosaic/0-opal.1` conformance profile, and the additive `Mosaic/0-opal-mainnet-alpha.4` deterministic contract profile. Alpha.4 freezes exact contributor-local 23-slot material and openings, deterministic overhead allocation, dual purpose-separated component-bound authorization, complete acknowledgement, authenticated component and BCH-signature mailbox admission, canonical signature-set, and complete-transaction contracts. Its admission ledger enforces attempt, generation, material, roster, round, phase, replay, x-only sender, mailbox, token, and input-index rules; the paired mainnet runtime consumes exact signature-set and complete-transaction facts only through previous-output-backed validation. Internal contributor and conductor executors prove refined-host signing, byte-exact commit, authorization issuance, aggregate publication, anonymous collection, signature validation, and complete-transaction assembly through injected non-network seams. The post-manifest `nostr-tor/0-opal-mainnet-alpha.5` mapping freezes kind-78 rumors, fixed padded content, regular NIP-59 gift wraps, exact tags, sender/recipient binding, cover-timestamp bounds, signed-wrapper replay identity, resource limits, and a three-relay/two-acceptance contract. An internal lifecycle ingress accepts only signed events and resolves their sole recipient identity against an immutable attempt-scoped capability set before a driver-owned bootstrap-bound authentication gate delivers to exactly one freshly constructed role executor. A sender-global internal publication bridge binds one local control/event key pair to the exact roster recipient allocation, starts at sequence zero, preclaims complete aggregate fragment runs, separately signs inner acknowledgements and control envelopes, creates one recipient-bound gift wrap per peer, and advances only after an injected whole-batch acknowledgement boundary. An internal one-shot publisher separately requires validator-sealed manifest relay endpoint identifiers, attempts the byte-identical signed event on exactly three injected Tor-only routes supplied by the route owner, and returns only after two accepted acknowledgements. A separate bounded multi-recipient fan-in validates one shared manifest relay selection, enforces one control mailbox and conductor-only anonymous groups within roster capacity, starts every mailbox's three globally distinct injected subscriptions before consuming into one ingress and runtime, serializes every signed EVENT copy through a bounded FIFO while preserving each route's source order, and fails closed on loss of any selected source. The generic transport-facing mainnet runtime driver remains disabled. Production stateful lease-to-material ownership, recipient-key generation, authenticated distribution and encrypted persistence, durable replay and wrapper-key tracking, authoritative app composition, relay selection and endpoint-to-capability binding, complete production mailbox and route allocation, durable digest-and-sequence duplicate merging, concrete Tor routing, acknowledgement persistence, reconnect, durable recovery, public Mosaic session execution, independent review, and mainnet broadcast remain unimplemented or explicitly gated.

This document defines the Opal Fusion product hierarchy, engine-selection contract, shared session boundary, and source-of-truth order. It does not redefine the CashFusion or Mosaic wire protocols.

## 1. Normative Language

The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHOULD**, **SHOULD NOT**, and **MAY** describe interoperability or safety requirements. Text without one of those terms is explanatory.

## 2. Source-Of-Truth Order

The following documents own distinct scopes:

1. This document owns the Opal Fusion hierarchy, shared facade, and engine-selection rules.
2. [`cashfusion-implementation-spec.md`](cashfusion-implementation-spec.md) owns the pinned Electron Cash `4.4.3` CashFusion `alpha13` client behavior.
3. [`mosaic-protocol-specification.md`](mosaic-protocol-specification.md) owns the Mosaic protocol.
4. [`mosaic-v0-profile.md`](mosaic-v0-profile.md) and [`mosaic-mainnet-alpha-profile.md`](mosaic-mainnet-alpha-profile.md) own their respective Opal profile contracts.
5. [`mosaic-security-model.md`](mosaic-security-model.md) owns Mosaic threat assumptions, privacy limits, and release gates.
6. [`architecture.md`](architecture.md) is the maintainer map and MUST defer to the preceding normative documents when wording differs.

No document may describe Mosaic as CashFusion v2. CashFusion and Mosaic are separate protocols implemented beneath one Opal Fusion facade.

## 3. Product And Protocol Hierarchy

- **Opal Fusion** is the repository, Swift package, and protocol-runtime product in the Opal Bitcoin Cash stack.
- **CashFusion** is the coordinator-based compatibility engine targeting the pinned Electron Cash `alpha13` behavior.
- **Mosaic** is the relay-assisted, peer-conducted protocol with no fixed coordinator service defined by the Mosaic specification.
- **OpalFusion.Session** is the planned protocol-neutral facade that will execute exactly one selected engine for a session.
- **OpalBase** owns wallet policy, automatic scheduling, input eligibility, reservation leases, output generation, signing authority, persistence, and broadcast decisions.
- **Opal Wallet** owns user intent, settings, progress presentation, and product lifecycle.

The word *serverless* SHOULD NOT be used as a protocol guarantee. Mosaic has no fixed trusted coordinator, but discovery or mailbox transports may use relays, bootstrap services, or other servers.

## 4. Engine Registry

| Engine | Mode case | Protocol identity | Current status |
|---|---|---|---|
| CashFusion | `.cashFusion(configuration)` | Electron Cash `alpha13` under the pinned `4.4.3` profile | Live pilot |
| Mosaic | `.mosaic(configuration)` | `Mosaic/1-draft.1`, chipnet-only `Mosaic/0-opal.1`, or contract-only `Mosaic/0-opal-mainnet-alpha.4` | Deterministic foundations with bounded internal adapters; Opal v0 reaches the generic internal driver and alpha.4 has an authenticated post-manifest role selector; no live session |

An engine identity names protocol semantics, not network topology. Public mode cases therefore MUST use `.cashFusion` and `.mosaic`; `.server` and `.peerToPeer` are not engine identifiers.

## 5. Shared Session API

The intended public shape is:

```swift
let session = OpalFusion.Session(
    mode: .cashFusion(cashFusionConfiguration),
    host: host
)

let session = OpalFusion.Session(
    mode: .mosaic(mosaicConfiguration),
    host: host
)

let session = OpalFusion.Session(
    mode: .automatic(automaticConfiguration),
    host: host
)
```

The current scaffold publishes the mode and configuration vocabulary but does not publish a runnable protocol-neutral initializer. Until that facade is implemented, `OpalFusion.Client.Session` remains the only live CashFusion session API.

`OpalFusion.CashFusion.Configuration` currently aggregates coordinator connection, optional genesis hash, join-pool, and reconnect values already consumed by the live CashFusion client. `OpalFusion.Mosaic.Configuration` selects one authoritative `.draft1`, `.opalV0`, or `.opalMainnetAlpha` profile and derives its protocol, roster, and transport contracts. It is not a complete deployment configuration and cannot supply relays, anonymous transport, independently reviewed cryptography, wallet execution, broadcast permission, or a public runtime.

### 5.1 Mode

`OpalFusion.Session.Mode` has three cases:

- `.cashFusion(CashFusion.Configuration)` pins CashFusion before any wallet reservation.
- `.mosaic(Mosaic.Configuration)` pins Mosaic before any wallet reservation.
- `.automatic(AutomaticConfiguration)` evaluates an ordered set of explicitly configured candidates.

The package MUST NOT obtain production coordinator endpoints, relay endpoints, or downgrade permission from hidden defaults.

### 5.2 Automatic Configuration

Automatic configuration contains:

- an ordered, non-empty candidate list;
- at most one configuration for each engine;
- an explicit fallback policy.

The first candidate is the preference. Candidate order is policy supplied by OpalBase or another host; OpalFusion does not invent product preference.

The only permitted cross-engine fallback boundary is `beforeReservationOnly`. A disabled policy selects no later candidate after the preferred candidate fails its preflight.

### 5.3 Selection Algorithm

Automatic selection MUST follow this order:

1. Validate candidate configuration without contacting a wallet host.
2. Determine whether each engine runtime and required privacy transport are available.
3. Perform only privacy-safe availability checks that reveal no wallet input, output, locking script, or reservation identity.
4. Select the first eligible candidate permitted by the fallback policy.
5. Pin the selected engine and emit a selection result.
6. Only then request wallet reservation material.

Selection MUST NOT:

- reserve wallet inputs while evaluating multiple engines;
- submit the same contribution, output, key, commitment, or transcript material to more than one engine;
- switch engines after reservation begins;
- silently downgrade from an anonymous transport to clearnet;
- treat participant count as a measured anonymity set.

If a pinned engine fails after reservation, the session ends. A later attempt MUST be a new session attempt with released or expired reservations and freshly generated protocol material.

## 6. Shared Lifecycle

The protocol-neutral facade normalizes lifecycle, not protocol internals. Its coarse state model is:

1. `idle`
2. `selecting`
3. `discovering`
4. `waiting`
5. `round`
6. `completed`
7. `failed`
8. `stopped`

An engine MAY skip states that do not apply. CashFusion may move from selection directly to coordinator connection and queue waiting. Mosaic uses discovery, candidate formation, role selection, and round execution.

The shared snapshot MUST identify:

- selected engine, when selected;
- selection reason suitable for diagnostics and host policy;
- coarse lifecycle state;
- coarse round state and terminal outcome;
- a privacy-safe error category;
- optional engine-specific detail carried in an engine-tagged value.

The shared snapshot MUST NOT make coordinator state mandatory because Mosaic has no fixed coordinator. Existing `CoordinatorStatus` remains CashFusion-specific.

## 7. Host Boundary

OpalFusion owns protocol execution. The host owns funds and wallet policy.

The eventual shared host boundary MUST support:

- creating an expiring reservation lease for eligible wallet inputs and fresh outputs;
- validating the complete proposed Bitcoin Cash transaction;
- authorizing signatures only for the host-owned inputs in that exact transaction;
- releasing a reservation after abort, failure, timeout, or stop;
- committing a reservation after a complete signed transaction is accepted by host policy;
- reporting broadcast separately from protocol assembly.

Engine-specific fields MUST remain engine-specific. CashFusion tier size, component count, excess-fee bounds, and coordinator status MUST NOT become fake requirements for Mosaic.

Private keys, wallet persistence, transaction broadcast, and user approval MUST remain outside OpalFusion.

## 8. Result Contract

A successful protocol result should carry:

- selected engine;
- session and round identifiers;
- complete signed transaction bytes or a host-owned reference to them;
- Bitcoin Cash transaction identifier when derivable;
- contributor count;
- transaction fee in satoshis;
- reservation identity;
- whether broadcast was attempted and its separately reported outcome.

Raw transaction bytes, outpoints, locking scripts, addresses, peer keys, relay endpoints, and transport identifiers are private diagnostic material.

## 9. Module Boundaries

The intended package decomposition is:

```text
OpalFusionCore
CashFusionEngine
MosaicEngine
OpalFusion
```

The current source remains in one Swift target while the shared contract is stabilized. A target split MUST preserve a single `import OpalFusion` integration surface and MUST NOT expose wire or runtime implementation types merely to avoid adapter work.

Shared code is limited to:

- engine identity and mode configuration;
- coarse session lifecycle and result models;
- genuinely protocol-neutral host contracts;
- privacy-safe diagnostics;
- reusable adapters to OpalCrypto.

CashFusion wire messages, timing, coordinator state, and compatibility fixtures stay in the CashFusion engine. Mosaic discovery, role election, manifest, transcript, mailbox transport, and retry freshness stay in the Mosaic engine.

## 10. Support Claims And Versioning

- `CashFusion alpha13-compatible` is an interoperability claim and requires the evidence in the CashFusion support statement.
- `Mosaic draft` means the semantic design is under review and is not an interoperability, privacy, or production-readiness claim.
- `Mosaic mainnet-alpha contract foundation` means only that the deterministic profile bytes and fail-closed validation boundaries in [`mosaic-mainnet-alpha-profile.md`](mosaic-mainnet-alpha-profile.md) are implemented; it is not a live-engine or mainnet-readiness claim.
- `Mosaic/1` MUST NOT be published until canonical wire encoding, transport identifiers, test vectors, deterministic simulation, and independent security review gates are complete.
- A change to a signed field, canonical encoding, domain separator, transaction construction rule, or required phase is a Mosaic protocol-version change.
- Documentation and internal refactoring that preserve all observable protocol bytes do not require a protocol-version change.

## 11. Scaffold Acceptance

This specification-first slice is complete when:

- public engine, mode, automatic configuration, CashFusion configuration, and Mosaic draft profile types compile;
- the current CashFusion session remains source-compatible;
- no public API claims that Mosaic can execute a live round;
- README, architecture, integration, validation, and support documents distinguish current implementation from draft design;
- deterministic tests lock the scaffolded configuration invariants.
