# Mosaic Opal v0 Conformance Profile

Status: Implemented deterministic conformance profile. Profile identifier: `Mosaic/0-opal.1`. Transport identifier: `nostr-conformance/0-opal.1`. This profile is chipnet-only and does not provide a live Mosaic session, anonymous transport, independently reviewed production cryptography, privacy evidence, or mainnet support.

This document freezes the Opal-owned choices needed to validate deterministic cross-package contracts while the generic [`Mosaic/1-draft.1`](mosaic-protocol-specification.md) design remains incomplete. It is not a claim that independent implementations can run a live round.

## 1. Profile Identity And Roster

`OpalFusion.Mosaic.Configuration(profile: .opalV0)` is the sole selector for this profile. Protocol, roster, transport, network, authorization, transcript, and transaction constants must not be selected independently.

| Contract | `Mosaic/0-opal.1` value |
|---|---|
| Network | Bitcoin Cash chipnet |
| Genesis hash, conventional display order | `000000001dd410c49a788668ce26751718cc797474d3152a5fc073dd44fd9f7b` |
| Conductors | exactly 1 |
| Contributors | 6–8 |
| Total candidates | 7–9 |
| Components per contributor | exactly 23 |
| Conductor contribution | prohibited |
| Retry | a new attempt with completely fresh material |
| Blame | disabled; failure terminates the attempt |

The default `Mosaic.Configuration()` remains `.draft1` for source behavior compatibility. No public `OpalFusion.Session` initializer or live Mosaic adapter exists.

## 2. Authorization Contract

