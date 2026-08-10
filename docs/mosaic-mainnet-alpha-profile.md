# Mosaic Mainnet-Alpha Profile

Status: Frozen deterministic contract profile. Profile identifier: `Mosaic/0-opal-mainnet-alpha.4`. Transport identifier: `nostr-tor/0-opal-mainnet-alpha.4`. Transaction profile identifier: `bch-mainnet-p2pkh-schnorr/0-opal-mainnet-alpha.4`.

This profile freezes an additive mainnet-targeted canonical contract without enabling a runnable Mosaic session, a live transport, wallet execution, broadcast, or a production-support claim. An internal local-material builder derives exactly 23 component slots from one validated reservation lease, constructs and locally opens the grouped commitments, and binds two purpose-separated blind authorizations to every slot. The admission ledger seals admitted documents to one attempt, generation, material identifier, and round-scoped per-sender sequence epoch; a local conductor additionally admits component mailbox sequence zero and BCH-signature mailbox sequence one under distinct attempt keys, then emits a canonical input-indexed signature set only after every transaction input is present. A paired internal runtime session still stops at transcript agreement, and the executable runtime driver still rejects this profile. A narrow reservation coordinator and signing-request builder retain their existing validated-input boundaries without invoking BCH signing. Production lease provenance, material persistence and erasure, mailbox transport, previous-output-backed signature validation in executable composition, complete-transaction disposition, recovery, Tor, and broadcast remain gated in Section 12. No test or package default may spend or broadcast mainnet funds.

## 1. Compatibility And Versioning

`Mosaic/0-opal-mainnet-alpha.4` is distinct from the chipnet-only [`Mosaic/0-opal.1`](mosaic-v0-profile.md) conformance profile and from `Mosaic/1-draft.1`. It supersedes alpha.3 by freezing the component salt formulas, contributor-local material construction and opening checks, two independently keyed authorization purposes, component-bound authorization inputs, component-to-signature spent-identifier binding, and the paired component/signature mailbox sequence. It retains alpha.3's deterministic ten-satoshi overhead allocation, aggregate kinds 3 and 5, and post-admission control-sequence epoch. Implementations MUST reject every alpha.3 identifier and cross-profile byte; no alpha.3 attempt material may resume under alpha.4. Adding this profile MUST NOT change any `Mosaic/0-opal.1` default, domain, canonical byte, tag, event kind, digest, or golden vector.

Any change to a field, field order, width, enum value, domain separator, transaction rule, or signature-authorization rule defined here requires a new profile identifier. Unresolved transport and cryptographic contracts listed in Section 12 are not implicitly defined by this identifier.

Alpha.4 retains the public Mosaic reservation and signing request field `requiredExcessFeeSatoshis` introduced by alpha.3, because a minimum/maximum range cannot identify one contributor's roster-derived share. The source-compatible legacy initializers remain available only for singleton ranges and fail closed for an ambiguous range; host integrations that used a range MUST pass the exact required value explicitly.

## 2. Fixed Parameters

| Parameter | Value |
|---|---|
| Bitcoin Cash network | Mainnet |
| Mainnet genesis hash, display order | `000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f` |
| Candidates | 7–9 |
| Conductors | Exactly 1 |
| Contributors | 6–8 |
| Components per contributor | 23 |
| Fee rate | Exactly 1 satoshi per estimated final signed byte |
| Minimum contributor excess fee | 1 satoshi |
| Maximum contributor excess fee | 2 satoshis |
| Fixed transaction overhead | 10 bytes and therefore 10 satoshis |
| BCH transaction version | 2 |
| BCH lock time | 0 |
| BCH input sequence | `0xffffffff` |
| BCH input signature | Schnorr with sighash byte `0x41` (`SIGHASH_ALL | SIGHASH_FORKID`) |
| Supported locking form | Standard P2PKH only |

