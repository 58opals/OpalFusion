# Mosaic Protocol Specification

Status: Draft `0.1`. Protocol identifier: `Mosaic/1-draft.1`. This document does not define a production-ready or interoperable `Mosaic/1` release.

Mosaic is a relay-assisted, peer-conducted collaborative transaction protocol for Bitcoin Cash with no fixed coordinator service. It reuses the useful component, Pedersen commitment, blind-token, and blame design of CashFusion while replacing the fixed coordinator service with an ephemeral conductor selected from a short-lived candidate set.

The conductor coordinates one attempt but MUST NOT contribute transaction inputs or outputs in that attempt.

## 1. Normative Language

The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHOULD**, **SHOULD NOT**, and **MAY** are normative.

## 2. Status And Compatibility

- The only identifier defined by this document is `Mosaic/1-draft.1`.
- [`Mosaic/0-opal.1`](mosaic-v0-profile.md) is a separate Opal-owned chipnet conformance profile that resolves only the deterministic contracts documented there; it does not rename or complete this draft.
- [`Mosaic/0-opal-mainnet-alpha.4`](mosaic-mainnet-alpha-profile.md) is a separate additive contract profile. It freezes mainnet identity, fee allocation, contributor material, grouped balance, purpose-separated authorization, complete acknowledgements, control sequencing, anonymous mailbox sequences, signatures, and complete-transaction assembly. Its alpha.5 mapping adds attempt-scoped recipient lookup, exact control and anonymous publication bridges, three-route/two-acknowledgement publishers, bounded multi-recipient fan-in, one injected write-ahead journal for semantically accepted digest/sequence and wrapper/mailbox replay facts, and one injected outbound publication journal for complete batches, permits, relay attempts, acknowledgements, and terminal outcomes. Relay copies append once, rejected traffic consumes no admission state, and publication append uncertainty is reconciled by exact readback. Neither journal is a complete runtime snapshot: nonempty admission restart still fails closed until admission, phase, coordinator, wallet, and inbound restoration exist. The generic mainnet driver, production mailbox allocation and key persistence, concrete Tor transport, full crash continuation, app wallet composition, and broadcast remain gated.
- The checked-in `Mosaic/0-opal.1` implementation constructs and binds the deterministic unsigned transaction and fails closed unless a contributor-local validation token is sealed to the exact attempt material and transcript. It does not yet implement the profile-owned commitment-opening/component-linkage validator that may produce that token in production.
- The checked-in internal host coordinator proves ordered release, signing, exact-commit, and recovery-required behavior through injected seams. It is not a public session, durable recovery implementation, transport adapter, or authority to enable the mainnet-alpha runtime.
- The checked-in internal control-batch publisher accepts only a bridge-minted batch with the exact bootstrap context, complete roster recipient allocation, and manifest relay selection; atomically journals the complete batch; records each relay attempt, acknowledgement, and terminal outcome before the corresponding effect; reconciles uncertain appends; restores acknowledgement-derived terminal outcomes before requesting new routes; rejects connection reuse across recipients; delegates each gift wrap to one exact-three-route/two-accepted-ACK publisher; and drains every route before returning. It does not provide a durable backend, provision endpoints or Tor circuits, restore admission or coordinator runtime, or admit semantic loopback.
- The checked-in contributor anonymous-publication bridge accepts only exact-material-bound component and BCH-signature validations minted after the contributor executor's local gates. It hands off one complete 23-component sequence-zero batch, then the exact local-input sequence-one signature batch on the corresponding mailboxes with distinct material-owned anonymous-envelope communication identities. Failure or cancellation is terminal, and the injected handoff does not allocate routes, define timing, persist or erase keys, retry, perform semantic loopback, or enable live mainnet execution.
- The checked-in anonymous-batch publisher accepts only the bridge-minted purpose and material binding, atomically journals the complete recipient set before publication, records one injected permit per recipient before opening that route, restores recorded permits and acknowledgement-derived terminal outcomes, rejects allocation mismatch and batch-wide connection reuse, delegates every sealed wrap to the exact-three-route/two-accepted-ACK publisher, and drains all routes. The durable backend, permit, and route providers remain external authorities; this value neither defines timing nor proves endpoint authority, Tor-circuit isolation, durable delivery, complete runtime recovery, or live execution.
- The checked-in mainnet-alpha admission ledger enforces exact attempt, generation, material, round, roster, publisher, sender sequence, immediate externally validated phase ordering, complete PlayerCommit and response-set collection, material-bound local blind-response finalization, one-time x-only anonymous sender and mailbox identities, purpose-specific replay, portable acknowledgements, and conductor signature collection. Alpha.4 explicitly accepts that a valid authorization proves one accounted component but not membership in a contributor-tagged grouped commitment; honest contributors still verify exact local inclusion before acknowledgement. The paired internal runtime consumes the exact signature set and complete transaction only after previous-output-backed validation. Internal contributor and conductor executors prove the post-manifest role paths through injected host, previous-output, and publication seams, including exact commit on contributors and canonical authorization, aggregate, signature, and transaction publication on a conductor. A lifecycle ingress accepts only signed post-manifest events, resolves their sole `p` identity against its immutable attempt-scoped recipient capabilities, and supplies the selected key and channel to an internal driver that derives the bootstrap context, authenticates and decrypts the event, and privately routes the typed delivery into exactly one executor. A separate one-shot publisher validates the frozen outer gift-wrap shape and injected manifest-relay-digest endpoint identifiers, attempts one byte-identical event on exactly three opaque injected Tor-only relay routes supplied by the route owner, requires two accepted NIP-01 acknowledgements, and closes every route without reconnect or fallback. The generic mainnet driver remains disabled, so these internal contracts do not authorize live mainnet execution.
- Implementations MUST reject unknown Mosaic protocol identifiers.
- Implementations MUST NOT advertise this draft as `Mosaic/1`, CashFusion v2, audited, production-ready, or privacy-equivalent to CashFusion.
- CashFusion wire compatibility is not a Mosaic goal. Reused cryptographic ideas do not make the protocols wire-compatible.
- Mainnet execution remains prohibited until the release gates in Section 18 and the remaining gates in the selected profile are complete.

