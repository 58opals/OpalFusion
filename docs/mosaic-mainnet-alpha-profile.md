# Mosaic Mainnet-Alpha Profile

Status: Frozen deterministic contract profile. Profile identifier: `Mosaic/0-opal-mainnet-alpha.2`. Transport identifier: `nostr-tor/0-opal-mainnet-alpha.2`. Transaction profile identifier: `bch-mainnet-p2pkh-schnorr/0-opal-mainnet-alpha.2`.

This profile freezes an additive mainnet-targeted canonical contract without enabling a runnable Mosaic session, a live transport, wallet execution, broadcast, or a production-support claim. An internal admission-only ledger seals admitted documents through transcript agreement to one attempt, generation, and round-scoped per-sender sequence epoch, but it has no conversion to runtime inputs, does not authorize phase transitions, and refuses BCH-signing or complete-transaction admission. The post-admission runtime driver deliberately rejects this profile until commitment linkage, previous-output authority, anonymous BCH-signature authorization, the runtime bridge, effect execution, recovery, and transport gates in Section 12 are complete. No test or package default may spend or broadcast mainnet funds.

## 1. Compatibility And Versioning

`Mosaic/0-opal-mainnet-alpha.2` is distinct from the chipnet-only [`Mosaic/0-opal.1`](mosaic-v0-profile.md) conformance profile and from `Mosaic/1-draft.1`. It supersedes the contract-only `Mosaic/0-opal-mainnet-alpha.1` identifier because alpha.2 assigns aggregate kinds 3 and 5 and freezes the post-admission control-sequence epoch. Implementations MUST reject cross-profile bytes. Adding this profile MUST NOT change any `Mosaic/0-opal.1` default, domain, canonical byte, tag, event kind, digest, or golden vector.

Any change to a field, field order, width, enum value, domain separator, transaction rule, or signature-authorization rule defined here requires a new profile identifier. Unresolved transport and cryptographic contracts listed in Section 12 are not implicitly defined by this identifier.

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
| Minimum excess fee | 0 satoshis |
| Maximum excess fee | 0 satoshis |
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

Every profile domain is exact UTF-8 `"Mosaic/0-opal-mainnet-alpha.2/" || suffix` with no terminating zero. The role documents are:

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
11. fee rate, minimum excess, and maximum excess as three `u64` values, exactly `1, 0, 0`;
12. validated RFC 9578 RSA-PSS SubjectPublicKeyInfo as canonical bytes, selecting the existing RSA-2048 authorization profile;
13. contributor-nonce-allocation digest as 32 fixed bytes;
14. transport profile identifier as canonical text;
15. relay-set digest as 32 fixed bytes;
16. phase start and the wallet-reservation, grouped-commitment, anonymous-component, transcript-agreement, and BCH-signing deadlines as six strictly increasing `u64` Unix-second values;
17. transaction profile identifier as canonical text.

The nonce-allocation and relay-set fields are opaque validated digests until their source documents are frozen. This profile freezes their placement and width, not their unresolved derivation. It also freezes deadline representation and ordering, not concrete timing values.

`roundIdentifier = SHA256(domain("manifest") || canonical(RoundManifestCore))`.

`RoundManifest` appends a vector of `controlKey32 || BIP340Signature64`, sorted by control key, with exactly one valid signature over `roundIdentifier` from every roster member. Before signing or accepting a proposal, a peer MUST compare the candidate-set digest, pool identifier, control roster, roles, and role seed with its locally established pre-manifest context.

`manifestDigest = SHA256(domain("complete-manifest") || canonical(RoundManifest))`.

## 6. PlayerCommit

One contributor's `PlayerCommit` is:

```text
roundIdentifier32 || contributorControlKey32 || canonical(GroupedCommitmentPayload) || vector(AuthorizationRequestPayload)
```

It contains exactly 23 grouped commitments and exactly 23 authorization requests. Request slots are the ascending values `0...22`, and slot `i` corresponds to grouped commitment `i`. Its digest is `SHA256(domain("player-commit") || canonical(PlayerCommit))`.

A control envelope may admit a PlayerCommit reservation only during wallet reservation and only from the same contributor control key encoded by the document. This syntactic and identity binding does not replace the still-deferred Pedersen, commitment-opening, lease-to-material, or per-component fee validation.

## 7. Aggregate Reservation And Fragmentation

An aggregate reservation is `aggregateKind u8 || aggregateDigest32 || canonicalByteCount u32 || fragmentCount u8`. Implemented kinds are `0 commitmentSet`, `1 componentSet`, `2 playerCommit`, `3 authorizationResponseSet`, `4 completeManifest`, `5 preSignAcknowledgementSet`, `6 bchSignatureSet`, and `7 completeTransaction`.