The conductor MUST NOT contribute an input, output, blank allocation, BCH signature, or wallet reservation. Profile selection is explicit; `.opalMainnetAlpha` is never a package default and does not grant broadcast permission.

## 3. Canonical Primitives

This profile uses the Section 8 primitives from [`mosaic-protocol-specification.md`](mosaic-protocol-specification.md): big-endian `u8`, `u16`, `u32`, and `u64`; `u32(length) || value` byte strings and printable-ASCII text; `u32(count)` vectors; fixed-width hashes and keys without a length prefix; and strictly ascending canonical sets. Decoders reject unknown enum values, duplicates, descending members, invalid lengths, malformed cryptographic encodings, and trailing bytes.

Role values are `0 = conductor` and `1 = contributor`. Phase values are the reducer order `0...9`: discovery, candidate-set agreement, control-roster agreement, role selection, manifest agreement, wallet reservation, grouped commitment, anonymous component submission, transcript agreement, and BCH signing.

## 4. Domains And Role Election

Every profile domain is exact UTF-8 `"Mosaic/0-opal-mainnet-alpha.4/" || suffix` with no terminating zero. The role documents are:

```text
roleCommitment = SHA256(domain("role-commitment") || controlRosterDigest32 || controlKey32 || randomness32)
roleSeed = SHA256(domain("role-seed") || controlRosterDigest32 || canonical(vector(controlKey32 || randomness32)))
```

The vector is sorted by control key, covers the complete 7–9-member control roster exactly once, and uses a `u32` count. The conductor index is the first eight role-seed bytes interpreted as an unsigned big-endian integer modulo candidate count. A failed election is terminal for that attempt; retry uses a new attempt and fresh material.

## 5. Complete Manifest

`RoundManifestCore` has this exact field order:

1. protocol identifier as canonical text;
2. mainnet genesis hash as 32 fixed bytes;
3. candidate-set digest as 32 fixed bytes;
4. control-roster digest as 32 fixed bytes;
5. role seed as 32 fixed bytes;
6. vector of `controlKey32 || role u8`, sorted by control key;
7. conductor control key as 32 fixed bytes;
8. contributor control-key vector sorted by key;
9. opaque pool identifier as 32 fixed bytes;
10. component count as `u8`, exactly 23;
11. fee rate, minimum excess, and maximum excess as three `u64` values, exactly `1, 1, 2`;
12. component-authorization RFC 9578 RSA-PSS SubjectPublicKeyInfo as canonical bytes, selecting the existing RSA-2048 authorization profile;
13. BCH-signature-authorization RFC 9578 RSA-PSS SubjectPublicKeyInfo under a distinct key identifier;
14. contributor-nonce-allocation digest as 32 fixed bytes;
15. transport profile identifier as canonical text;
16. relay-set digest as 32 fixed bytes;
17. phase start and the wallet-reservation, grouped-commitment, anonymous-component, transcript-agreement, and BCH-signing deadlines as six strictly increasing `u64` Unix-second values;
18. transaction profile identifier as canonical text.

The nonce-allocation and relay-set fields are opaque validated digests until their source documents are frozen. This profile freezes their placement and width, not their unresolved derivation. It also freezes deadline representation and ordering, not concrete timing values.

`roundIdentifier = SHA256(domain("manifest") || canonical(RoundManifestCore))`.

`RoundManifest` appends a vector of `controlKey32 || BIP340Signature64`, sorted by control key, with exactly one valid signature over `roundIdentifier` from every roster member. Before signing or accepting a proposal, a peer MUST compare the candidate-set digest, pool identifier, control roster, roles, and role seed with its locally established pre-manifest context.

`manifestDigest = SHA256(domain("complete-manifest") || canonical(RoundManifest))`.

## 6. PlayerCommit

One contributor's `PlayerCommit` is:

```text
roundIdentifier32 || contributorControlKey32 || canonical(GroupedCommitmentPayload) || vector(ComponentAuthorizationRequestPayload) || vector(BCHSignatureAuthorizationRequestPayload)
```

