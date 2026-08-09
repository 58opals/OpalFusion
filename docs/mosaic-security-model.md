# Mosaic Security Model

Status: Draft companion to [`mosaic-protocol-specification.md`](mosaic-protocol-specification.md). This document owns Mosaic threat assumptions, privacy limits, safe claims, and security release gates.

Mosaic is experimental. Neither this document nor the protocol draft is an audit, proof of anonymity, or production-readiness statement.

The implemented [`Mosaic/0-opal.1`](mosaic-v0-profile.md) slice is a chipnet-only deterministic conformance foundation. The additive [`Mosaic/0-opal-mainnet-alpha.3`](mosaic-mainnet-alpha-profile.md) slice freezes deterministic role, manifest, PlayerCommit, fixed-overhead fee allocation, grouped Pedersen balance, authorization-response-set, complete contributor acknowledgement-set, aggregate, control-envelope, transcript, BCH-signature-set, and complete-transaction contracts, but remains runtime-driver-disabled and rejects legacy aggregate host markers. Its admission ledger binds admitted control and anonymous-component documents through transcript agreement to one attempt, generation, round, roster, local role, roster-derived zero sequence epoch, and monotonic externally validated phase mirror. A paired internal runtime session advances the same validated local attempt through transcript agreement only after an external validator seals the exact reservation-reference and PlayerCommit binding and every local commitment appears in the conductor set; it cannot admit BCH signing or completion. An internal profile-neutral coordinator separately proves in-process host-effect ordering, including late-lease release, the no-release boundary after signing may have begun, exact complete-transaction commit, and recovery-required outcomes against injected seams. Neither profile proves live lease-to-PlayerCommit provenance, a concrete Tor route, salt/opening and privacy-preserving component linkage, production lease-material construction, previous-output-backed wallet ownership and value validation in executable composition, anonymous BCH-signature authorization, production mailbox ingress, coordinator composition, durable recovery, or independent deployment review. These boundaries therefore do not satisfy the remaining transport, cryptographic-review, interoperability, mainnet-execution, or privacy release gates below.

## 1. Security Objectives

Mosaic aims to ensure:

- the protocol grants no conductor, contributor, relay, or observer signing authority over another contributor's reserved wallet inputs;
- contributors sign only a transaction they independently validated and acknowledged;
- conductor equivocation produces an abort before BCH signing;
- the conductor cannot normally link anonymous components to the contributor commitment group that authorized them;
- a failed attempt does not reuse protocol or wallet-output material in a later attempt;
- diagnostics do not become a second source of peer, wallet, or transport linkage.

Mosaic does not guarantee that a completed transaction has a particular anonymity set or that later spending preserves privacy.

## 2. Protected Assets

Protected material includes:

- wallet private keys and signing authority;
- reserved UTXOs and their ownership grouping;
- fresh output locking scripts and their ownership grouping;
- mapping between grouped commitments and anonymous components;
- mapping between input components, output components, and contributors;
- peer IP addresses and timing profiles;
- discovery, control, mailbox, proof, and retry linkages;
- raw transaction proposals and signatures before completion.

The existence of a public collaborative transaction, its public inputs and outputs, fee, and on-chain protocol marker are not secret after broadcast.

## 3. Adversaries

The model considers:

- a malicious conductor;
- one or more malicious contributors;
- a conductor colluding with contributors;
- malicious, censoring, logging, or partitioning relays;
- a global or partial network observer;
- Sybil candidates controlling many discovery identities;
- a participant that aborts at the last useful moment;
- malware or compromise in the wallet host;
- later chain-analysis based on amounts and spending behavior.

Mosaic does not claim protection from a compromised OpalBase signing boundary, a fully global passive observer that defeats the anonymous transport, or an adversary controlling nearly all contributors in a round.

## 4. Trust Assumptions

Security depends on all of the following:

- OpalBase correctly reserves wallet inputs and fresh outputs and validates the complete proposed transaction before signing.
- Bitcoin Cash signature verification and transaction semantics behave as expected.
- At least several contributors are honest and not controlled by one adversary.
- The conductor does not collude with enough external contributors to reconstruct useful component grouping.
- SHA-256, secp256k1 operations, Pedersen commitments, blind signatures, authenticated encryption, and secure randomness remain sound in their specified uses.
- Anonymous transport prevents the conductor and relays from trivially linking control identities to component mailbox connections.
- Implementations erase or rotate attempt-scoped secrets as required.

The conductor is not trusted with funds. It is trusted for liveness only to the degree that any selected conductor can abort an attempt.