One contributor's kind-3 authorization response set is `roundIdentifier32 || contributorControlKey32 || playerCommitDigest32 || vector(slot u8 || blindSignature256)`. It contains exactly 23 responses in slots `0...22`, is exactly 6,011 bytes, and has digest `SHA256(domain("authorization-response-set") || canonical(set))`. The conductor constructs a set only after the attempt-wide issuance ledger reaches its issued state and only when the ledger's stored blinded requests exactly match that PlayerCommit's slot-addressed request vector. Every roster peer consumes the same complete conductor response-set stream so the sender-global sequence remains continuous; non-target contributors record each structurally valid set without using its responses. The addressed contributor additionally requires the exact retained PlayerCommit digest, binds every request to the manifest's blind-signing key identifier, finalizes all 23 blind signatures against the corresponding private blind-request states, and rejects any repeated authorization spent identifier. Wallet-reservation phase advancement requires every contributor's response set to have been consumed and the local contributor's set to have been finalized. Structural admission alone does not mint usable tokens.

The kind-5 complete pre-sign acknowledgement set is `roundIdentifier32 || transcriptRoot32 || vector(contributorControlKey32 || BIP340Signature64)`. Its contributor entries are strictly ascending by control key and cover the complete 6–8-contributor roster exactly once, excluding the conductor. It is 644, 740, or 836 bytes for 6, 7, or 8 contributors and has digest `SHA256(domain("pre-sign-acknowledgement-set") || canonical(set))`. Each inner signature independently verifies the existing pre-sign acknowledgement document for the common round and transcript root. A conductor admits its publication only when it is semantically identical to the locally collected individual submissions; contributors validate the complete portable set directly.

The reservation sequence is followed immediately by exactly `fragmentCount` control sequences. A fragment payload is `reservationSequence u64 || fragmentIndex u8 || body bytes`; indices start at zero, have no gaps, and use a 3,799-byte maximum body derived from the frozen 4,092-byte control-envelope limit. Exact duplicates are idempotent. Gaps, interleaving, conflicting bytes, wrong sequence, overflow, digest mismatch, impossible kind-specific lengths, malformed canonical reassembly, and input after terminal completion are rejected.

Successful reassembly MUST run the strict decoder for the declared kind and return a typed document. A matching digest over arbitrary bytes is insufficient.

## 8. Authenticated Control Documents

The canonical control-envelope body is: protocol text, genesis hash32, round identifier32, phase `u8`, sender control key32, sender event key32, sequence `u64`, payload type `u16`, payload digest32, and expiry `u64`. The payload digest is `SHA256(domain("payload") || payloadType u16 || bytes(payload))`. The message digest is `SHA256(domain("message") || canonical(body))`. The envelope appends a 64-byte BIP340 control signature and canonical payload bytes.

The control key and event key MUST be distinct and valid. Control admission requires the already-authenticated outer event identity and rejects it unless it equals the signed event-key field. The admitted payload MUST be unexpired at the caller-supplied current Unix second and match the envelope round, current reducer phase, roster membership, publisher role, and any active aggregate reservation. The round identifier defines the post-admission sequence epoch: every roster control identity's first envelope for that round has sequence zero, each sender advances independently across phase changes, and a retry's fresh round identifier starts a fresh zero epoch. Aggregate reservations, every fragment, and individual acknowledgements each consume one sequence. Every roster peer consumes the same conductor aggregate stream, including response sets addressed to other contributors; transport filtering MUST NOT create per-recipient gaps in that sender-global stream. Pre-manifest traffic is outside this epoch and does not consume these counters. The ledger permits at most one fragment run per sender and treats gaps, conflicts, overflow, rollback, skipping, in-place retry, and nonduplicate input after termination as fail-closed outcomes. This document does not assign Nostr event kinds, tags, relay endpoints, padding, or pre-manifest sequencing.

An individual pre-sign submission contains `roundIdentifier32 || transcriptRoot32 || BIP340Signature64`. The inner signature is verified with the contributor control key over the existing `profile + "/pre-sign-ack"` acknowledgement digest. The surrounding control-envelope signature authenticates delivery metadata separately and MUST NOT be substituted for the inner acknowledgement signature.

## 9. Anonymous Component Boundary

The anonymous envelope freezes protocol, network, round, phase, compressed communication key, recipient event key, per-mailbox sequence, payload type, payload digest, expiry, and payload fields. Admission requires the authenticated outer sender identity and the receiving mailbox identity, binds both to the envelope, and rejects an expiry earlier than the caller-supplied current Unix second. Anonymous component admission additionally requires a mainnet-alpha authorization token whose round and RSA key match the manifest and a sealed validator that proves the communication key and disclosed component belong to an admitted commitment. The package models this validator boundary but intentionally provides no production implementation while the commitment-opening/linkage contract remains unresolved.

The individual anonymous BCH-signature payload shape is modeled for deterministic transaction assembly, but runtime admission remains fail closed. The generic protocol requires one-time authorization and committed mailbox linkage for signature submissions; this profile does not invent the missing issuance and replay document.

