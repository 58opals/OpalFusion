# Mosaic Mainnet-Alpha.4 Design Proposal

Status: Non-normative review proposal. No source, wire codec, runtime gate, wallet integration, or deployment may consume these choices until they are explicitly approved and moved into the normative mainnet-alpha profile with golden vectors.

This proposal addresses the remaining protocol-owned gaps between the frozen `Mosaic/0-opal-mainnet-alpha.3` deterministic foundation and a runtime that can safely request Bitcoin Cash signatures. It does not authorize mainnet spending, networking, broadcast, or a privacy claim.

## 1. Decision Summary

| Decision | Recommendation | Consequence |
|---|---|---|
| A4-D1: versioning | Advance the existing `.opalMainnetAlpha` selector to `Mosaic/0-opal-mainnet-alpha.4`; do not add a second public enum case | Alpha.3 bytes and persisted attempts become non-resumable; retry starts with completely fresh alpha.4 material |
| A4-D2: component salts | Use fresh 32-byte salts with alpha.4-domain-separated, round-bound hashes | Prevents cross-profile and cross-round reuse while preserving anonymous component bytes |
| A4-D3: local material proof | Implement exact lease-content-to-23-slot construction and contributor-local opening/inclusion validation | Proves deterministic derivation from a sealed lease value but leaves live wallet ownership, persistence, and liveness to OpalBase |
| A4-D4: BCH-signature authorization | Issue a second blind credential for every one of the 23 slots under a separate attempt-exclusive RSA key | Hides the contributor's real input count and cryptographically prevents component credentials from authorizing signatures |
| A4-D5: signature mailbox | Use a fresh anonymous sender key and a second sequence on the component's already admitted recipient mailbox | Avoids inventing an unfrozen mailbox-assignment document while keeping signature delivery separate from the component sender identity |
| A4-D6: privacy proof | Require an independently reviewed unlinkable membership proof; prohibit a conductor-visible opening fallback | Keeps the central contributor-to-component unlinkability goal intact, but leaves live runtime enablement blocked until that proof is designed and reviewed |

## 2. Compatibility And Migration

The recommended profile, transport, transaction, and domain prefixes are respectively `Mosaic/0-opal-mainnet-alpha.4`, `nostr-tor/0-opal-mainnet-alpha.4`, `bch-mainnet-p2pkh-schnorr/0-opal-mainnet-alpha.4`, and exact UTF-8 `"Mosaic/0-opal-mainnet-alpha.4/" || suffix`. The existing Swift selector remains `.opalMainnetAlpha`; its computed contract changes only when the alpha.4 normative document lands.

Alpha.4 decoders reject every alpha.3 identifier and digest. Alpha.3 decoders reject alpha.4. No journal, reservation, output, salt, nonce, key, blind request, mailbox, acknowledgement, or partially signed transaction crosses the version boundary. Because mainnet-alpha has never had an enabled runtime driver, this is a fail-closed contract migration rather than a live-session compatibility promise.

The alternative is a new public `.opalMainnetAlpha4` selector that retains alpha.3 indefinitely. That preserves explicit historical selection but expands a public API for a profile that cannot run. This proposal recommends the smaller single-selector migration.

## 3. Salted Component Construction

For every one of the 23 contributor slots, generate an independent uniformly random 32-byte `salt32`, Pedersen nonce, component communication key, component authorization nonce, and signature authorization nonce. None may be reused by another slot, attempt, generation, round, purpose, or retry.

The proposed hashes are:

```text
saltCommitment32 = SHA256(domain("component-salt") || roundIdentifier32 || salt32)
saltedComponentDigest32 = SHA256(domain("salted-component") || roundIdentifier32 || salt32 || canonical(componentPayload))
```

`canonical(componentPayload)` is only the already-defined input, output, or blank payload encoding; it excludes the salt commitment, blind credentials, mailbox fields, contributor identity, and slot number. The anonymous component carries `saltCommitment32` and the payload. The grouped component commitment carries `saltedComponentDigest32`, its Pedersen amount commitment, and its communication public key.

Domain separation and round binding are recommended instead of copying a bare CashFusion hash because this is a new versioned contract and cross-round material reuse must fail cryptographically. The normative alpha.4 change must add golden vectors for every component kind and reject wrong domain, round, salt length, payload encoding, and trailing bytes.

## 4. Lease-To-Material Construction And Local Validation

