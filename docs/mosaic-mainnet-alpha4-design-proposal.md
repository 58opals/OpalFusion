# Mosaic Mainnet-Alpha.4 Design Record

Status: Accepted non-normative design record. Decisions A4-D1 through A4-D6 are incorporated into the normative [`Mosaic/0-opal-mainnet-alpha.4` profile](mosaic-mainnet-alpha-profile.md) and its golden vectors. The profile and source own the contract; this record retains rationale and rejected alternatives without independently authorizing runtime enablement, wallet integration, or deployment.

This record explains the accepted transition from the frozen `Mosaic/0-opal-mainnet-alpha.3` deterministic foundation to alpha.4's local material and standalone anonymous-signature admission contracts. It does not authorize mainnet spending, networking, broadcast, or a privacy claim.

## 1. Decision Summary

| Decision | Accepted design | Consequence |
|---|---|---|
| A4-D1: versioning | Advance the existing `.opalMainnetAlpha` selector to `Mosaic/0-opal-mainnet-alpha.4`; do not add a second public enum case | Alpha.3 bytes and persisted attempts become non-resumable; retry starts with completely fresh alpha.4 material |
| A4-D2: component salts | Use fresh 32-byte salts with alpha.4-domain-separated, round-bound hashes | Prevents cross-profile and cross-round reuse while preserving anonymous component bytes |
| A4-D3: local material proof | Implement exact lease-content-to-23-slot construction and contributor-local opening/inclusion validation | Proves deterministic derivation from a sealed lease value but leaves live wallet ownership, persistence, and liveness to OpalBase |
| A4-D4: component-bound authorization | Issue two component-bound blind credentials for every one of the 23 slots under separate attempt-exclusive RSA keys | Limits each anonymous component and optional BCH signature to exact one-time authority without encoding the contributor or real input count; privacy still depends on RSABSSA blindness and reviewed transport isolation |
| A4-D5: signature mailbox | Use a fresh anonymous sender key and a second sequence on the component's already admitted recipient mailbox | Avoids inventing an unfrozen mailbox-assignment document while keeping signature delivery separate from the component sender identity |
| A4-D6: honest-wallet safety boundary | Use the CashFusion-derived blind-authorization accounting invariant, contributor-local inclusion, unanimous transcript, and wallet-host validation model without adding a happy-path membership proof | Adds no conductor-visible contributor mapping, but explicitly accepts successful off-commitment components, reduced accountability, and unattributable aborts under the stated blindness, transport, timing, and collusion assumptions; a stronger unlinkable proof remains a future profile option |

## 2. Compatibility And Migration

The accepted profile, transport, transaction, and domain prefixes are respectively `Mosaic/0-opal-mainnet-alpha.4`, `nostr-tor/0-opal-mainnet-alpha.4`, `bch-mainnet-p2pkh-schnorr/0-opal-mainnet-alpha.4`, and exact UTF-8 `"Mosaic/0-opal-mainnet-alpha.4/" || suffix`. The existing Swift selector remains `.opalMainnetAlpha`; its computed contract now resolves to alpha.4.

Alpha.4 decoders reject every alpha.3 identifier and digest. Alpha.3 decoders reject alpha.4. No journal, reservation, output, salt, nonce, key, blind request, mailbox, acknowledgement, or partially signed transaction crosses the version boundary. Because mainnet-alpha has never had an enabled runtime driver, this is a fail-closed contract migration rather than a live-session compatibility promise.

The rejected alternative was a new public `.opalMainnetAlpha4` selector that retained alpha.3 indefinitely. That would preserve explicit historical selection but expand a public API for a profile that cannot run. The accepted design uses the smaller single-selector migration.

## 3. Salted Component Construction

For every one of the 23 contributor slots, generate an independent uniformly random 32-byte `salt32`, Pedersen nonce, component communication key, component authorization nonce, and signature authorization nonce. None may be reused by another slot, attempt, generation, round, purpose, or retry.

The frozen hashes are:

```text
saltCommitment32 = SHA256(domain("component-salt") || roundIdentifier32 || salt32)
saltedComponentDigest32 = SHA256(domain("salted-component") || roundIdentifier32 || salt32 || canonical(componentPayload))
```

`canonical(componentPayload)` is only the already-defined input, output, or blank payload encoding; it excludes the salt commitment, blind credentials, mailbox fields, contributor identity, and slot number. The anonymous component carries `saltCommitment32` and the payload. The grouped component commitment carries `saltedComponentDigest32`, its Pedersen amount commitment, and its communication public key.

