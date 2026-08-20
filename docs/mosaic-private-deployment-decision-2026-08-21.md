# Mosaic Private-Deployment.1 Semantic Decision — 2026-08-21

Status: Accepted as the frozen private-deployment contract for Mosaic private-alpha G0. This decision closed the semantic-approval blocker only; the separately recorded [Mosaic G0 Closure Evidence — 2026-08-21](mosaic-g0-closure-evidence-2026-08-21.md) subsequently closed G0 after one exact application dependency graph passed its required local cross-package validation.

## Scope

This decision adopts `nostr-tor/0-opal-mainnet-alpha-private-deployment.1` unchanged for the internal macOS private alpha. It composes the already frozen `Mosaic/0-opal-mainnet-alpha.4` protocol and `nostr-tor/0-opal-mainnet-alpha.5` post-manifest transport profiles without changing either profile's bytes. Any change to a private-deployment field, domain, enum, event kind, ordering rule, endpoint rule, signer authority, timing value, fee mapping, or recovery decision requires a new private-deployment identifier and a new semantic decision.

## Accepted Decisions

| Concern | Accepted decision | Boundary and rationale |
| --- | --- | --- |
| Off-commitment accountability | Retain alpha.4's existing limitation: an authorized anonymous component is not proven to open a member of a contributor-tagged grouped commitment. | A membership proof would change the frozen protocol and add a new cryptographic construction. The private alpha accepts the resulting accountability and collusion risk and makes no anonymity claim. |
| Admission throttle | Require at least 20 leading zero bits in the selector-bound availability-beacon work digest. | This is an operational throttle selected from the recorded M1 Max benchmark, not a security level, identity proof, fairness proof, or Sybil-resistance claim. |
| Candidate and role policy | Select the first seven through nine valid candidates by work digest and discovery key, then elect exactly one non-contributing conductor and six through eight contributors through the frozen commit-reveal mechanism. | Oversubscription and role randomness improve attempt formation but do not prove independent participants or prevent capture and selective abort. |
| Fee policy | Retain alpha.4's exact one-satoshi-per-estimated-final-byte fee rate, one-through-two-satoshi roster-derived contributor excess, ten-satoshi fixed overhead, version 2, lock time zero, final sequence, standard P2PKH, and Schnorr sighash byte `0x41`. | The exact values are already committed by the frozen manifest and host contract; application policy may reject an attempt but may not silently substitute different values. |
| Timing policy | Use one aligned 300-second discovery epoch with pre-manifest offsets `+60`, `+90`, `+120`, `+150`, `+180`, and `+240`, then post-manifest offsets `+60`, `+120`, `+240`, `+300`, and `+360`; the reservation lease expires at the BCH-signing deadline. | One exact schedule prevents implementation-defined deadlines and binds recovery to the same terminal boundary. Overflow, misalignment, or drift fails before state installation. |
| Discovery mapping | Use private NIP-01 ephemeral event kinds `26540...26548`, one exact `d` selector tag, canonical lowercase hexadecimal content, exact signer derivation, strict expiry, and complete canonical decoding. | These kinds are in NIP-01's ephemeral range. Ephemeral relay treatment is not durable evidence, so application persistence and replay remain mandatory. |
| Relay set | Require exactly three canonical `wss://dns-host/` endpoints and three distinct reviewed registry-label digests, with every manifest endpoint bound to one concrete Tor-only capability. | Endpoint and label diversity are configuration assertions only; they do not prove operator, jurisdiction, infrastructure, route, or circuit independence. |
| Relay authentication and work | Reject a relay that requires NIP-42 authentication or relay-required proof of work. Do not invent credentials, identities, or work parameters. | Alpha.5 assigns neither capability. Supporting either would change metadata exposure and the frozen transport contract; the discovery-beacon throttle is separate. |
| Post-manifest delivery | Retain alpha.5's byte-identical regular kind-1059 gift wrap on exactly three relays with at least two accepted acknowledgements and durable publication facts. | Regular gift wraps permit asynchronous retrieval, but acknowledgements do not prove honest storage, route independence, anonymity, or delivery to the semantic runtime. |
| Keys and attempt material | Generate every discovery, control, sender, recipient-mailbox, wrapper, nonce, salt, token, output, and anonymous path value fresh for one attempt; never reconstruct signing material during recovery or reuse it for retry. | OpalCrypto owns primitives; the application owns production generation, Keychain wrapping, encrypted persistence, inventory, and terminal erasure. No external cryptographic runtime dependency is introduced. |
| Recovery and broadcast | Use one authenticated atomically replaced application outer record over Fusion, Base, transport, wallet-inventory/tombstone, and minimum recoverable material state; unknown or ambiguous state stays quarantined. Recovered signing intent never re-signs, and ambiguous broadcast intent reconciles exact chain presence before dispatch. | Package snapshots are not independently atomic. Cross-process ownership, rollback/deletion anchors, startup enumeration, physical cleanup, approval, and exact chain reconciliation remain application obligations. |
| Claims | Until G4 closes, the maximum readiness wording is “deterministic mainnet-alpha contract foundation.” Participant count, relay count, work, and successful tests may not be described as anonymity, Sybil resistance, audit completion, or production readiness. | Nostr encryption and gift wrapping do not hide all metadata, the admission throttle does not establish identity, and the inherited accountability tradeoff remains material. |