It contains exactly 23 grouped commitments, 23 component-authorization requests, and 23 BCH-signature-authorization requests. Both request vectors use ascending slots `0...22`, and slot `i` in both vectors corresponds to grouped commitment `i`. The two vectors are not interchangeable. Its digest is `SHA256(domain("player-commit") || canonical(PlayerCommit))`.

For every slot, the contributor generates fresh independent 32-byte salt, Pedersen nonce, component communication private key, component-authorization nonce, BCH-signature-authorization nonce, and recipient mailbox event identity. Within one material value, no raw 32-byte secret, communication x-only identity, or recipient identity may repeat across slots or fields. A production material owner MUST additionally prevent reuse across attempts, generations, rounds, purposes, retries, or profile versions and erase private material after terminal disposition.

Across every grouped commitment and the complete commitment set, communication public keys MUST have distinct 32-byte x-only event identities; opposite SEC1 parities of one x-coordinate are duplicates. Neither parity of any published grouped-commitment identity may later authenticate an anonymous component or BCH-signature envelope in the same attempt.

The alpha.4 component hashes are exact:

```text
saltCommitment32 = SHA256(domain("component-salt") || roundIdentifier32 || salt32)
saltedComponentDigest32 = SHA256(domain("salted-component") || roundIdentifier32 || salt32 || canonical(componentPayload))
componentBinding32 = SHA256(domain("component-authorization/payload") || canonical(component))
```

`canonical(componentPayload)` is the existing input, output, or blank payload encoding and excludes the salt commitment, authorization token, mailbox, contributor identity, and private opening. `canonical(component)` includes the salt commitment and payload. The grouped commitment carries the salted component digest, Pedersen amount commitment, and compressed communication public key. The anonymous component carries the component authorization token and exact component.

Authorization purpose values are exactly `0 = component` and `1 = BCH signature`. An authorization input is domain-separated and binds mainnet genesis, round identifier, one manifest RSA key identifier, purpose, fresh nonce, and a 32-byte binding. Its spent identifier is `SHA256(domain("authorization-spent") || canonical(input))`. The component input binds `componentBinding32`. The corresponding BCH-signature input binds the component input's spent identifier. Each purpose uses its own manifest RSA key and each token encodes `roundIdentifier32 || keyIdentifier32 || purpose u8 || nonce32 || binding32 || messageRandomizer32 || signature256`, exactly 417 bytes.

A standard P2PKH input contributes `amount - 141` satoshis, a standard P2PKH output contributes `-(amount + 34)` satoshis, and a blank contributes zero. The 141-byte input and 34-byte output charges cover every component-derived byte. The remaining transaction fields are the four-byte version, one-byte input count, one-byte output count, and four-byte lock time. Counts remain one byte because this profile permits at most 184 nonblank components, so the fixed overhead is exactly ten bytes and ten satoshis.

Let `n` be the 6–8 contributor count, order contributors lexicographically by their 32-byte one-time control identity, let `base = 10 / n`, and let `remainder = 10 % n` using unsigned integer division. Contributors at indices below `remainder` MUST declare `base + 1` excess satoshis and the rest MUST declare `base`. The resulting vectors are `[2,2,2,2,1,1]`, `[2,2,2,1,1,1,1]`, and `[2,2,1,1,1,1,1,1]`; every vector totals exactly ten. A conductor has no share. A PlayerCommit whose declared excess differs from its roster-derived share is invalid.

For each PlayerCommit, the sum of all 23 Pedersen commitment points MUST equal a commitment to the exact roster-derived excess using the published total nonce and OpalCrypto's canonical Pedersen setup. This group equation proves the declared aggregate balance but does not prove that any disclosed component opens a particular member commitment.