## 3. Goals

Mosaic aims to provide:

- noncustodial collaborative Bitcoin Cash transactions;
- no fixed trusted coordinator service;
- arbitrary participant input and output amounts within explicit fee and component constraints;
- concealed ownership grouping for transaction components;
- detection of conductor equivocation before BCH signing;
- bounded blame evidence for malformed or missing contributions;
- cheap participation with no protocol or conductor fee;
- a wallet integration that can run without exposing protocol topology to the user interface.

## 4. Non-Goals

Mosaic does not promise:

- a fully leaderless round;
- strong Sybil resistance in a permissionless pool;
- guaranteed availability or successful matching;
- a numerical anonymity score derived from participant count;
- protection from later spending behavior that recombines outputs;
- privacy over clearnet transport;
- compatibility with arbitrary Bitcoin Cash locking scripts in the first profile;
- CashTokens participation in the first profile;
- persistent peer identities, reputation, bans, or fees.

## 5. Roles

### 5.1 Candidate

A candidate advertises short-lived availability for one discovery epoch using a one-time identity key. A candidate reveals no outpoint, locking script, exact BCH amount, output count, wallet identifier, or reusable network identity.

### 5.2 Conductor

The conductor sequences one attempt, validates grouped commitments, performs blind signing, publishes canonical aggregate sets, verifies anonymous component and transaction-signature submissions, and coordinates blame.

The conductor MUST NOT contribute a transaction input, transaction output, blank component allocation, or BCH signature in the same attempt. This role separation reduces the server-plus-participant collusion surface identified in the CashFusion security analysis.

### 5.3 Contributor

A contributor reserves wallet inputs and fresh outputs, constructs exactly the required number of input, output, and blank components, verifies all shared protocol material, acknowledges one final transcript root, and signs only its own inputs in the exact acknowledged transaction.

### 5.4 Relay And Mailbox Transport

Relays carry signed control messages and encrypted mailbox payloads. A relay is not a protocol authority and cannot make an invalid message valid. Relay availability, IP observation, timing observation, filtering, and partitioning remain threat-model concerns.

## 6. Draft Profile Parameters