The profile selects [RFC 9474](https://www.rfc-editor.org/rfc/rfc9474.html) `RSABSSA-SHA384-PSS-Randomized` with RSA-2048, public exponent 65,537, SHA-384, MGF1-SHA384, a 48-byte PSS salt, and a fresh 32-byte randomized-message prefix. Encoded blinded messages, blind-signature responses, and finalized signatures are each 256 bytes. The attempt uses a fresh, attempt-exclusive signing key. The key identifier is `SHA256` of the validated SubjectPublicKeyInfo document; profile adapters must validate the `id-RSASSA-PSS` parameters described by [RFC 9578](https://www.rfc-editor.org/rfc/rfc9578.html) before treating a key identifier as valid.

OpalCrypto implements this bounded profile with opaque nonpersistent RSA-2048 signing keys, operating-system randomness, strict PSS SubjectPublicKeyInfo validation, client blinding, raw-signing fault checks, finalization, and signature verification. Its client path matches the published RFC 9474 randomized SHA-384/PSS vector. OpalFusion adds an internal attempt-scoped evaluator and contributor-local request/finalization adapter; an explicitly unavailable evaluator remains fail-closed. These operations have not completed independent cryptographic or side-channel review and do not make the profile live or production-ready.

Each contributor has exactly 23 component-authorization request slots numbered `0...22`. The conductor evaluates no request until all 23 slots from every contributor are present. An exact duplicate request is idempotent and reuses the cached response; a different request in an occupied slot terminates the attempt. The ledger never accepts conductor or unknown-contributor requests. A provider failure terminates the attempt.

The canonical component-token input contains the profile/component-authorization domain, chipnet genesis hash, 32-byte round identifier, validated 32-byte authorization-key identifier, and fresh 32-byte nonce. A token's spent identifier is derived from this canonical input, not from the randomized prefix or finalized randomized signature.

These rules constrain issuance and replay accounting. Passing the deterministic and published-vector tests does not itself prove blindness, one-more unforgeability, or side-channel resistance.

## 3. Transcript And Signing Binding

The wallet-host transcript binding carries four 32-byte digests:

1. manifest digest;
2. commitment-set digest;
3. component-set digest;
4. exact unsigned-transaction digest.

`unsignedTransactionDigest = SHA256(UTF8(profile + "/unsigned-transaction") || bytes(unsignedTransaction))`.

`transcriptRoot = SHA256(UTF8(profile + "/transcript") || bytes(manifestDigest) || bytes(commitmentSetDigest) || bytes(componentSetDigest) || bytes(unsignedTransactionDigest))`.

Here `bytes(value)` is the Mosaic canonical `u32(length) || value` encoding. A `MosaicTranscriptBinding` validates all digest lengths, recomputes the unsigned-transaction digest from the exact bytes, and rejects an acknowledged root that differs from the recomputed root. `MosaicTransactionSigningRequest` requires this binding and rejects substituted transaction bytes.

The binding proves internal consistency, not unanimity. The attempt reducer remains responsible for requiring every contributor to acknowledge the same root before it emits BCH-signing eligibility. OpalBase must recheck the binding before any signature operation.

## 4. Canonical Component, Aggregate, And Message Documents

The Opal v0 documents below use the fixed-order canonical encoding from Section 8 of the generic Mosaic specification. They are transport-independent hash documents and subordinate message bodies, not complete `PlayerCommit` or Nostr event bodies. This profile defines deterministic fragmentation only for the existing canonical commitment-set and component-set bytes; it does not define complete message composition, a Nostr payload type for fragments, or how fragment delivery interacts with authenticated control sequence numbers. No generic `Mosaic/1-draft.1` field numbers are assigned by this profile.

The profile freezes these primitive representations:

- hashes, round identifiers, authorization-key identifiers, nonces, salt commitments, and transcript roots are fixed 32-byte fields without length prefixes;
- Pedersen amount commitments are validated secp256k1 points encoded as canonical 65-byte uncompressed SEC1 values;
- component communication public keys are validated secp256k1 points encoded as canonical 33-byte compressed SEC1 values;
- blinded authorization requests, blind-signature responses, and finalized authorization signatures are fixed 256-byte fields;
- Pedersen total nonces and randomized-message prefixes are validated fixed 32-byte fields;
- output components contain exactly one standard 25-byte P2PKH locking script: `OP_DUP OP_HASH160 PUSHBYTES_20 <20 bytes> OP_EQUALVERIFY OP_CHECKSIG`;
- satoshi amounts are positive `u64` values no greater than the Bitcoin Cash maximum money supply, except that a blank component has the implicit amount zero.

The canonical documents are:

| Document | Fixed field order |
|---|---|
| Component commitment | salted-component digest, amount commitment, communication public key |
| Grouped commitment payload | vector of exactly 23 component commitments in contributor slot order, zero excess fee as `u64`, Pedersen total nonce |
| Authorization request payload | slot as `u8`, blinded request |
| Authorization response payload | slot as `u8`, blind-signature response |
| Authorization token | round identifier, authorization-key identifier, nonce, randomized-message prefix, finalized signature |
| Anonymous component payload | round identifier, authorization token, component |
| Pre-sign acknowledgement payload | round identifier, transcript root |
| Aggregate fragment | round identifier, aggregate kind as `u8`, aggregate digest, declared aggregate byte count as `u32`, zero-based fragment index as `u8`, fragment count as `u8`, fragment body as canonical bytes |

A component encodes its 32-byte salt commitment, then a `u8` kind and kind-specific fields. The kind values are `0` for input, `1` for output, and `2` for blank. An input then encodes the previous transaction hash in conventional display order, output index as `u32`, and amount as `u64`. An output then encodes the fixed 25-byte P2PKH locking script and amount as `u64`. A blank has no additional fields.

Authorization slots are exactly `0...22`. Each request and response has a slot-addressed canonical subordinate document and remains subject to the all-contributor issuance barrier in Section 2. The complete `PlayerCommit` composition that binds the grouped commitment to its 23 requests remains deferred. An anonymous component payload must carry a token whose embedded round identifier exactly matches the payload round identifier. Token signature verification and spent-identifier accounting remain mandatory validation steps outside decoding.

Within a grouped commitment and across the aggregate commitment set, salted-component digests, amount commitments, and component communication public keys must each be unique. Across the component set, salt commitments must be unique. These checks reject observable reuse of material that the protocol requires to be fresh; they do not replace cryptographic generation or secret-lifecycle review.

A commitment set is a canonical sorted set of component commitments. A component set is a canonical sorted set of components and additionally rejects duplicate input outpoints. Each set must contain `contributorCount * 23` members for 6–8 contributors, therefore 138–184 members in a multiple of 23. Their digests are:

`commitmentSetDigest = SHA256(UTF8(profile + "/commitment-set") || canonical(commitmentSet))`.

`componentSetDigest = SHA256(UTF8(profile + "/component-set") || canonical(componentSet))`.

The aggregate-fragment kind values are `0` for a commitment set and `1` for a component set. This is an Opal v0 subordinate-document enum, not a Nostr event kind. The fixed header is 75 bytes: the two 32-byte fields, kind, declared aggregate byte count, fragment index, fragment count, and the canonical `u32` body-length prefix. Each encoded fragment MUST fit the 4,092-byte raw inner-envelope limit, so the body capacity is exactly 4,017 bytes. The canonical splitter operates on byte boundaries, uses a zero-based index, fills every nonfinal body to 4,017 bytes, and emits one positive-length final remainder. Fragment count is derived as `ceil(declaredAggregateByteCount / 4,017)` and MUST match the encoded count. The largest accepted aggregate document is the 23,924-byte, 184-member commitment set, so no aggregate can require more than six fragments.

A fragment descriptor binds a 32-byte round identifier, aggregate kind, existing domain-separated aggregate digest, and declared canonical byte count. A reassembler is initialized for one expected round and kind, validates that context before indexing, and lets the first valid fragment bind the digest and total. Reordering and byte-identical duplicate indices are accepted. A different body at an occupied index or a competing digest or total terminates the reassembler. No partial aggregate is emitted. Completion concatenates bodies in canonical index order, verifies the existing kind-specific aggregate digest, and then invokes the strict commitment-set or component-set decoder; digest agreement alone cannot admit descending, duplicate, trailing, or structurally invalid members. Success and failure are terminal and discard buffered fragment material. Retry requires a fresh attempt and reassembler.

Fragmentation is a bounded subordinate-document contract only. It does not assign complete authenticated envelopes, sender identities, relay events, delivery deadlines, or sequence layering. Applying the existing padded-envelope codec to an encoded fragment produces the fixed 8,192-byte plaintext, but the fragment codec itself emits variable-length documents and the number of fragments reveals an aggregate size class.

This slice validates canonical syntax, point/key encodings, fixed counts, P2PKH output form, amount bounds, duplicate rejection, round binding, deterministic set digests, and bounded aggregate fragmentation and reassembly. It does not define or claim validation of the unresolved CashFusion-derived Pedersen sum equation, per-component fee allocation, a complete round manifest, anonymous BCH-signature authorization, or blame proofs. Blame remains disabled for this profile, so an Opal v0 decoder accepts no proof document.

## 5. Nostr Conformance Contract

The profile assigns three Nostr ephemeral kinds:

| Use | Kind |
|---|---:|
| Discovery | `26528` |
| Authenticated control | `21939` |
| Anonymous submission | `20652` |

These are Opal conformance assignments, not a claim of registry ownership. Discovery events have no tags. Encrypted point-to-point control and anonymous events have exactly one tag, `[["p", recipientEventPublicKeyLowercaseHex]]`, with a 32-byte recipient event key. An attempt's Nostr event key and control identity are distinct one-time 32-byte values.

The inner plaintext is exactly 8,192 ASCII bytes. It contains an eight-character lowercase hexadecimal payload-byte length, lowercase hexadecimal payload bytes, and ASCII `0` padding. The maximum raw payload is 4,092 bytes. NIP-44 v2 encoding of this 8,192-byte plaintext is exactly 11,012 ASCII bytes. The maximum accepted complete event JSON is 16,384 bytes.

Per-sender control sequencing begins at zero and increments by exactly one. An exact duplicate identifier at an accepted sequence is idempotent. A gap or conflicting identifier at the same sequence terminates the attempt.

No relay client, Tor circuit manager, mailbox adapter, proof-of-work minimum, discovery timing, relay URL set, or live traffic-shaping policy is defined by this profile slice.

## 6. Bitcoin Cash Transaction Contract

The transaction profile identifier is `bch-chipnet-p2pkh-schnorr/0-opal.1`. A conforming wallet-host policy must require:

- chipnet and the exact profile genesis hash;
- transaction version `2`, lock time `0`, and input sequence `UInt32.max`;
- empty unlocking scripts before local signing;
- standard P2PKH inputs and outputs only;
- no CashTokens and no dedicated on-chain marker output;
- Bitcoin Cash Schnorr signatures with `SIGHASH_ALL | SIGHASH_FORKID` and without `ANYONECANPAY`;
- inputs ordered lexicographically by conventional display-order previous transaction hash, then output index;
- outputs ordered by amount in satoshis, then locking-script bytes;
- every referenced previous transaction fetched and decoded, with its hash, output index, amount, locking script, and token absence verified;
- fee rate exactly 1 satoshi per estimated final signed byte and zero permitted excess-fee range.

The exact fee is `estimatedFinalSignedSize * 1 satoshi`. The estimator must model one 100-byte standard P2PKH Schnorr unlocking script for each input. A policy mismatch fails before signing.

This rigid transaction contract exists for deterministic chipnet conformance. It is not a mainnet fee recommendation or a complete wallet coin-selection policy.

## 7. Implemented And Deferred Boundaries

Implemented deterministic boundaries include the phase and terminal reducer, roster validation, one authoritative profile selector, transcript-to-transaction binding, authorization issuance accounting, attempt-scoped RSA blind-signature evaluation, contributor request finalization and token verification, token replay identifiers, canonical Opal v0 component, commitment, set, authorization-message, anonymous-submission, pre-sign-acknowledgement, and aggregate-fragment documents, bounded aggregate fragmentation and terminal reassembly, fixed-size inner-envelope coding, exact profile tags and kinds, strict sequence progression, and host request validation.

The following remain blocked or deferred:

- independent parameter, fault, timing, side-channel, and one-more-security review of the RSA blind-signature provider;
- the unresolved Pedersen sum and fee-allocation algorithms, complete manifest and BCH-signature messages, their authenticated fragment-envelope and sequence integration, and any future proof or blame schema;
- discovery proof-of-work and timing values based on device measurements;
- live Nostr relay and Tor-only transport adapters with traffic-analysis testing;
- blame cryptography and any nonterminal blame flow;
- a runnable public `OpalFusion.Session` and production effect driver;
- multi-device chipnet round evidence, fuzzing of every parser, and independent protocol/security review;
- any mainnet enablement or privacy/support claim.

Until those gates are complete, safe wording is limited to a deterministic, nonmainnet conformance foundation.