A control envelope may admit a PlayerCommit reservation only during wallet reservation and only from the same contributor control key encoded by the document. Structural admission alone does not authorize phase advancement. The implemented semantic validation additionally binds the exact manifest round, contributor role, roster-derived excess share, and grouped Pedersen equation. The local material builder accepts one contributor lease only, validates every selected input as compressed-key standard P2PKH, rejects more than 23 nonblank components without truncation, appends blanks to exactly 23, computes every salt and Pedersen opening, constructs both request vectors, and rejects any local count, key/script, duplicate material, or balance mismatch before it can mint reservation-publication or transcript-inclusion validations. It does not prove to the conductor that an anonymously disclosed component is a member of a contributor-tagged group; alpha.4 explicitly accepts that off-commitment accountability limitation rather than revealing salts, openings, group indices, or contributor identity during the happy path. Contributor nonce-allocation derivation and production stateful material ownership remain deferred.

## 7. Aggregate Reservation And Fragmentation

An aggregate reservation is `aggregateKind u8 || aggregateDigest32 || canonicalByteCount u32 || fragmentCount u8`. Implemented kinds are `0 commitmentSet`, `1 componentSet`, `2 playerCommit`, `3 authorizationResponseSet`, `4 completeManifest`, `5 preSignAcknowledgementSet`, `6 bchSignatureSet`, and `7 completeTransaction`.

One contributor's kind-3 authorization response set is `roundIdentifier32 || contributorControlKey32 || playerCommitDigest32 || vector(component slot u8 || blindSignature256) || vector(BCH-signature slot u8 || blindSignature256)`. Each vector contains exactly 23 responses in slots `0...22`, the complete set is exactly 11,926 bytes, reserves exactly four fragments with body lengths `3,799, 3,799, 3,799, 529`, and has digest `SHA256(domain("authorization-response-set") || canonical(set))`. The conductor constructs a set only after both attempt-wide issuance ledgers reach their issued state and only when each ledger's stored blinded requests exactly match the corresponding purpose-specific PlayerCommit vector. Every roster peer consumes the same complete conductor response-set stream so the sender-global sequence remains continuous; non-target contributors record each structurally valid set without using its responses. The addressed contributor additionally requires the exact retained PlayerCommit digest, binds each request to its purpose-specific manifest key, component bytes, and component spent identifier, finalizes all 46 blind signatures against the corresponding private blind-request states, and rejects repeated authorization spent identifiers. The material-bound validation delivered to the ledger also carries the exact attempt, generation, and material identifier and cannot be relabeled by its caller. Wallet-reservation phase advancement requires every contributor's response set to have been consumed and the local contributor's set to have been finalized. Structural admission alone does not mint usable tokens.

The kind-5 complete pre-sign acknowledgement set is `roundIdentifier32 || transcriptRoot32 || vector(contributorControlKey32 || BIP340Signature64)`. Its contributor entries are strictly ascending by control key and cover the complete 6–8-contributor roster exactly once, excluding the conductor. It is 644, 740, or 836 bytes for 6, 7, or 8 contributors and has digest `SHA256(domain("pre-sign-acknowledgement-set") || canonical(set))`. Each inner signature independently verifies the existing pre-sign acknowledgement document for the common round and transcript root. A conductor admits its publication only when it is semantically identical to the locally collected individual submissions; contributors validate the complete portable set directly.

The reservation sequence is followed immediately by exactly `fragmentCount` control sequences. A fragment payload is `reservationSequence u64 || fragmentIndex u8 || body bytes`; indices start at zero, have no gaps, and use a 3,799-byte maximum body derived from the frozen 4,092-byte control-envelope limit. Exact duplicates are idempotent. Gaps, interleaving, conflicting bytes, wrong sequence, overflow, digest mismatch, impossible kind-specific lengths, malformed canonical reassembly, and input after terminal completion are rejected.

Successful reassembly MUST run the strict decoder for the declared kind and return a typed document. A matching digest over arbitrary bytes is insufficient.

## 8. Authenticated Control Documents