The production material owner should construct exactly 23 slots from one live reservation lease: all selected inputs, all fresh outputs, then enough blanks to reach 23, with a deterministic private slot order that is shuffled before anonymous delivery. It must reject the lease without truncation or wallet progression when `inputs.count + outputs.count > 23`; exactly 23 nonblank components is valid and adds no blanks. Each input and output amount contribution follows the already frozen 141-byte input, 34-byte output, and roster-derived alpha.3 excess-share rules. The conductor remains non-contributing.

For each slot, the material owner stores the exact lease reference, attempt, generation, material identifier, round, component payload, salt, Pedersen nonce, amount commitment, component communication private key, both blind-request states, and mailbox binding. Secrets remain outside reducer state and must be erased at terminal disposition.

Contributor-local validation opens each locally retained Pedersen commitment, recomputes both hashes, proves that all 23 exact grouped commitments are present in the conductor's commitment set, proves that every local component is present exactly once in the component set, and binds the resulting transcript-inclusion validation to the same attempt, generation, material, contributor, and transcript. The existing sealed runtime inputs remain the only reducer authority.

This local proof does not let the conductor verify that an anonymous component came from one of the contributor-tagged grouped commitments. Revealing the salt, Pedersen opening, group index, or contributor identity to the conductor would create the linkage Mosaic is intended to hide and is therefore not an acceptable production fallback.

## 5. Purpose-Separated Blind Authorization

Each slot receives two independent RSABSSA credentials under two independently generated, attempt-exclusive RSA keys. The alpha.4 manifest replaces the singular blind-signing verification key with two ordered fields: the component-authorization verification key followed by the BCH-signature-authorization verification key. Their key identifiers must be distinct. Purpose values are exactly `0 = component` and `1 = BCH signature`:

```text
authorizationInput = text(profileIdentifier || "/authorization/input") || bytes(genesisHash32) || bytes(roundIdentifier32) || bytes(keyIdentifier32) || purpose u8 || bytes(nonce32)
authorizationSpentIdentifier = SHA256(domain("authorization-spent") || authorizationInput)
```

Purpose zero requires the component-authorization key identifier and purpose one requires the BCH-signature-authorization key identifier. Any other purpose/key pairing is invalid even when the underlying RSA signature verifies. This relationship is enforced when a contributor constructs and finalizes a request and again when an anonymous token is admitted.

The exact alpha.4 `PlayerCommit` field order is the existing round identifier, contributor identity, and grouped commitment, followed by a 23-entry component-request vector and then a 23-entry signature-request vector. Each request entry remains `slot u8 || blindedMessage256`, and each vector must contain slots `0...22` exactly once in ascending order. The conductor evaluates the component vector only with the component-authorization signing key and the signature vector only with the BCH-signature-authorization signing key. The retained blind-request state is bound to the explicit purpose-bearing authorization input and its required key above. Consequently, moving a blinded purpose-zero request into the signature vector yields a token under the wrong key and cannot mint usable authority, and the inverse fails identically.

The exact alpha.4 authorization-response set field order is the round identifier, contributor identity, PlayerCommit digest, a 23-entry component-response vector, and a 23-entry signature-response vector. Each response entry remains `slot u8 || blindSignature256`, and both vectors must contain slots `0...22` exactly once in ascending order. The addressed contributor finalizes each response only against the matching vector, slot, purpose-bearing input, retained blind-request state, and purpose-specific manifest key. A credential valid for one purpose is invalid for the other.

The exact alpha.4 authorization-token wire form is `roundIdentifier32 || keyIdentifier32 || purpose u8 || nonce32 || messageRandomizer32 || signature256`. A component submission requires purpose zero. A BCH-signature submission requires purpose one and has exact inner field order `transcriptRoot32 || authorizationToken || inputIndex u32 || schnorrSignature64 || compressedPublicKey33`. The surrounding anonymous envelope supplies and authenticates the common round and delivery metadata; the token round must equal it. Replay uses `authorizationSpentIdentifier` above, so the purpose is part of the replay key.

Fixed 23-plus-23 issuance is recommended over issuing signature credentials only for input slots because the latter reveals each contributor's input count to the conductor during the control phase. It also avoids deriving signature authority from a component credential, which would make cross-purpose replay possible.

## 6. Anonymous BCH-Signature Delivery

After the complete acknowledgement set has been validated, each real input slot uses its purpose-1 credential to authorize exactly one `BCHSignatureSubmission`. Blank and output slots never submit a signature, but their unused purpose-1 credentials reveal nothing about which slots were inputs.