| Parameter | `Mosaic/1-draft.1` value |
|---|---|
| Bitcoin Cash network | Committed by 32-byte genesis block hash |
| Target contributors | 8 |
| Minimum contributors | 6 |
| Conductors per attempt | 1 |
| Maximum candidates selected | 9 |
| Components per contributor | 23 |
| Component types | input, output, blank |
| Control identity signature | BIP340 Schnorr over secp256k1, as used by NIP-01 |
| Hash function | SHA-256 |
| BCH input signature | Schnorr with `SIGHASH_ALL | SIGHASH_FORKID` |
| Initial live transport profile | `nostr-tor/1-draft.1` |
| Anonymous transport | Required; no clearnet fallback |

The fee rate, minimum excess fee, maximum excess fee, discovery epoch, relay-set digest, and phase deadlines are fixed in the signed manifest for each attempt. They are not hidden conductor policy.

## 7. Cryptographic Separation

Mosaic uses independent key domains:

- one-time discovery identity;
- one-time control identity for the attempt;
- one-time transport event identities;
- conductor blind-signing key;
- per-component communication and mailbox keys;
- per-proof encryption keys;
- wallet-owned Bitcoin Cash signing keys.

No discovery, control, mailbox, or proof key may be derived from a wallet private key. A wallet public key used to authorize a Bitcoin Cash input MUST NOT be used as a Mosaic identity.

The following ASCII domain strings are reserved by this draft:

```text
Mosaic/1-draft.1/beacon
Mosaic/1-draft.1/candidate-set
Mosaic/1-draft.1/control-roster
Mosaic/1-draft.1/role-commitment
Mosaic/1-draft.1/role-seed
Mosaic/1-draft.1/manifest
Mosaic/1-draft.1/message
Mosaic/1-draft.1/transcript
Mosaic/1-draft.1/pre-sign-ack
Mosaic/1-draft.1/commitment-set
Mosaic/1-draft.1/component-set
Mosaic/1-draft.1/unsigned-transaction
Mosaic/1-draft.1/retry
```

A digest defined below is `SHA256(UTF8(domain) || canonicalBody)`. Domain strings include their exact capitalization and punctuation and are not NUL-terminated.

## 8. Canonical Hash Encoding

Wire transports may wrap messages differently, but all signed and transcript-committed objects MUST use the same canonical hash encoding.

Primitive encodings are:

- `u8`, `u16`, `u32`, and `u64`: unsigned big-endian integers of the named width;
- `bool`: `0x00` for false or `0x01` for true;
- `bytes`: `u32(length) || rawBytes`;
- `text`: UTF-8 encoded as `bytes`; protocol text fields are restricted to printable ASCII;
- `optional<T>`: `0x00` when absent or `0x01 || T` when present;
- `vector<T>`: `u32(count) || item[0] || ... || item[count-1]`;
- fixed-size hashes and keys: raw bytes without a length prefix where the field table fixes their size.

Structures encode fields once, in the order listed by this specification. No field is omitted because it has a default value. Maps are prohibited in signed bodies. Sets are encoded as vectors sorted lexicographically by each item's canonical bytes.

Malformed lengths, non-canonical ordering, duplicate set members, invalid booleans, trailing bytes, unknown enum values, and invalid UTF-8 MUST be rejected.

The complete field-numbered wire schema and golden byte fixtures remain release-blocking work. Until those artifacts exist, separate implementations MUST NOT claim interoperability.

## 9. Message Envelope

Every post-admission authenticated control message commits to:

1. protocol identifier;
2. 32-byte Bitcoin Cash genesis block hash;
3. 32-byte round identifier, or all zeroes before a round exists;
4. phase identifier;
5. sender one-time control public key;
6. monotonically increasing sender sequence number;
7. payload type;
8. SHA-256 payload digest;
9. expiry time;
10. identity signature over the domain-separated canonical body.

Discovery beacons, candidate-set acknowledgements, and candidate admissions use their discovery/control signatures as defined in Section 10 because the post-admission envelope does not yet apply.

Receivers MUST reject a message with the wrong network, protocol, round, phase, sender, sequence, payload digest, expiry, or signature. Exact duplicate messages are idempotent. Conflicting messages with the same sender and sequence are equivocation evidence and abort the attempt.