The canonical control-envelope body is: protocol text, genesis hash32, round identifier32, phase `u8`, sender control key32, sender event key32, sequence `u64`, payload type `u16`, payload digest32, and expiry `u64`. The payload digest is `SHA256(domain("payload") || payloadType u16 || bytes(payload))`. The message digest is `SHA256(domain("message") || canonical(body))`. The envelope appends a 64-byte BIP340 control signature and canonical payload bytes.

The control key and event key MUST be distinct and valid. Control admission requires the already-authenticated outer event identity and rejects it unless it equals the signed event-key field. The admitted payload MUST be unexpired at the caller-supplied current Unix second and match the envelope round, current reducer phase, roster membership, publisher role, and any active aggregate reservation. The round identifier defines the post-admission sequence epoch: every roster control identity's first envelope for that round has sequence zero, each sender advances independently across phase changes, and a retry's fresh round identifier starts a fresh zero epoch. Aggregate reservations, every fragment, and individual acknowledgements each consume one sequence. Every roster peer consumes the same conductor aggregate stream, including response sets addressed to other contributors; transport filtering MUST NOT create per-recipient gaps in that sender-global stream. Pre-manifest traffic is outside this epoch and does not consume these counters. The ledger permits at most one fragment run per sender and treats gaps, conflicts, overflow, rollback, skipping, in-place retry, and nonduplicate input after termination as fail-closed outcomes. This document does not assign Nostr event kinds, tags, relay endpoints, padding, or pre-manifest sequencing.

An individual pre-sign submission contains `roundIdentifier32 || transcriptRoot32 || BIP340Signature64`. The inner signature is verified with the contributor control key over the existing `profile + "/pre-sign-ack"` acknowledgement digest. The surrounding control-envelope signature authenticates delivery metadata separately and MUST NOT be substituted for the inner acknowledgement signature.

## 9. Anonymous Component And Signature Boundary

The anonymous envelope freezes protocol, network, round, phase, compressed communication key, recipient event key, per-mailbox sequence, payload type, payload digest, expiry, and payload fields. Admission requires the authenticated outer sender identity and receiving mailbox identity, binds both to the envelope, and rejects an expiry earlier than the caller-supplied current Unix second. An anonymous component uses mailbox sequence zero and contains the exact round, one purpose-zero authorization token, and one canonical component. Admission verifies the token against the manifest component-authorization key and `componentBinding32`, then records its spent identifier, sender x-only identity, and recipient identity exactly once. The communication key's authenticated x-only identity and the recipient mailbox identity are one-time across accepted deliveries; opposite-parity compressed keys with the same x-coordinate are the same sender identity. The published grouped-commitment communication key MUST NOT be reused directly as the anonymous envelope identity because direct equality would reveal the contributor-to-component linkage to the conductor.

An anonymous BCH-signature submission uses sequence one on the same recipient mailbox that admitted the corresponding input component. Its purpose-one token must use the manifest BCH-signature authorization key and bind the accepted component token's spent identifier; its transcript root must equal the acknowledged transcript. Admission additionally requires a different one-time authenticated sender x-only identity, an input component, an unused authorization spent identifier, and an unused input index, then invokes an injected previous-output-backed semantic validator. Exact duplicates are recognized before phase and expiry checks. A rejected semantic validation consumes no mailbox, sender, token, or input-index state. Only a local conductor collects these anonymous deliveries, and it emits a canonical set only after every transaction input index is present. This standalone ledger path does not enter the paired runtime session, invoke a wallet host, or grant signing, commit, or broadcast authority.

Alpha.4 intentionally does not claim that an authorized component opens a member of a contributor-tagged grouped commitment. The valid off-commitment vector pinned by the tests documents that accountability limitation. Adding a privacy-preserving happy-path membership proof would require a new profile.

## 10. BCH Signature Set And Complete Transaction