Domain separation and round binding were selected instead of copying a bare CashFusion hash because this is a new versioned contract and cross-round material reuse must fail cryptographically. The alpha.4 tests pin every component kind and reject wrong domain, round, salt length, payload encoding, and trailing bytes.

## 4. Lease-To-Material Construction And Local Validation

The production material owner should construct exactly 23 slots from one live reservation lease: all selected inputs, all fresh outputs, then enough blanks to reach 23, with a deterministic private slot order that is shuffled before anonymous delivery. It must reject the lease without truncation or wallet progression when `inputs.count + outputs.count > 23`; exactly 23 nonblank components is valid and adds no blanks. Each input and output amount contribution follows the already frozen 141-byte input, 34-byte output, and roster-derived alpha.3 excess-share rules. The conductor remains non-contributing.

For each slot, the material owner stores the exact lease reference, attempt, generation, material identifier, round, component payload, salt, Pedersen nonce, amount commitment, component communication private key, both blind-request states, and mailbox binding. Secrets remain outside reducer state and must be erased at terminal disposition.

Contributor-local validation opens each locally retained Pedersen commitment, recomputes both hashes, proves that all 23 exact grouped commitments are present in the conductor's commitment set, proves that every local component is present exactly once in the component set, and binds the resulting transcript-inclusion validation to the same attempt, generation, material, contributor, and transcript. The existing sealed runtime inputs remain the only reducer authority.

This local proof does not let the conductor verify that an anonymous component came from one of the contributor-tagged grouped commitments. Revealing the salt, Pedersen opening, group index, or contributor identity to the conductor would create the linkage Mosaic is intended to hide and is therefore not an acceptable production fallback.

## 5. Component-Bound Purpose-Separated Blind Authorization

Each slot receives two independent RSABSSA credentials under two independently generated, attempt-exclusive RSA keys. The alpha.4 manifest replaces the singular blind-signing verification key with two ordered fields: the component-authorization verification key followed by the BCH-signature-authorization verification key. Their key identifiers must be distinct. Purpose values are exactly `0 = component` and `1 = BCH signature`.

`canonical(component)` below is the already-defined canonical component encoding containing its salt commitment and input, output, or blank payload. It excludes either authorization token and all mailbox metadata. The component credential is bound to those exact bytes. The signature credential is bound to the spent identifier of that component credential, which is known to the contributor before blinding, disclosed to the conductor when the component token is presented, and eligible as a signature binding only after that component is accepted:

```text
componentDigest32 =
  SHA256(domain("component-authorization/payload") || canonical(component))

componentAuthorizationInput =
  text(profileIdentifier || "/authorization/input") ||
  bytes(genesisHash32) ||
  bytes(roundIdentifier32) ||
  bytes(componentAuthorizationKeyIdentifier32) ||
  0 u8 ||
  bytes(componentAuthorizationNonce32) ||
  bytes(componentDigest32)

componentAuthorizationSpentIdentifier =
  SHA256(domain("authorization-spent") || componentAuthorizationInput)

signatureAuthorizationInput =
  text(profileIdentifier || "/authorization/input") ||
  bytes(genesisHash32) ||
  bytes(roundIdentifier32) ||
  bytes(signatureAuthorizationKeyIdentifier32) ||
  1 u8 ||
  bytes(signatureAuthorizationNonce32) ||
  bytes(componentAuthorizationSpentIdentifier)

signatureAuthorizationSpentIdentifier =
  SHA256(domain("authorization-spent") || signatureAuthorizationInput)
```

Purpose zero requires the component-authorization key identifier and `componentDigest32`. Purpose one requires the BCH-signature-authorization key identifier and one previously accepted `componentAuthorizationSpentIdentifier`. Any other purpose, key, or binding is invalid even when the underlying RSA signature verifies. These relationships are enforced when a contributor constructs and finalizes each request and again when an anonymous token is admitted. During issuance the conductor receives each blinded message but does not learn its authorization input; it enforces the two exact 23-request quotas and verifies the application-defined structure only when a token is presented.

The exact alpha.4 `PlayerCommit` field order is the existing round identifier, contributor identity, and grouped commitment, followed by a 23-entry component-request vector and then a 23-entry signature-request vector. Each request entry remains `slot u8 || blindedMessage256`, and each vector must contain slots `0...22` exactly once in ascending order. The conductor evaluates the component vector only with the component-authorization signing key and the signature vector only with the BCH-signature-authorization signing key. The retained blind-request state is bound to the exact component, explicit purpose-bearing authorization input, and required key above. Consequently, moving a blinded purpose-zero request into the signature vector yields a token under the wrong key and cannot mint usable authority, and the inverse fails identically.