Anonymous component and transaction-signature submissions do not carry the contributor control identity. They bind to a round, a one-time authorization token, and their payload digest.

### 9.1 Phase Discipline

One attempt moves monotonically through discovery, candidate-set agreement, control-roster agreement, role selection, manifest agreement, wallet reservation, grouped commitment, anonymous component submission, transcript agreement, BCH signing, and completion. A receiver MUST reject a message from an earlier completed phase or a future phase whose prerequisites are incomplete, except an exact idempotent duplicate explicitly permitted by that phase.

Discovery, candidate-set, control-roster, and role-selection deadlines come from the frozen transport profile because no manifest exists yet. Post-manifest deadlines come from the unanimously signed manifest. A timeout, invalid transition, equivocation, or missing required participant aborts the attempt; an implementation MUST NOT roll back to an earlier phase or substitute a candidate in place.

## 10. Discovery And Candidate Formation

### 10.1 Availability Beacon

A signed `AvailabilityBeacon` contains only:

- protocol identifier;
- Bitcoin Cash genesis block hash;
- discovery epoch;
- opaque coarse pool identifier;
- one-time discovery public key;
- relay-set digest;
- proof-of-work nonce and claimed work bits;
- expiry time.

The beacon MUST NOT contain exact BCH amounts, outpoints, locking scripts, addresses, input count, output count, wallet age, persistent identity, or IP-derived data.

The beacon's work digest is `SHA256(domainBeacon || canonical(AvailabilityBeaconCore))`, where the core contains every listed field except claimed work bits and the identity signature. Claimed work bits MUST equal the number of leading zero bits in that digest. The discovery identity signs the domain-separated canonical beacon body including the claimed count.

The proof of work is an admission throttle, not Sybil resistance. The draft minimum work value is intentionally not frozen until device benchmarks exist. The final profile MUST freeze one minimum and include it in conformance vectors.

### 10.2 Candidate Set

At an epoch cutoff, each candidate independently:

1. validates beacons for one network, protocol, pool, epoch, relay-set digest, expiry, and minimum work;
2. deduplicates identical beacons and rejects a discovery key that advertises more than one distinct valid beacon core in the epoch;
3. sorts candidates lexicographically by `(workDigest, discoveryPublicKey)`;
4. selects the first nine valid candidates, or all candidates when seven or eight are available;
5. aborts formation when fewer than seven candidates remain.

Seven candidates produce one conductor and six contributors. Nine candidates produce one conductor and eight contributors.

The candidate-set digest is `SHA256(domainCandidateSet || canonical(sortedAvailabilityBeaconBodies))`. It includes each selected beacon body and claimed work count but excludes transport wrappers and signatures after those signatures have been verified.

Each selected candidate signs a `CandidateSetAcknowledgement` containing the candidate-set digest with its discovery key. All selected candidates MUST obtain and validate the complete acknowledgement set before role selection. A disagreement, missing acknowledgement, or nonresponsive selected candidate aborts formation without wallet reservation; the attempt does not replace that candidate in place.

### 10.3 Control Roster

After candidate-set agreement, every selected candidate generates a one-time BIP340 control key and publishes a `CandidateAdmission` containing the protocol identifier, network genesis hash, candidate-set digest, discovery public key, control public key, and expiry. The admission MUST carry valid signatures from both the discovery key and the control key, proving the binding and possession of both keys.

Every candidate validates exactly one admission for each selected discovery key and rejects duplicate control keys. Admissions are sorted by discovery public key. `controlRosterDigest = SHA256(domainControlRoster || candidateSetDigest || canonical(sortedAdmissions))`. Every role commitment, reveal, role seed, and manifest MUST bind this digest.

## 11. Commit-Reveal Role Selection

Role selection uses commit-reveal randomness so no single successful participant chooses the conductor.