## 5. Core Invariants

The following are release-blocking invariants:

1. The conductor does not contribute BCH in its attempt.
2. Wallet reservation starts only after engine selection, role selection, and complete manifest agreement.
3. Every contributor acknowledges one identical transcript root before any BCH signature is requested.
4. OpalBase validates the exact transaction independently of conductor claims.
5. Every BCH signature commits to all inputs and outputs with `SIGHASH_ALL | SIGHASH_FORKID`.
6. Sensitive anonymous submissions never use clearnet fallback.
7. A retry regenerates every output, identity, nonce, commitment, token, salt, key, mailbox, and anonymous network path.
8. Automatic engine fallback never occurs after wallet reservation.
9. Participant count is never presented as a measured anonymity set.

An implementation that violates one of these rules is not Mosaic-compatible.

## 6. Threat Analysis

| Threat | Primary control | Residual risk |
|---|---|---|
| Conductor attempts to steal funds | Host validates the complete transaction and signs only reserved inputs | Compromised host or incorrect validation defeats this boundary |
| Conductor sends different rosters or fees | Every candidate signs one manifest hash | Conductor can abort or partition availability |
| Conductor sends different component sets | Every contributor computes and acknowledges one transcript root | Partition causes abort; it does not guarantee liveness |
| Conductor also verifies participant proofs | Conductor is excluded from contributing | Conductor may still collude with external contributors |
| Relay reads payload | Authenticated encryption with one-time keys | Relay still observes metadata unless anonymous transport and padding hold |
| Relay sees IP address | Tor or reviewed equivalent is mandatory | A global observer may correlate traffic across paths |
| Relay censors or reorders | Multi-relay replication, signatures, sequence numbers, idempotence | Enough relays can deny liveness or partition participants |
| Replay from an earlier attempt | Protocol, network, round, phase, sequence, expiry, and payload digest binding | Implementation state loss may reopen replay windows |
| One-more authorization attempt | Exactly 23 request slots per contributor, all-contributor issuance barrier, cached duplicate response, and spent identifier derived from token input | Security still depends on a vetted RFC 9474 provider and correct persistent replay accounting |
| Participant submits malformed component | Commitment validation and CashFusion-derived blame | Blame can reveal bounded proof material and does not create durable bans |
| Participant withholds reveal or signature | Deadlines and abort | Permissionless peers can repeatedly deny liveness |
| Last revealer selectively aborts role election | Fresh identities and randomness prevent an in-place reroll | Repeated abort-and-rejoin attempts can bias which conductor selections complete |
| Sybil pool capture | Beacon proof of work, oversubscription, role randomness | These only increase cost; they do not provide strong Sybil resistance |
| Amount correlation | Arbitrary amounts, multiple inputs and outputs, host privacy-shape checks | Unusual amounts or poor output shaping remain linkable |
| Retry correlation | Complete attempt-material regeneration | A network observer may correlate closely timed retries |
| Post-fusion recombination | OpalBase coin policy keeps sibling and unfused outputs separate | User spending can undo achieved privacy |
| Diagnostic leakage | Typed aggregate diagnostics with private-field exclusion | Crash reports or app logs outside OpalDiagnostics may still leak |
| One operator controls several configured relays | Signed messages and relay replication preserve validity and improve availability | Endpoint count does not prove operator, jurisdiction, or network-path diversity |

## 7. Conductor Separation Rationale

CashFusion's coordinator knows which commitments arrived from each participant. During blame, a participant may learn selected component proof material. The published CashFusion audit identifies server-plus-player collusion as a privacy weakness because those views can be combined.

Mosaic therefore prohibits the conductor from contributing in the same attempt. This does not eliminate conductor collusion, but it prevents the protocol from automatically assigning both views to one wallet.

Threshold blind signing or multiparty computation could reduce conductor trust further, but both add substantial cryptographic and operational complexity. They are outside the first Mosaic profile.

## 8. Sybil Boundary

Permissionless discovery, low user cost, and strong Sybil resistance cannot all be assumed simultaneously.

Mosaic uses proof of work and oversubscription only as throttles. A well-funded adversary may still control most or all selected identities, become conductor, or repeatedly abort attempts. No documentation or wallet UI may imply otherwise.

Future admission mechanisms such as fidelity bonds, paid credentials, allowlists, or persistent reputation would change the privacy and product model and require a new specification decision.

## 9. Transport Boundary