The exact alpha.4 authorization-response set field order is the round identifier, contributor identity, PlayerCommit digest, a 23-entry component-response vector, and a 23-entry signature-response vector. Each response entry remains `slot u8 || blindSignature256`, and both vectors must contain slots `0...22` exactly once in ascending order. The addressed contributor finalizes each response only against the matching vector, slot, purpose-bearing input, retained blind-request state, and purpose-specific manifest key. A credential valid for one purpose is invalid for the other.

The exact alpha.4 authorization-token wire form is `roundIdentifier32 || keyIdentifier32 || purpose u8 || nonce32 || binding32 || messageRandomizer32 || signature256`. A component submission requires purpose zero, recomputes `componentDigest32` from the submitted component, and requires it to equal `binding32`. A BCH-signature submission requires purpose one and has exact inner field order `transcriptRoot32 || authorizationToken || inputIndex u32 || schnorrSignature64 || compressedPublicKey33`; its `binding32` must name the purpose-zero spent identifier accepted at sequence zero on the same mailbox. The surrounding anonymous envelope supplies and authenticates the common round and delivery metadata; the token round must equal it. Replay uses the purpose-specific spent identifier above, so the purpose and binding are part of the replay key.

Fixed 23-plus-23 issuance is recommended over issuing signature credentials only for input slots because the latter reveals each contributor's input count to the conductor during the control phase. It also avoids deriving signature authority from a component credential, which would make cross-purpose replay possible.

## 6. Anonymous BCH-Signature Delivery

After the complete acknowledgement set has been validated, each real input slot uses its purpose-1 credential to authorize exactly one `BCHSignatureSubmission`. Blank and output slots never submit a signature, but their unused purpose-1 credentials reveal nothing about which slots were inputs. Admission additionally requires that the bound sequence-zero component is an input, the input index identifies that exact component in the acknowledged transcript, the compressed public key matches it, and the signature verifies for the exact previous output and unsigned transaction.

The accepted delivery uses a new anonymous sender event key while retaining the exact recipient mailbox identity already bound to that component. A production adapter must additionally use a fresh Tor circuit. The component delivery consumes mailbox sequence zero; its optional BCH-signature delivery consumes sequence one. Admission authenticates the complete outer envelope and canonical payload, computes its exact record identity, and checks the accepted-record table first. A byte-identical authenticated record already accepted for that mailbox is idempotent even after phase advancement or expiry. A nonduplicate then passes the current recipient-mailbox, profile, round, phase, expiry, sequence-range, payload-shape, purpose-1 token, transcript-root, input-index, public-key, and signature-semantic checks without mutating replay state. Unauthenticated, stale, foreign-round, wrong-phase, expired, wrong-purpose, malformed, or otherwise invalid nonduplicate traffic is rejected without consuming the mailbox sequence, sender key, or token. Only an authenticated nonduplicate with a valid purpose-1 token that conflicts with an already accepted use of the same mailbox sequence, anonymous sender identity, or spent identifier is terminal equivocation. After all validation succeeds, the conductor atomically records the exact record, sequence, sender identity, and purpose-1 spent identifier before accepting the signature. A third mailbox sequence is rejected without mutating the attempt.

Reusing the recipient mailbox avoids inventing a second confidential mailbox-assignment message. It does create an intentional component-to-signature association, which is already necessary to bind the signature to that public input; it must not create a contributor-control association. The transport review must verify that the fresh sender key, timing policy, and circuit isolation prevent the two deliveries from exposing the contributor.

## 7. CashFusion-Derived Honest-Wallet Safety Boundary

Alpha.4 does not add a happy-path proof that lets the conductor verify which hidden grouped commitment an anonymous component opens. Instead, it uses the narrower CashFusion-derived safety structure:

- every honest peer accepts the canonical issuance stream only when it contains exactly 23 purpose-zero responses for each roster contributor, and the conductor publishes only after exactly `23 * contributorCount` uniquely authorized components have been accepted;
- the conductor validates token structure, uniqueness, component form, duplicate outpoints, aggregate transaction balance, and the exact fee before publishing the component set;
- every contributor opens and recomputes its own 23 grouped commitments, requires all of its exact components and commitments to appear once, independently derives the same unsigned transaction, and acknowledges the same transcript root;
- OpalBase requires the exact live reservation, expected local outputs, resolved previous outputs, roster-derived fee share, and transcript-bound transaction before signing only its reserved inputs with `SIGHASH_ALL | SIGHASH_FORKID`;
- completion requires one valid signature for every input and byte-exact revalidation of the complete transaction before reservation commit.