1. Each candidate generates 32 random bytes `r` after validating the complete control roster.
2. Each publishes `RoleCommitment = SHA256(domainRoleCommitment || controlRosterDigest || controlPublicKey || r)`.
3. After every valid commitment is present, each candidate reveals `r`.
4. Every reveal MUST match its commitment.
5. Sort `(controlPublicKey, r)` pairs lexicographically by control public key and calculate `RoleSeed = SHA256(domainRoleSeed || controlRosterDigest || canonical(sortedPairs))`.
6. Interpret the first eight bytes of `RoleSeed` as a big-endian `u64` and calculate `conductorIndex = value mod candidateCount`.
7. Select the conductor from the same control-public-key-sorted vector; every other candidate is a contributor.

A missing commitment, missing reveal, duplicate control key, or invalid reveal aborts the attempt. The last revealer can deny liveness and may selectively abort attempts whose result it dislikes. It cannot change the result of a completed attempt, but repeated selective aborts can bias which attempts complete. A restart requires fresh discovery and control identities and fresh random values; the security model treats cross-attempt selection bias as residual risk rather than claiming unbiased leadership.

Wallet reservation MUST NOT begin before role selection succeeds and the manifest is accepted.

## 12. Round Manifest

The conductor proposes `RoundManifestCore` containing, in canonical field order:

1. protocol identifier;
2. Bitcoin Cash genesis block hash;
3. candidate-set digest;
4. control-roster digest;
5. role seed;
6. sorted roster of control public keys and roles;
7. conductor control public key;
8. ordered contributor control public keys;
9. opaque pool identifier;
10. component count;
11. fee rate in satoshis per byte;
12. minimum excess fee in satoshis;
13. maximum excess fee in satoshis;
14. blind-signing public key and contributor nonce allocation digest;
15. transport profile identifier;
16. canonical relay-set digest;
17. phase start time and phase deadlines;
18. draft transaction profile identifier.

`roundID = SHA256(domainManifest || canonical(RoundManifestCore))`.

Every candidate signs `roundID` with its one-time control key. A complete `RoundManifest` is the core plus signatures sorted by control public key. The attempt begins only after every conductor and contributor signature is valid.

The conductor cannot alter a roster, fee, deadline, relay set, blind-signing key, or transaction profile after manifest agreement. A conflicting manifest is equivocation and aborts the attempt.

## 13. Contribution And Blind Authorization

After manifest agreement, each contributor asks OpalBase for one round-scoped reservation lease and prepares exactly 23 components:

- each input component identifies one reserved UTXO and its amount in satoshis;
- each output component contains one fresh locking script and its amount in satoshis;
- each blank component has amount zero;
- input and output values incorporate the manifest fee rules using the CashFusion-derived Pedersen amount construction;
- every component uses fresh salts, nonces, communication keys, and blind-token material.

The contributor sends one grouped `PlayerCommit` to the conductor. The conductor learns which commitments belong to one contributor but does not learn which anonymous component submissions later correspond to that contributor.

The conductor MUST validate:

- exactly 23 unique commitments;
- valid curve points and blind requests;
- the Pedersen sum opening and declared excess fee;
- manifest fee bounds;
- no commitment duplicated within or across contributors.

The conductor returns blind-signature responses only after all valid contributor commitments are present. It then publishes one canonical shuffled commitment set. Every contributor verifies inclusion of its commitments and the expected total count.

The `Mosaic/0-opal.1` conformance profile fixes the authorization variant, request-slot ledger, duplicate-response cache, and replay-identifier derivation described in [`mosaic-v0-profile.md`](mosaic-v0-profile.md). Those deterministic contracts do not constitute a live or reviewed blind-signature implementation.

## 14. Anonymous Component Submission

Each contributor submits every input, output, and blank component through a separate covert mailbox authorization. The transport profile MUST provide:

- one-time mailbox keys;
- authenticated encryption;
- fixed ciphertext size for each message class;
- randomized submission time inside the manifest window;
- isolated anonymous network paths for unlinkable component submissions;
- replay detection and idempotent duplicate handling.

The conductor accepts a component only when its blind authorization, salt hash, type, size, and protocol constraints are valid. It cannot infer the contributor from the blind token or mailbox identity under the stated transport assumptions.

After the component window closes, the conductor publishes the canonical ordered component set. Every contributor verifies:

- inclusion of all its components;
- expected component count;
- no duplicate input outpoint;
- valid input and output forms for the transaction profile;
- transaction balance and fee bounds;
- absence of unauthorized token data;
- acceptable privacy shape under host policy.