One BCH signature entry is `inputIndex u32 || schnorrSignature64 || compressedPublicKey33`. A complete set is `roundIdentifier32 || transcriptRoot32 || vector(entry)`, with entries already in exact ascending indices `0...(inputCount - 1)`. Its digest is `SHA256(domain("bch-signature-set") || canonical(set))`. A decoder MUST reject descending, duplicate, missing, or out-of-range indices rather than sorting received bytes.

One anonymous BCH-signature submission is `transcriptRoot32 || authorizationToken417 || inputIndex u32 || schnorrSignature64 || compressedPublicKey33`, exactly 550 bytes. Its digest is `SHA256(domain("bch-signature") || canonical(submission))`. The authorization token is retained and validated during admission; construction of a signature set discards only the already-spent authorization evidence after the ledger has enforced one-time token, mailbox, sender, and input-index rules.

Complete assembly independently checks every ordered previous outpoint, component-committed amount, resolved previous-output amount, standard P2PKH locking script, compressed public key, and Schnorr signature against the exact acknowledged unsigned transaction and sighash byte `0x41`. Inputs and outputs together cannot exceed the 184 nonblank component slots. Each unlocking script is exactly `0x41 || signature64 || 0x41 || 0x21 || publicKey33`, totaling 100 bytes. The complete payload is `roundIdentifier32 || transcriptRoot32 || bytes(completeTransaction)` with digest `SHA256(domain("complete-transaction") || canonical(payload))`. Publication validation requires the expected transcript and rejects a signed transaction whose unlocking-script-stripped body differs from it; exact previous-output and signature validation remains the assembler and host responsibility.

OpalBase remains authoritative. It MUST independently fetch or validate every previous output, verify every script and signature, compare the exact transcript-bound transaction body, enforce fee and network policy, persist the exact transaction, and commit only the matching reservation. OpalFusion assembly never grants broadcast permission.

The public `MosaicPreviousOutputSource` contract accepts an ordered vector of transcript-committed outpoints and expected amounts and returns ordered source-asserted output data, including the locking script and token-presence state. The internal mainnet-alpha resolver derives that request vector from the exact transcript, binds exact outpoints and amounts, and rejects reported token presence. This boundary neither proves that the locking script or token state came from authoritative transaction bytes nor authorizes signing, commit, or broadcast; a production OpalBase adapter must establish those facts and the wallet host must revalidate every resolved previous output at signing time.

The internal signing-request builder accepts only a resolver-minted validation for the exact transcript. It additionally requires the complete sealed reservation lease and PlayerCommit publication, contributor-local transcript-inclusion validation for the same attempt, generation, and material, and a roster-complete acknowledgement set for the same round and transcript root. It maps each reserved local outpoint to the canonical transcript index, requires exact amount and locking-script equality, validates compressed secp256k1 public keys against standard P2PKH scripts, matches local outputs as a multiset, and supplies the roster-derived excess-fee share to the public host request. Constructing that request is not BCH-signing eligibility, a host invocation, a previous-output authority claim, commit permission, or broadcast permission.

## 11. Implemented Evidence Boundary