The proposed delivery uses a new anonymous sender event key and a fresh Tor circuit while retaining the exact recipient mailbox identity already bound to that component. The component delivery consumes mailbox sequence zero; its optional BCH-signature delivery consumes sequence one. Admission authenticates the complete outer envelope and canonical payload, computes its exact record identity, and checks the accepted-record table first. A byte-identical authenticated record already accepted for that mailbox is idempotent even after phase advancement or expiry. A nonduplicate then passes the current recipient-mailbox, profile, round, phase, expiry, sequence-range, payload-shape, purpose-1 token, transcript-root, input-index, public-key, and signature-semantic checks without mutating replay state. Unauthenticated, stale, foreign-round, wrong-phase, expired, wrong-purpose, malformed, or otherwise invalid nonduplicate traffic is rejected without consuming the mailbox sequence, sender key, or token. Only an authenticated nonduplicate with a valid purpose-1 token that conflicts with an already accepted use of the same mailbox sequence, anonymous sender identity, or spent identifier is terminal equivocation. After all validation succeeds, the conductor atomically records the exact record, sequence, sender identity, and purpose-1 spent identifier before accepting the signature. A third mailbox sequence is rejected without mutating the attempt.

Reusing the recipient mailbox avoids inventing a second confidential mailbox-assignment message. It does create an intentional component-to-signature association, which is already necessary to bind the signature to that public input; it must not create a contributor-control association. The transport review must verify that the fresh sender key, timing policy, and circuit isolation prevent the two deliveries from exposing the contributor.

## 7. Unresolved Privacy-Preserving Membership Proof

Current OpalCrypto primitives can generate and open Pedersen commitments, BIP340 signatures, RSABSSA credentials, and NIP44 ciphertexts. They do not provide a reviewed zero-knowledge proof that an anonymously submitted component belongs to one member of the published commitment set without disclosing which contributor's 23-member group contained it.

Alpha.4 must therefore choose and independently review an unlinkable membership construction before the executable mainnet runtime is enabled. The proof must bind the exact round, commitment-set digest, salted-component digest, amount commitment, communication key, anonymous component payload, and one-time authorization while hiding the group and contributor. It must have canonical encoding, bounded verification cost, replay semantics, failure behavior, and published positive and negative vectors.

This proposal rejects the tempting shortcut of sending the salt or Pedersen opening to the conductor. That shortcut would make implementation easier but would allow the conductor to map each component back to its contributor group, defeating a primary Mosaic privacy objective.

## 8. Required Proof Before Runtime Enablement

The alpha.4 implementation may land in two bounded steps. First, contract and local-material code may land while the mainnet driver remains disabled. Second, anonymous admission and executable runtime work may land only after the membership proof and transport binding are reviewed.

The normative change must include golden vectors for profile identifiers; salt and salted-component hashes; all three component kinds; 23-slot local construction with zero, one, and multiple blanks, exact 23-nonblank acceptance, and 24-nonblank rejection without truncation; Pedersen openings and group sums for 6, 7, and 8 contributors; the two purpose-specific manifest verification keys and distinct key identifiers; the two 23-request PlayerCommit vectors and two 23-response vectors; wrong-vector and wrong-key request substitution; purpose-separated token encoding, finalization, and spent identifiers; authorized signature-submission encoding; signature-mailbox sequence zero and one; non-mutating invalid-delivery rejection; exact duplicate recognition before phase and expiry checks; authenticated equivocation behavior; shuffled-signature determinism; cross-profile, cross-round, cross-purpose, and retry rejection; and the selected unlinkable membership proof. OpalCrypto validation must additionally cover a complete eight-contributor attempt's 368 blind evaluations—184 under each purpose-specific key—increasing the current Mosaic batch proof from 184 without changing the public primitive contract.

The runtime gate remains false until production code proves lease provenance, local construction, membership verification, anonymous signature authorization and replay, authoritative previous-output resolution, failure-aware signing and commit ordering, durable recovery, Tor-only transport, app-owned broadcast approval, and independent protocol, cryptographic, side-channel, privacy, wallet-policy, and deployment review.

## 9. Approval Boundary

Explicit approval of A4-D1 through A4-D6 authorizes converting the proposal's deterministic parts into a versioned normative alpha.4 contract and implementation. It does not authorize inventing the membership proof, using a conductor-visible linkage fallback, spending real funds, opening paid infrastructure, or broadcasting a transaction. Those actions retain their separate review and operational gates.