Any failure before BCH signing aborts without a BCH signature.

## 15. Transcript Agreement And BCH Signing

Every participant independently constructs the same unsigned Bitcoin Cash transaction from the manifest and ordered component set.

The draft transcript root is:

```text
manifestHash       = SHA256(UTF8("Mosaic/1-draft.1/manifest") || canonical(RoundManifest))
commitmentSetHash  = SHA256(UTF8("Mosaic/1-draft.1/commitment-set") || canonical(CommitmentSet))
componentSetHash   = SHA256(UTF8("Mosaic/1-draft.1/component-set") || canonical(ComponentSet))
unsignedTxHash     = SHA256(UTF8("Mosaic/1-draft.1/unsigned-transaction") || unsignedBitcoinCashTransactionBytes)

TranscriptRoot = SHA256(
    UTF8("Mosaic/1-draft.1/transcript") ||
    manifestHash ||
    commitmentSetHash ||
    componentSetHash ||
    unsignedTxHash
)
```

Each contributor signs a `PreSignAcknowledgement(roundID, TranscriptRoot)` with its one-time control key. The conductor publishes the complete acknowledgement set. Every contributor MUST verify one valid acknowledgement from every contributor before asking OpalBase to sign.

OpalBase MUST independently validate the exact transaction, including reserved inputs, expected fresh outputs, amounts in satoshis, fee, script forms, token exclusion, and transaction shape. It signs only its own inputs using Schnorr with `SIGHASH_ALL | SIGHASH_FORKID`.

Transaction signatures are submitted through anonymous per-input mailboxes. The conductor verifies them and publishes a canonical complete signature set. Each contributor independently assembles and validates the complete signed transaction.

No partial acknowledgement set, conductor assertion, relay assertion, or timeout permits BCH signing.

## 16. Completion, Blame, And Retry

Any contributor MAY give the complete signed transaction to its host for broadcast. Broadcast remains host-owned and is not proof that the Mosaic protocol itself preserved privacy.

If an attempt fails, participants MAY exchange CashFusion-derived encrypted proof and blame material sufficient to identify malformed or missing components inside that attempt. Blame does not create a persistent identity or durable ban.

Mosaic does not restart in place. A later attempt MUST regenerate:

- discovery and control identities;
- role-selection randomness;
- wallet outputs and reservation lease;
- component salts and nonces;
- Pedersen commitments;
- blind requests and conductor blind-signing key;
- communication, proof, and mailbox keys;
- relay subscriptions and anonymous network paths;
- round identifier and transcript.

The retry MUST NOT publish a parent-attempt link. Local diagnostics may correlate attempts only through private, non-exported identifiers.

## 17. `nostr-tor/1-draft.1` Transport Requirements

The initial transport profile uses Nostr-compatible relays as replicated mailboxes and Tor as the required anonymous network path.

- At least three distinct `wss` relay endpoints MUST be committed by digest in the manifest.
- Senders MUST attempt publication to every relay and require acceptance from at least two.
- Receivers subscribe to every relay and merge valid signed messages by digest and sequence.
- Relay ordering or timestamps are not consensus inputs.
- One-time event keys MUST be used for each attempt, with additional one-time mailbox keys for anonymous submissions.
- Sensitive component and signature traffic MUST use isolated Tor circuits or a reviewed equivalent that satisfies the same unlinkability contract.
- A transport failure MUST abort or wait; it MUST NOT fall back to clearnet.
- NIP-44 encryption alone is insufficient because relays can observe IP addresses and message metadata. The profile requires an outer fixed-size envelope and anonymous transport.