Deterministic tests pin the profile selectors and alpha.3 rejection; 138-, 161-, and 184-component capacity; canonical 6–8-contributor overhead allocation; exact component and final-fee arithmetic; salt commitment, salted-component, component-binding, purpose-one authorization-input, spent-identifier, 417-byte token, 550-byte signature-submission, PlayerCommit, dual-vector response-set, acknowledgement-set, manifest, transcript, signature-set, and complete-transaction golden vectors; grouped Pedersen openings and sums; exact 23-slot construction including zero blanks and 24-member rejection without truncation; and one structurally valid, globally balanced authorized component whose salted digest is absent from the commitment set. The admission ledger additionally proves roster-derived zero sequence epochs, attempt/generation/material routing, one roster-wide conductor response stream, 6–8-contributor PlayerCommit and response-set barriers, material-bound local finalization, conductor-only component sequence-zero and signature sequence-one intake, exact-duplicate precedence, non-consuming semantic rejection, one-time sender x-only identities, mailbox identities, tokens, and input indices, shuffled complete-set determinism, transcript-root agreement, portable contributor acknowledgements, phase ordering, terminal absorption, and in-place retry rejection. The paired runtime session still proves translation only through transcript agreement and does not consume the standalone signature set. The signing-request builder and complete-transaction assembler separately prove resolver-bound previous outputs, local P2PKH request construction, Schnorr validation, and byte-exact transaction assembly without enabling the mainnet runtime or broadcast. Negative tests cover cross-profile and foreign-round bytes, wrong publisher or phase, malformed aggregates, sequence conflict, wrong excess share or Pedersen balance, request/component/signature binding substitution, wrong purpose or RSA key, opposite-parity sender reuse, recipient reuse, semantic validator failure, incomplete or extra signatures, acknowledgement mismatch, local commitment substitution, previous-output substitution, and invalid BCH signatures.

The profile-scoped reservation coordinator proves exact host-lease/reference matching, rejection of direct validation injection, one reservation and publication claim, late-lease release, publication-before-release ordering, every frozen request field plus an exact caller-owned expiration, conductor rejection, and recovery-required release failure. It does not select the still-unfrozen manifest-deadline-to-lease-expiry mapping, construct a PlayerCommit, or prove that the lease material produced one. The internal runtime driver still rejects `.opalMainnetAlpha`, and legacy identity-array host markers terminate a mainnet-alpha runtime session. These are release guards, not missing test coverage.

## 12. Remaining Release Gates

The following are intentionally unresolved or external and MUST remain fail closed:

- canonical availability beacon, candidate-set, admission, pool, relay-set, contributor-nonce-allocation, and discovery documents;
- proof-of-work minimums, discovery and pre-manifest timing values, concrete post-manifest deadline values, Nostr event kinds and tags, relay URL normalization, endpoint provisioning, reconnect behavior, and pre-manifest sequencing;
- a concrete Tor WebSocket implementation with reviewed circuit isolation and no clearnet fallback;
- a production stateful attempt-material owner that proves one live reservation lease produced the sealed PlayerCommit, prevents reuse across attempts and retries, persists only the minimum recoverable state, erases salts, nonces, communication keys, blind-request state, and mailbox identities after terminal disposition, and supplies the already-frozen local builder with fresh material;
- a privacy-preserving proof relating each authorized anonymous component to one grouped commitment if the accepted off-commitment accountability tradeoff is later changed; adding such a proof requires a new profile identifier;
- production mailbox ingress that authenticates the per-component sequence-zero and sequence-one route, delivers standalone ledger facts into the paired runtime session, and preserves terminal and cancellation ordering without exposing contributor identities;
- an authoritative previous-output-backed BCH-signature semantic validator wired into executable composition, RuntimeSession consumption of the complete signature set, exact host finalization and complete-transaction commit, durable encrypted attempt journal loading, and crash-recovery execution;
- full OpalCrypto capacity evidence for 368 blind evaluations under the two distinct purpose keys, followed by independent cryptographic, side-channel, privacy, wallet-policy, and deployment review;
- app-owned mainnet transaction-reader selection, explicit broadcast permission, and recovery-aware broadcast execution; no test may call a live reader or broadcaster.

Until every relevant gate is complete, safe wording is limited to “deterministic mainnet-alpha contract foundation.” It is not a live Mosaic engine, a mainnet-ready wallet feature, an anonymity claim, or permission to use real funds.

The [Alpha.4 Design Record](mosaic-mainnet-alpha4-design-proposal.md) retains the rationale and rejected alternatives for the salt, local material, component-bound purpose-separated authorization, mailbox, and honest-wallet safety-boundary decisions accepted by this normative profile. This document and the implemented golden vectors are authoritative; the design record is not a second source of protocol truth.
