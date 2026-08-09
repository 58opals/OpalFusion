# Mosaic Mainnet-Alpha Profile

Status: Frozen deterministic contract profile. Profile identifier: `Mosaic/0-opal-mainnet-alpha.3`. Transport identifier: `nostr-tor/0-opal-mainnet-alpha.3`. Transaction profile identifier: `bch-mainnet-p2pkh-schnorr/0-opal-mainnet-alpha.3`.

This profile freezes an additive mainnet-targeted canonical contract without enabling a runnable Mosaic session, a live transport, wallet execution, broadcast, or a production-support claim. An internal admission ledger seals admitted documents through transcript agreement to one attempt, generation, and round-scoped per-sender sequence epoch. A paired internal runtime session owns that ledger and the same validated local attempt, requires an externally sealed reservation-publication validation carrying the exact lease and PlayerCommit binding, verifies every local commitment is present in the conductor set, and synchronizes only locally ready immediate phase successors through transcript agreement. A narrow reservation coordinator accepts that validation only when it matches the actual host-returned lease, rejects non-fresh runtime state, and releases a late lease when cancellation wins; the injected validator still owns the unimplemented lease-to-PlayerCommit derivation proof. An internal signing-request builder consumes only that sealed publication, exact local transcript inclusion, the roster-complete acknowledgement set, and resolver-minted previous-output validation to construct a host request without invoking signing. The runtime refuses BCH-signing or complete-transaction admission. The executable runtime driver deliberately rejects this profile until commitment linkage, material provenance, previous-output authority, anonymous BCH-signature authorization, effect execution, recovery, and transport gates in Section 12 are complete. No test or package default may spend or broadcast mainnet funds.

## 1. Compatibility And Versioning

`Mosaic/0-opal-mainnet-alpha.3` is distinct from the chipnet-only [`Mosaic/0-opal.1`](mosaic-v0-profile.md) conformance profile and from `Mosaic/1-draft.1`. It supersedes alpha.2 because alpha.2's zero-excess rule omitted the fixed ten bytes of every supported BCH transaction and therefore could not satisfy its own exact one-satoshi-per-final-byte policy. Alpha.3 retains alpha.2's aggregate kinds 3 and 5 and post-admission control-sequence epoch while assigning that fixed overhead deterministically across contributors. Implementations MUST reject cross-profile bytes. Adding this profile MUST NOT change any `Mosaic/0-opal.1` default, domain, canonical byte, tag, event kind, digest, or golden vector.

Any change to a field, field order, width, enum value, domain separator, transaction rule, or signature-authorization rule defined here requires a new profile identifier. Unresolved transport and cryptographic contracts listed in Section 12 are not implicitly defined by this identifier.

Alpha.3 also extends the public Mosaic reservation and signing requests with `requiredExcessFeeSatoshis`, because the prior minimum/maximum range cannot identify one contributor's roster-derived share. The source-compatible legacy initializers remain available only for singleton ranges and fail closed for an ambiguous range; host integrations that used a range MUST pass the exact required value explicitly.

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

Every profile domain is exact UTF-8 `"Mosaic/0-opal-mainnet-alpha.3/" || suffix` with no terminating zero. The role documents are:

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

A standard P2PKH input contributes `amount - 141` satoshis, a standard P2PKH output contributes `-(amount + 34)` satoshis, and a blank contributes zero. The 141-byte input and 34-byte output charges cover every component-derived byte. The remaining transaction fields are the four-byte version, one-byte input count, one-byte output count, and four-byte lock time. Counts remain one byte because this profile permits at most 184 nonblank components, so the fixed overhead is exactly ten bytes and ten satoshis.

Let `n` be the 6–8 contributor count, order contributors lexicographically by their 32-byte one-time control identity, let `base = 10 / n`, and let `remainder = 10 % n` using unsigned integer division. Contributors at indices below `remainder` MUST declare `base + 1` excess satoshis and the rest MUST declare `base`. The resulting vectors are `[2,2,2,2,1,1]`, `[2,2,2,1,1,1,1]`, and `[2,2,1,1,1,1,1,1]`; every vector totals exactly ten. A conductor has no share. A PlayerCommit whose declared excess differs from its roster-derived share is invalid.

For each PlayerCommit, the sum of all 23 Pedersen commitment points MUST equal a commitment to the exact roster-derived excess using the published total nonce and OpalCrypto's canonical Pedersen setup. This group equation proves the declared aggregate balance but does not prove that any disclosed component opens a particular member commitment.