## 10. BCH Signature Set And Complete Transaction

One BCH signature entry is `inputIndex u32 || schnorrSignature64 || compressedPublicKey33`. A complete set is `roundIdentifier32 || transcriptRoot32 || vector(entry)`, with entries already in exact ascending indices `0...(inputCount - 1)`. Its digest is `SHA256(domain("bch-signature-set") || canonical(set))`. A decoder MUST reject descending, duplicate, missing, or out-of-range indices rather than sorting received bytes.

Complete assembly independently checks every ordered previous outpoint, component-committed amount, resolved previous-output amount, standard P2PKH locking script, compressed public key, and Schnorr signature against the exact acknowledged unsigned transaction and sighash byte `0x41`. Inputs and outputs together cannot exceed the 184 nonblank component slots. Each unlocking script is exactly `0x41 || signature64 || 0x41 || 0x21 || publicKey33`, totaling 100 bytes. The complete payload is `roundIdentifier32 || transcriptRoot32 || bytes(completeTransaction)` with digest `SHA256(domain("complete-transaction") || canonical(payload))`. Publication validation requires the expected transcript and rejects a signed transaction whose unlocking-script-stripped body differs from it; exact previous-output and signature validation remains the assembler and host responsibility.

OpalBase remains authoritative. It MUST independently fetch or validate every previous output, verify every script and signature, compare the exact transcript-bound transaction body, enforce fee and network policy, persist the exact transaction, and commit only the matching reservation. OpalFusion assembly never grants broadcast permission.

## 11. Implemented Evidence Boundary

Deterministic tests pin the profile selectors and genesis hash; role commitment and seed; manifest round and complete-manifest digests; PlayerCommit; authorization input and spent identifier; authorization-response-set and complete acknowledgement-set bytes, digests, sizes, ordering, and fragment boundaries; commitment-set, component-set, unsigned-transaction, and transcript digests; control and anonymous envelope fingerprints; strict aggregate reassembly; BCH signature-set ordering; 100-byte unlocking-script assembly; and complete-transaction digest. The admission ledger additionally proves roster-derived zero sequence epochs, attempt/generation/foreign-round routing rejection, per-sender replay and concurrent fragment isolation, exact manifest-core binding, one roster-wide conductor response stream, 6–8-contributor PlayerCommit and response-set barriers, contributor-local finalization before wallet-reservation advancement, conductor-only authorized anonymous-component intake with one-time sender and mailbox identities, transcript-root agreement, conductor-local collection and exact portable publication of every contributor acknowledgement, attempt- and generation-bound phase synchronization, terminal absorption, in-place retry rejection, and stale delivery-routing rejection by a distinct fresh instance. It explicitly terminates before BCH signing and complete-transaction admission. Separate profile-contract tests prove previous-output-backed complete-transaction assembly. A profile-neutral internal coordinator also proves ordered late-lease release, the no-release boundary after signing may have begun, exact complete-transaction commit, and recovery-required failure behavior against injected seams. Cross-profile, foreign-round, wrong-publisher, wrong-phase, malformed canonical aggregate, sequence conflict, local PlayerCommit-digest mismatch, invalid blind response, wrong acknowledgement root, wrong outpoint, wrong P2PKH script, and invalid BCH signature negatives fail closed.

The internal runtime driver still rejects `.opalMainnetAlpha`, and legacy identity-array host markers terminate a mainnet-alpha runtime session. These are release guards, not missing test coverage.

## 12. Remaining Release Gates

The following are intentionally unresolved or external and MUST remain fail closed:

- canonical availability beacon, candidate-set, admission, pool, relay-set, contributor-nonce-allocation, and discovery documents;
- proof-of-work minimums, discovery and pre-manifest timing values, concrete post-manifest deadline values, Nostr event kinds and tags, relay URL normalization, endpoint provisioning, reconnect behavior, and pre-manifest sequencing;
- a concrete Tor WebSocket implementation with reviewed circuit isolation and no clearnet fallback;
- the Pedersen balance equation, per-component fee allocation, commitment-opening/component-linkage validator, production local inclusion validator, and lease-to-component material builder;
- the BCH-signature one-time authorization/replay document;
- conversion of sealed admission-ledger output into mainnet runtime facts, production mailbox integration, and production composition of the internal failure-aware coordinator with sealed mainnet material and host-result provenance;
- ordered previous-output resolution, durable encrypted attempt journal loading, crash recovery execution, app-owned broadcast policy, and a mainnet-disabled end-to-end host integration proof;
- independent protocol, cryptographic, side-channel, privacy, wallet-policy, and deployment review.

Until every relevant gate is complete, safe wording is limited to “deterministic mainnet-alpha contract foundation.” It is not a live Mosaic engine, a mainnet-ready wallet feature, an anonymity claim, or permission to use real funds.