The generic implementation includes a strict internal NIP-59 rumor, seal, and gift-wrap layer. The additive mainnet contract selects `nostr-tor/0-opal-mainnet-alpha.5`: kind-78 rumors, exact tags, fixed 8,192-byte padded content, regular kind-1059 delivery, bounded cover timestamps, signed-wrapper replay identity, exact allocation ceilings, and three relays with two accepted acknowledgements. Its control bridge owns zero-origin sender sequences and complete recipient batches; fan-in starts three globally distinct injected subscriptions per mailbox, serializes copies while preserving source order, ignores EOSE and NOTICE, and treats source loss as terminal. After authentication, the selected coordinator stages semantic admission and an injected attempt-bound admission journal durably appends accepted control digest/sequence or anonymous wrapper/mailbox facts before effects. Exact copies append once; rejected traffic remains unconsumed; append failure installs nothing. A separate outbound publication journal records the complete batch, permits, relay attempts, acknowledgements, and terminal outcome, reconciles uncertain appends through exact snapshot readback, and resumes unresolved publication without changing canonical bytes. These satisfy their bounded durable component requirements only when durable stores are supplied. The separately versioned accepted `nostr-tor/0-opal-mainnet-alpha-private-deployment.1` supplement fixes private-alpha discovery mappings, strict endpoint policy, reviewed relay capability flags, a 20-bit availability proof-of-work throttle, and timing policy without changing this draft or the alpha.5 post-manifest bytes. Those contracts do not supply complete execution: mailbox and key persistence, admission and coordinator restoration, inbound reconnect, application-owned relay provisioning, and concrete Tor-only sessions remain absent from the generic implementation, so a nonempty admission journal cannot resume a runtime and instead fails closed.

The control-batch publisher supplies the bounded roster-wide handoff omitted from the bridge callback: it requires the exact batch context and recipient mapping, journals one complete batch before route exposure, records relay attempts and acknowledgements before their effects, restores terminal acknowledgement outcomes before requesting routes, rejects batch-global connection reuse, cancels sibling publications on failure, and drains every delegated publisher. The caller still supplies the durable journal backend and authoritative endpoint-to-capability-bound Tor routes; admission, coordinator, inbound, material, and application recovery policy remain external.

The anonymous-batch publisher supplies the equivalent bounded handoff for one bridge-minted component or local-signature batch. It atomically journals the complete recipient set, preflights every recipient route group before exposing a wrap, then requires a caller-owned per-recipient publication permit and records the grant before relay delegation. A restored journal reuses only recorded permits and requests a permit for a prepared-but-unpermitted recipient. The provider must supply the durable backend, fresh anonymous route capabilities, timing policy, reconnect and retry scheduling, and supervision; neither the journal nor the publisher's in-process object checks establish Tor-circuit independence or durable relay delivery.

## 18. Release Gates For `Mosaic/1`

Before removing `draft` from the protocol identifier, all of the following are REQUIRED:

- complete field-numbered wire schema;
- complete CashFusion-derived amount-commitment, blind-authorization, fee-allocation, and blame algorithms with no implementation-defined steps;
- frozen domain separators, enum values, and transaction marker decision;
- registered or otherwise collision-reviewed on-chain protocol identifier when an identifier is retained;
- fixed transport event kinds and ciphertext sizes;
- fixed proof-of-work and timing parameters supported by device and Tor measurements;
- positive and negative golden vectors for every canonical digest and message type;
- deterministic multi-peer simulator with conductor equivocation, relay partition, replay, reorder, duplicate, omission, timeout, blame, and retry cases;
- OpalBase reservation lease, validation, signing, release, and commit integration;
- mainnet-disabled end-to-end test profile;
- reviewed privacy claim language;
- independent cryptographic and protocol security review;
- explicit resolution of every open item in this document and the security model.

## 19. References

- [CashFusion protocol specification](https://github.com/cashshuffle/spec/blob/master/CASHFUSION.md)
- [CashFusion security audit](https://electroncash.org/fusionaudit.pdf)
- [NIP-01 basic relay and event protocol](https://github.com/nostr-protocol/nips/blob/master/01.md)
- [NIP-44 encrypted payloads and limitations](https://github.com/nostr-protocol/nips/blob/master/44.md)
- [NIP-59 gift wrapping](https://github.com/nostr-protocol/nips/blob/master/59.md)
- [NIP-78 application data](https://github.com/nostr-protocol/nips/blob/master/78.md)
- [00 Protocol BCH Stealth Protocol](https://github.com/00-Protocol/BCH-Stealth-Protocol)
- [CoinShuffle++ / DiceMix](https://eprint.iacr.org/2016/824.pdf)