A control envelope may admit a PlayerCommit reservation only during wallet reservation and only from the same contributor control key encoded by the document. Structural admission alone does not authorize phase advancement. The implemented semantic validation additionally binds the exact manifest round, contributor role, roster-derived excess share, and grouped Pedersen equation. Salt construction, individual commitment openings, lease-to-material construction, privacy-preserving anonymous linkage, and contributor nonce-allocation derivation remain explicitly deferred.

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

The anonymous envelope freezes protocol, network, round, phase, compressed communication key, recipient event key, per-mailbox sequence, payload type, payload digest, expiry, and payload fields. Admission requires the authenticated outer sender identity and the receiving mailbox identity, binds both to the envelope, and rejects an expiry earlier than the caller-supplied current Unix second. Anonymous component admission additionally requires a mainnet-alpha authorization token whose round and RSA key match the manifest and a sealed validator for the still-unresolved component-admission proof. The published grouped-commitment communication key MUST NOT be reused directly as the anonymous envelope identity because direct equality would reveal the contributor-to-component linkage to the conductor. This profile does not yet freeze a privacy-preserving proof relating a disclosed component to an admitted commitment, so the package models the validator boundary but provides no production implementation.

The individual anonymous BCH-signature payload shape is modeled for deterministic transaction assembly, but runtime admission remains fail closed. The generic protocol requires one-time authorization and committed mailbox linkage for signature submissions; this profile does not invent the missing issuance and replay document.

## 10. BCH Signature Set And Complete Transaction

One BCH signature entry is `inputIndex u32 || schnorrSignature64 || compressedPublicKey33`. A complete set is `roundIdentifier32 || transcriptRoot32 || vector(entry)`, with entries already in exact ascending indices `0...(inputCount - 1)`. Its digest is `SHA256(domain("bch-signature-set") || canonical(set))`. A decoder MUST reject descending, duplicate, missing, or out-of-range indices rather than sorting received bytes.

Complete assembly independently checks every ordered previous outpoint, component-committed amount, resolved previous-output amount, standard P2PKH locking script, compressed public key, and Schnorr signature against the exact acknowledged unsigned transaction and sighash byte `0x41`. Inputs and outputs together cannot exceed the 184 nonblank component slots. Each unlocking script is exactly `0x41 || signature64 || 0x41 || 0x21 || publicKey33`, totaling 100 bytes. The complete payload is `roundIdentifier32 || transcriptRoot32 || bytes(completeTransaction)` with digest `SHA256(domain("complete-transaction") || canonical(payload))`. Publication validation requires the expected transcript and rejects a signed transaction whose unlocking-script-stripped body differs from it; exact previous-output and signature validation remains the assembler and host responsibility.

OpalBase remains authoritative. It MUST independently fetch or validate every previous output, verify every script and signature, compare the exact transcript-bound transaction body, enforce fee and network policy, persist the exact transaction, and commit only the matching reservation. OpalFusion assembly never grants broadcast permission.

The public `MosaicPreviousOutputSource` contract accepts an ordered vector of transcript-committed outpoints and expected amounts and returns ordered source-asserted output data, including the locking script and token-presence state. The internal mainnet-alpha resolver derives that request vector from the exact transcript, binds exact outpoints and amounts, and rejects reported token presence. This boundary neither proves that the locking script or token state came from authoritative transaction bytes nor authorizes signing, commit, or broadcast; a production OpalBase adapter must establish those facts and the wallet host must revalidate every resolved previous output at signing time.

The internal signing-request builder accepts only a resolver-minted validation for the exact transcript. It additionally requires the complete sealed reservation lease and PlayerCommit publication, contributor-local transcript-inclusion validation for the same attempt, generation, and material, and a roster-complete acknowledgement set for the same round and transcript root. It maps each reserved local outpoint to the canonical transcript index, requires exact amount and locking-script equality, validates compressed secp256k1 public keys against standard P2PKH scripts, matches local outputs as a multiset, and supplies the roster-derived excess-fee share to the public host request. Constructing that request is not BCH-signing eligibility, a host invocation, a previous-output authority claim, commit permission, or broadcast permission.

## 11. Implemented Evidence Boundary

