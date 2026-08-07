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

## 4. Nostr Conformance Contract

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

## 5. Bitcoin Cash Transaction Contract

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

## 6. Implemented And Deferred Boundaries

Implemented deterministic boundaries include the phase and terminal reducer, roster validation, one authoritative profile selector, transcript-to-transaction binding, authorization issuance accounting, attempt-scoped RSA blind-signature evaluation, contributor request finalization and token verification, token replay identifiers, fixed-size inner-envelope coding, exact profile tags and kinds, strict sequence progression, and host request validation.

The following remain blocked or deferred:

- independent parameter, fault, timing, side-channel, and one-more-security review of the RSA blind-signature provider;
- complete reviewed component, Pedersen, proof, and named wire-message schemas with golden vectors;
- discovery proof-of-work and timing values based on device measurements;
- live Nostr relay and Tor-only transport adapters with traffic-analysis testing;
- blame cryptography and any nonterminal blame flow;
- a runnable public `OpalFusion.Session` and production effect driver;
- multi-device chipnet round evidence, fuzzing of every parser, and independent protocol/security review;
- any mainnet enablement or privacy/support claim.

Until those gates are complete, safe wording is limited to a deterministic, nonmainnet conformance foundation.