Nostr provides replicated signed events and convenient relay discovery; it does not provide network anonymity. NIP-44 explicitly notes metadata, forward-secrecy, post-compromise, and IP-observation limits.

The initial Mosaic transport therefore requires:

- one-time identities;
- multiple relays;
- Tor-only relay and mailbox connections;
- isolated paths for sensitive submissions;
- fixed outer ciphertext sizes by message class;
- randomized timing inside signed phase windows;
- no raw relay URL, peer key, mailbox key, or circuit identifier in diagnostics.

If these properties are unavailable, the safe behavior is to wait or fail. Clearnet fallback is a privacy failure, not a degraded success.

When an encoded Opal v0 aggregate fragment is passed through the existing padded-envelope codec, the resulting plaintext is the fixed 8,192-byte size, but the number of fragments reveals an aggregate size class. The fragment codec itself emits variable-length subordinate documents and does not define live envelope sequencing or publication behavior. Fragmentation is not a full size-hiding or traffic-analysis defense.

OHTTP or another relay construction may become a later transport profile only after it demonstrates an equivalent or explicitly different privacy contract. A transport adapter cannot inherit the `nostr-tor` claim merely because payload encryption succeeds.

## 10. Wallet And Host Boundary

OpalFusion never receives mnemonic material or general wallet authority. OpalBase remains responsible for:

- UTXO eligibility and token exclusion;
- expiring reservation leases;
- fresh output generation;
- complete transaction validation;
- signing only intended inputs;
- reservation release or commit;
- transaction broadcast;
- post-fusion coin separation policy.

The Opal v0 host request includes a recomputable binding from the manifest, commitment set, component set, and exact unsigned transaction bytes to the acknowledged transcript root. This prevents an opaque transcript value from authorizing unrelated bytes, but the reducer and transport must still establish authentic unanimous acknowledgement before the request reaches OpalBase.

Reservation and signing APIs must remain actor-safe and idempotent. A timeout, cancellation, duplicate callback, or stale protocol generation must not leave a UTXO permanently reserved or sign a superseded proposal.

## 11. Safe Public Claims

Before independent review, acceptable wording is limited to:

- "Mosaic is a draft peer-to-peer fusion protocol with no fixed coordinator service."
- "Mosaic is designed so contributors retain their signing keys."
- "The current repository contains a deterministic in-process semantic core and integration contracts; no live, interoperable, private, or production-ready Mosaic support is claimed."

The following claims are prohibited without later evidence:

- anonymous;
- untraceable;
- audited;
- production-ready;
- equivalent or superior to CashFusion privacy;
- Sybil-resistant;
- serverless in every deployment sense;
- guaranteed to complete;
- a measured anonymity set based only on participant count.

## 12. Required Verification

The deterministic simulator must cover at least:

- duplicate and malformed beacons;
- candidate-set disagreement;
- role commitment omission and invalid reveal;
- conductor equivocation on manifest, commitments, components, acknowledgements, or results;
- relay censorship, partition, delay, duplication, and reorder;
- stale sequence numbers and cross-round replay;
- malformed Pedersen commitments and blind-token responses;
- missing, duplicated, or invalid components;
- transaction mismatch and unauthorized output;
- missing or invalid BCH signature;
- cancellation during every phase;
- reservation release after every failure path;
- retry attempts proving complete material regeneration;
- automatic-mode downgrade attempts after reservation.

Golden vectors must include both valid and invalid canonical encodings. Fuzzing must cover every parser before any live profile is enabled.

## 13. Review Gates

Production consideration requires:

- complete protocol and transport schemas;
- independent cryptographic review of reused and changed CashFusion constructions;
- independent protocol review of role election, manifest agreement, transcript agreement, blame, and retry behavior;
- traffic-analysis testing across supported Tor and relay environments;
- constant-time and secret-lifecycle review in OpalCrypto;
- OpalBase reservation and transaction-validation review;
- repeated multi-device reliability tests;
- documented incident response and protocol-disable mechanism;
- conservative wallet UX reviewed against the safe-claim boundary.

## 14. References

- [CashFusion protocol specification](https://github.com/cashshuffle/spec/blob/master/CASHFUSION.md)
- [CashFusion security audit](https://electroncash.org/fusionaudit.pdf)
- [NIP-01](https://github.com/nostr-protocol/nips/blob/master/01.md)
- [NIP-44 limitations](https://github.com/nostr-protocol/nips/blob/master/44.md#limitations)
- [CoinShuffle++ / DiceMix](https://eprint.iacr.org/2016/824.pdf)