## First-Party Dependency Principle

Production implementation remains inside the purpose-specific Opal repositories: OpalCrypto owns cryptographic calculation, OpalFusion owns protocol and transport semantics, OpalBase owns wallet and broadcast authority, SwiftFulcrum owns chain-client correctness, OpalDiagnostics owns only approved privacy-safe diagnostic categories, and Wallet owns deployment composition and policy. External specifications, audits, and implementations are conformance and review inputs only; they are not production runtime dependencies. Cryptographic behavior must follow the selected standards and verified vectors rather than introducing novel constructions.

## Conformance Basis

- RFC 9474 defines RSABSSA and recommends randomized preparation when application requirements do not demand a deterministic variant. OpalCrypto's selected `RSABSSA-SHA384-PSS-Randomized` profile and RFC vector coverage remain the accepted primitive boundary: <https://www.rfc-editor.org/rfc/rfc9474.html>.
- NIP-01 defines event IDs, signatures, strict event structure, and the `20000...29999` ephemeral-kind range used by private discovery: <https://github.com/nostr-protocol/nips/blob/master/01.md>.
- NIP-13 and NIP-42 define relay proof of work and connection authentication. Private-deployment.1 intentionally does not negotiate either and rejects relays that require them: <https://github.com/nostr-protocol/nips/blob/master/13.md> and <https://github.com/nostr-protocol/nips/blob/master/42.md>.
- NIP-44 documents authenticated encryption and its metadata, forward-secrecy, post-compromise, IP, time, and size limitations; NIP-59 defines regular kind-1059 gift wrapping and one-time wrapper keys. These limits are inherited and support the Tor-only and safe-claim boundaries: <https://github.com/nostr-protocol/nips/blob/master/44.md> and <https://github.com/nostr-protocol/nips/blob/master/59.md>.
- The CashFusion specification and published security audit remain the reference inputs for the inherited component-commitment, blind-authorization, blame, collusion, and Sybil tradeoffs. Mosaic's non-contributing conductor and stricter transcript agreement do not erase those residual risks: <https://github.com/cashshuffle/spec/blob/master/CASHFUSION.md> and <https://electroncash.org/fusionaudit.pdf>.

## Residual Risks Accepted For Private Alpha

- A capable Sybil adversary may capture the selected candidate set, become conductor, or repeatedly abort attempts despite the work throttle and oversubscription.
- A malicious conductor colluding with contributors may learn bounded component linkages; the accepted off-commitment design does not add a new membership proof.
- Three reviewed registry labels and three Tor capabilities do not prove independent operators or circuits, and traffic timing may still correlate an attempt.
- NIP-44 and NIP-59 do not provide forward secrecy, post-compromise security, complete metadata hiding, or protection from a sufficiently global observer.
- Relay acknowledgements, local persistence, and deterministic tests do not establish external delivery, chain acceptance, privacy, or bounded-canary safety.

These risks are acceptable only inside the private-alpha gates and safe-claim boundary. A G4 review may reject this acceptance and reopen G0; a successful G5 canary cannot waive it.

## Non-Authorizations

This decision does not authorize concrete external relay or Tor access, credentials, NIP-42 identity use, relay-required proof of work, Fulcrum access, broadcast, value movement, a bounded canary, a public Mosaic session, public release, tags, main-branch promotion, production-readiness wording, or an anonymity claim. Each later gate must still supply its own implementation and evidence, and every externally visible or value-moving action retains its separate approval boundary.

## G0 Follow-Through

The acceptance revision is the OpalFusion commit containing this record and the corresponding status updates in the authoritative documents. G0 may close only after that public integration candidate is consumed through the exact OpalBase and Wallet resolved graph alongside exact OpalCrypto, SwiftFulcrum, and OpalDiagnostics revisions; profile drift must fail before wallet, recovery, transport, or broadcast mutation; and the focused package and Wallet validation evidence is recorded with its exact commands and environment.