Deterministic tests pin the profile selectors and genesis hash; the canonical 6–8-contributor fixed-overhead allocation; exact component and final-fee arithmetic; grouped-commitment profile bounds and Pedersen sum validation; role commitment and seed; manifest round and complete-manifest digests; PlayerCommit; authorization input and spent identifier; authorization-response-set and complete acknowledgement-set bytes, digests, sizes, ordering, and fragment boundaries; commitment-set, component-set, unsigned-transaction, and transcript digests; control and anonymous envelope fingerprints; strict aggregate reassembly; BCH signature-set ordering; 100-byte unlocking-script assembly; and complete-transaction digest. The admission ledger additionally proves roster-derived zero sequence epochs, attempt/generation/foreign-round routing rejection, per-sender replay and concurrent fragment isolation, exact manifest-core binding, one roster-wide conductor response stream, 6–8-contributor PlayerCommit and response-set barriers, contributor-local finalization before wallet-reservation advancement, conductor-only authorized anonymous-component intake with one-time sender and mailbox identities, transcript-root agreement, conductor-local collection and exact portable publication of every contributor acknowledgement, attempt- and generation-bound phase synchronization, terminal absorption, in-place retry rejection, and stale delivery-routing rejection by a distinct fresh instance. The paired runtime-session tests prove common construction for 6–8 contributors, exact manifest and aggregate translation into the local attempt, an externally validated reservation-publication binding seam, field-isolated substitution rejection, exact local-commitment inclusion, conductor non-contribution, transcript equality, release-before-terminal failure ordering, cancellation, terminal absorption, and in-place retry rejection. They do not prove that a reservation is live or that production lease material derived the PlayerCommit. The signing-request-builder tests prove sealed-lease, local-inclusion, exact-round/root/roster acknowledgement, resolver-only previous-output, canonical multi-input index, local-output multiset, P2PKH key, and required-fee-share binding before host-request construction. They do not invoke signing or supply runtime signing eligibility. Separate profile-contract tests prove previous-output-backed complete-transaction assembly. A profile-neutral internal coordinator also proves ordered late-lease release, the no-release boundary after signing may have begun, exact complete-transaction commit, and recovery-required failure behavior against injected seams. Cross-profile, foreign-round, wrong-publisher, wrong-phase, malformed canonical aggregate, sequence conflict, wrong excess share, invalid grouped Pedersen balance, local PlayerCommit-digest mismatch, invalid blind response, wrong acknowledgement round, root, or roster, wrong reservation publication binding, local commitment substitution, wrong outpoint, wrong P2PKH script, and invalid BCH signature negatives fail closed.

The profile-scoped reservation coordinator proves exact host-lease/reference matching, rejection of direct validation injection, one reservation and publication claim, late-lease release, publication-before-release ordering, every frozen request field plus an exact caller-owned expiration, conductor rejection, and recovery-required release failure. It does not select the still-unfrozen manifest-deadline-to-lease-expiry mapping, construct a PlayerCommit, or prove that the lease material produced one. The internal runtime driver still rejects `.opalMainnetAlpha`, and legacy identity-array host markers terminate a mainnet-alpha runtime session. These are release guards, not missing test coverage.

## 12. Remaining Release Gates

The following are intentionally unresolved or external and MUST remain fail closed:

- canonical availability beacon, candidate-set, admission, pool, relay-set, contributor-nonce-allocation, and discovery documents;
- proof-of-work minimums, discovery and pre-manifest timing values, concrete post-manifest deadline values, Nostr event kinds and tags, relay URL normalization, endpoint provisioning, reconnect behavior, and pre-manifest sequencing;
- a concrete Tor WebSocket implementation with reviewed circuit isolation and no clearnet fallback;
- salt and salted-component formulas, individual commitment-opening/component-linkage validation, a privacy-preserving anonymous linkage proof, a production local inclusion validator, a lease-to-component material builder, and a production validator proving live reservation and PlayerCommit derivation provenance;
- the BCH-signature one-time authorization/replay document;
- production mailbox ingress into the paired runtime session, executable runtime-driver integration, production lease-to-PlayerCommit validation, and full failure-aware coordinator composition with sealed mainnet material;
- an authoritative production previous-output source wired into executable composition, signing-request execution under the mainnet runtime's failure ordering, durable encrypted attempt journal loading, crash recovery execution, app-owned broadcast policy, and a mainnet-disabled end-to-end host integration proof;
- independent protocol, cryptographic, side-channel, privacy, wallet-policy, and deployment review.

Until every relevant gate is complete, safe wording is limited to “deterministic mainnet-alpha contract foundation.” It is not a live Mosaic engine, a mainnet-ready wallet feature, an anonymity claim, or permission to use real funds.

The non-normative [Alpha.4 Design Proposal](mosaic-mainnet-alpha4-design-proposal.md) records one review-ready resolution for the salt, local material, purpose-separated signature authorization, mailbox, and privacy-proof decisions. It has no protocol or implementation authority until explicitly approved and incorporated here with golden vectors.