This deliberately leaves one integrity relation unproved to the conductor: a malicious contributor can spend one of its accounted credentials on a structurally valid component that does not open one of its published grouped tuples. Grouped commitments therefore constrain only the locally retained material that an honest contributor opens and verifies; they are not conductor-verifiable provenance for another contributor's anonymous components. Exact counts prevent an extra component from replacing an honest contributor's component without that contributor detecting omission. If the substituted private set remains globally balanced and passes every transaction, signature, transcript, and host check, the transaction can complete even though that contributor's published grouped tuples were not the source of its anonymous components. Otherwise the mismatch causes an abort. Neither outcome grants authority over an honest wallet, but the unused grouped commitments weaken integrity and may prevent blame from attributing the substitution. Unlike an authenticated omission, this mismatch can remain unattributable and repeatedly defeat an attempt; the accepted profile therefore carries a real accountability regression and permits successful off-commitment transactions. The normative profile and security model state this versioned boundary, while complete blame/accountability remains an unresolved runtime and production-release gate.

The 23-per-contributor issuance rule is a protocol and ledger invariant, not a cryptographic restriction on a malicious conductor: the conductor owns both RSA signing keys and can mint additional valid credentials. The exact aggregate count and every honest contributor's local inclusion checks prevent those extra credentials from silently displacing an honest component. A conductor can use them only by causing a detectable omission or by obtaining space through collusion with a contributor, which remains inside Mosaic's stated malicious-conductor and collusion threat model rather than becoming a stronger privacy claim.

The accepted profile prohibits sending a salt, Pedersen opening, group index, or published grouped communication private key to the conductor during the happy path. Those shortcuts would reveal the contributor-to-component mapping. A future profile may add a reviewed same-hidden-index proof over the salted payload, amount commitment, and communication-key relations if deployment evidence shows that happy-path commitment membership or stronger blame attribution justifies the substantial cryptographic and interoperability cost.

This choice follows the structure of the [CashFusion specification](https://github.com/cashshuffle/spec/blob/master/CASHFUSION.md), where blind signatures authorize exact covert component messages, fixed component counts and global fee checks gate signing, contributors verify local inclusion, and openings are reserved for blame. The [CashFusion audit](https://electroncash.org/fusionaudit.pdf) informs this tradeoff but does not audit Mosaic or support a Mosaic privacy/readiness claim. [RFC 9474](https://www.rfc-editor.org/rfc/rfc9474.html) supplies the blind-signature primitive; alpha.4 separately requires dedicated keys, high-entropy randomized inputs, exact application-message structure checks, and expected-key verification.

## 8. Evidence And Runtime Gates

The alpha.4 contract, local-material builder, component admission, and standalone signature-admission ledger are implemented while the mainnet driver remains disabled. Executable runtime work still requires the documented wallet-safety composition, authoritative signature semantics, mailbox transport, and independent review.

The Fusion evidence includes golden vectors for profile identifiers; salt and salted-component hashes; all three component kinds; 23-slot local construction with zero, one, and multiple blanks, exact 23-nonblank acceptance, and 24-nonblank rejection without truncation; Pedersen openings and group sums; exact authorized totals of 138, 161, and 184; distinct purpose keys; two request and response vectors; component and signature bindings; purpose-separated token encoding, finalization, and spent identifiers; authorized signature-submission encoding; mailbox sequences zero and one; non-mutating invalid-delivery rejection; exact duplicate recognition; equivocation behavior; shuffled-signature determinism; cross-profile, cross-round, cross-purpose, and retry rejection; and one explicit structurally valid, globally balanced nonmember-substitution vector. OpalCrypto validation must still cover a complete eight-contributor attempt's 368 blind evaluations—184 under each purpose-specific key—without changing the public primitive contract.

The runtime gate remains false until production code proves lease provenance, local construction and inclusion, exact component-bound authorization, anonymous signature authorization and replay, aggregate count/balance/fee validation, authoritative previous-output resolution, failure-aware signing and commit ordering, durable recovery, Tor-only transport, app-owned broadcast approval, and independent protocol, cryptographic, side-channel, privacy, wallet-policy, and deployment review.

## 9. Decision Boundary

Approval of A4-D1 through A4-D6 has been incorporated into the versioned normative alpha.4 contract and implementation. A4-D6 specifically records that grouped commitments constrain honest contributors' locally verified material but do not prove another contributor's anonymous component provenance; a malicious contributor may complete with a different valid, balanced component set or cause an unattributable abort. The decision does not authorize a conductor-visible linkage fallback, a Mosaic privacy or production-readiness claim, spending real funds, opening paid infrastructure, or broadcasting a transaction. Those actions retain their separate review and operational gates.
