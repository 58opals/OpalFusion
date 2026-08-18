# Mosaic Mainnet-Alpha Private-Deployment Profile

Status: Proposed frozen private-deployment supplement pending explicit G0 semantic approval. Private-deployment identifier: `nostr-tor/0-opal-mainnet-alpha-private-deployment.1`.

This document proposes exact values for the previously unresolved private-deployment contract decisions needed to compose `Mosaic/0-opal-mainnet-alpha.4` with `nostr-tor/0-opal-mainnet-alpha.5` in one reviewed macOS alpha. Adoption remains pending the explicit semantic approval recorded by the roadmap; until then, these values are implemented proposal bytes rather than an accepted deployment decision. The proposal does not change any alpha.4 protocol byte or alpha.5 post-manifest transport byte. The [Mosaic Mainnet-Alpha Profile](mosaic-mainnet-alpha-profile.md) remains authoritative for those frozen identifiers, the [Mosaic Security Model](mosaic-security-model.md) remains authoritative for claims and threats, and this supplement is authoritative only for the separately versioned discovery, pre-manifest, deployment-policy, and cross-layer recovery proposal below. A change to any field, domain, event kind, timing value, signer rule, endpoint rule, or canonical order in this supplement requires a new private-deployment identifier and separate approval.

The public Mosaic session, generic mainnet runtime driver, public release lane, broadcast permission, and P0 through P4 remain disabled. No provision in this supplement authorizes a relay, Tor, Fulcrum, or value-moving external run.

## 1. Claims, Admission, And Accountability

The alpha.4 off-commitment accountability tradeoff is accepted unchanged: a valid authorized component is not proven to open a member of a contributor-tagged grouped commitment. Adding such a proof requires a new protocol profile identifier and separate approval.

Discovery requires a valid one-time BIP340 identity, a canonical availability beacon, and at least 20 leading zero bits in the beacon work digest. This work is an admission throttle only. It is not Sybil resistance, an anonymity measure, or evidence that selected candidates are independent people, devices, wallets, networks, or operators. Selection oversubscribes to seven through nine candidates and the existing commit-reveal election chooses exactly one conductor and six through eight contributors. Repeated selective aborts and candidate capture remain residual risks.

Three distinct configured relay-operator digests assert only that the application reviewed three different registry labels. They do not prove corporate, jurisdictional, infrastructure, route, or Tor-circuit independence. Until G4 evidence exists, the only permitted readiness wording remains “deterministic mainnet-alpha contract foundation.”

## 2. Canonical Primitives And Version Isolation

Canonical integers, byte strings, printable-ASCII text, vectors, fixed-width values, ordering, strict decoding, and trailing-byte rejection use Section 3 of the mainnet-alpha profile. Every canonical document introduced by this supplement includes the exact private-deployment identifier before its deployment-specific fields, even when it also includes the alpha.4 protocol identifier and mainnet genesis hash. Every private-deployment digest therefore commits the identifier either directly or through identifier-bearing canonical bytes. An implementation must reject identifier drift before installing discovery, roster, manifest, transport, wallet, recovery, or broadcast state.

Unless a formula below says otherwise, `deploymentHash(suffix, fields...)` is SHA-256 over exact UTF-8 `"Mosaic/0-opal-mainnet-alpha.4/" || suffix || fields...`. Identifier-bearing canonical documents remove ambiguity between private-deployment versions; this domain addition does not alter any pre-existing alpha.4 hash.

### 2.1 Canonical Schema And Domain Registry

In this registry, `D` is the raw UTF-8 private-deployment identifier, `P` is the raw UTF-8 alpha.4 protocol identifier, `G` is the 32-byte mainnet genesis hash, `text(x)` is `u32 byteCount || printableASCII(x)`, `bytes(x)` is `u32 byteCount || x`, and `vector(x...)` is `u32 memberCount || canonical members`. Fixed-size fields have no length prefix. Every integer is unsigned big-endian. `H(s, fields...)` means `deploymentHash(s, fields...)`. The direct `D` hash field and the `text(D)` inside each canonical document are both mandatory; removing either is contract drift.

| Name | Exact canonical bytes or digest input |
| --- | --- |
| Opaque pool document | `text(D) || text(P) || G || opaquePoolIdentifier32`; digest `H("private-deployment/opaque-pool", D, canonicalDocument)` |
| Relay operator identity | `H("private-deployment/relay-operator-registry-label", D, normalizedRegistryLabelASCII)` |
| Relay registration | `text(D) || text(normalizedEndpoint) || operatorDigest32 || requiresNIP42 u8 || requiresProofOfWork u8` |
| Relay set | `text(D) || text(P) || G || vector(bytes(registration)...)`; digest `H("private-deployment/relay-set", D, canonicalRelaySet)` |
| Availability core | `text(D) || text(P) || G || epochStart u64 || opaquePoolIdentifier32 || discoveryIdentity32 || relaySetDigest32 || proofOfWorkNonce u64 || expiry u64`; work digest `H("private-deployment/availability-beacon-work", D, canonicalCore)` |
| Availability body and document | Body `text(D) || bytes(canonicalCore) || actualLeadingZeroBitCount u16`; signature digest `H("private-deployment/availability-beacon-signature", D, canonicalBody)`; document `text(D) || bytes(canonicalBody) || discoverySignature64` |
| Candidate set | `text(D) || vector(bytes(selectedAvailabilityBody)...)`; digest `H("private-deployment/candidate-set", D, canonicalCandidateSet)` |
| Candidate-set acknowledgement | Body `text(D) || text(P) || G || epochStart u64 || candidateSetDigest32 || signerDiscoveryIdentity32 || expiry u64`; signature digest `H("private-deployment/candidate-set-acknowledgement", D, canonicalBody)`; document `text(D) || bytes(canonicalBody) || discoverySignature64` |
| Complete acknowledgement set | `text(D) || vector(bytes(canonicalAcknowledgement)...)` in discovery-key order |
| Candidate admission | Body `text(D) || text(P) || G || epochStart u64 || candidateSetDigest32 || discoveryIdentity32 || controlIdentity32 || expiry u64`; signature digest `H("private-deployment/candidate-admission", D, canonicalBody)`; document `text(D) || bytes(canonicalBody) || discoverySignature64 || controlSignature64` |
| Control roster | `text(D) || vector(bytes(canonicalAdmission)...)` in discovery-key order; digest `H("private-deployment/control-roster", D, candidateSetDigest32, canonicalAdmissions)` |
| Contributor nonce allocation | `text(D) || text(P) || G || controlRosterDigest32 || vector(contributorControlIdentity32 || publicSource32...)` in contributor-key order; digest `H("private-deployment/contributor-nonce-allocation", D, canonicalDocument)` |
| Role commitment | `text(D) || candidateControlIdentity32 || controlRosterDigest32 || commitment32` |
| Role reveal | `text(D) || candidateControlIdentity32 || controlRosterDigest32 || randomness32` |
| Manifest proposal | `text(D) || bytes(alpha4RoundManifestCore)`; proposal digest `H("private-deployment/manifest-proposal", D, canonicalProposal)` and signature binding `(alpha4RoundIdentifier32, proposalDigest32)` |
| Manifest signature | `text(D) || signerControlIdentity32 || BIP340Signature64`; the signature remains over the unchanged alpha.4 round identifier |
| Nostr payload | `text(D) || text(P) || G || epochStart u64 || payloadKind u8 || signerRole u8 || signerIdentity32 || expiry u64 || bytes(body)` |
| Abort context | `text(D) || contextKind u8 || contextDigest32`; discovery digest is `H("private-deployment/discovery-context", D, epochStart u64 || opaquePoolDigest32 || relaySetDigest32)`, candidate-set and control-roster contexts use their existing digest directly, manifest context is `H("private-deployment/manifest-context", D, roundIdentifier32, exactProposalOrCompleteManifestDigest32)` |
| Abort document | `text(D) || text(P) || G || epochStart u64 || phase u8 || bytes(canonicalAbortContext) || abortReason u8` |
| Completion document | `text(D) || text(P) || G || epochStart u64 || roundIdentifier32 || completeTransactionPayloadDigest32` |

Decoders require exact vector order, exact counts, known enum values, canonical nested bytes, complete input consumption, and no trailing bytes. The canonical candidate set contains signed beacon bodies rather than signatures; when more than one valid signature represents the same core, selection retains the lexicographically lowest complete beacon document so the in-memory validation value is also arrival-order invariant.

### 2.2 Canonical Enum Registry

| Enum | Exact values |
| --- | --- |
| Payload kind | availability beacon `0`; candidate-set acknowledgement `1`; candidate admission `2`; role commitment `3`; role reveal `4`; contributor nonce allocation `5`; manifest proposal `6`; manifest signature `7`; abort `8`; completion `9` |
| Signer role | discovery `0`; control `1`; conductor `2` |
| Abort context kind | discovery `0`; candidate set `1`; control roster `2`; manifest `3` |
| Attempt phase | discovery `0`; candidate-set agreement `1`; control-roster agreement `2`; role selection `3`; manifest agreement `4`; wallet reservation `5`; grouped commitment `6`; anonymous component submission `7`; transcript agreement `8`; BCH signing `9` |
| Abort reason | timeout `0`; equivocation `1`; invalid authenticated message `2`; missing required participant `3` |

Unknown, negative, out-of-range, cross-selector, or cross-context values are invalid. These values version only this private-deployment supplement; they do not assign or change any alpha.4 or alpha.5 enum value.

## 3. Fixed Policy And Time

One discovery epoch is 300 Unix seconds and starts at a Unix second divisible by 300. Given `epochStart`, exact pre-manifest boundaries are:

| Boundary | Unix second |
| --- | --- |
| Availability beacon cutoff | `epochStart + 60` |
| Candidate-set agreement | `epochStart + 90` |
| Control-roster agreement | `epochStart + 120` |
| Role commitment | `epochStart + 150` |
| Role reveal | `epochStart + 180` |
| Manifest agreement and post-manifest `phaseStart` | `epochStart + 240` |
| Discovery epoch end and pre-manifest abort expiry | `epochStart + 300` |

Given the exact manifest `phaseStart`, post-manifest boundaries are wallet reservation `+60`, grouped commitment `+120`, anonymous component submission `+240`, transcript agreement `+300`, and BCH signing `+360`. The OpalBase reservation lease expires exactly at the BCH-signing deadline. Unsigned overflow, an unaligned epoch, a manifest whose `phaseStart` is not the corresponding `epochStart + 240`, or any different deadline vector is invalid.

The alpha.4 transaction policy remains exactly one satoshi per estimated final signed byte, one through two satoshis of contributor excess according to the frozen roster allocation, ten satoshis of fixed transaction overhead, version 2, lock time zero, sequence `0xffffffff`, standard P2PKH only, and Schnorr sighash byte `0x41`.

## 4. Pool And Relay Documents

The application generates one fresh 32-byte opaque pool identifier independently of wallet keys, amounts, outpoints, scripts, addresses, or reusable wallet identifiers and prevents its reuse across concurrently active discovery contexts. The canonical opaque-pool document is private-deployment identifier text, alpha.4 protocol text, mainnet genesis hash32, and opaque pool identifier32. Its digest is `deploymentHash("private-deployment/opaque-pool", privateDeploymentIdentifier || canonicalDocument)`.

A relay endpoint normalizes to exact lowercase ASCII `wss://dns-host/`. An explicit port is permitted only when it is decimal `443` and normalizes away. User information, non-root paths, query, fragment, IP literals, bracketed literals, percent notation, non-ASCII input, empty labels, single-label hosts, labels longer than 63 bytes, a host longer than 253 bytes, invalid DNS characters, and non-443 ports are invalid. A relay that requires NIP-42 authentication or relay proof of work is unavailable for this deployment; the application must not invent credentials or work parameters.

For each relay, the application supplies one reviewed printable-ASCII registry label of one through 128 bytes with no surrounding space. ASCII letters are lowercased, and the canonical operator identity is `deploymentHash("private-deployment/relay-operator-registry-label", privateDeploymentIdentifier || normalizedLabel)`. The registry label itself is not transmitted in the relay document. A registration contains private-deployment identifier text, normalized endpoint text, operator digest32, `requiresNIP42 = false`, and `requiresProofOfWork = false`.

A relay-set document contains private-deployment identifier text, alpha.4 protocol text, mainnet genesis hash32, and exactly three registrations sorted by canonical registration bytes. Endpoints and operator digests must each be unique. `relaySetDigest = deploymentHash("private-deployment/relay-set", privateDeploymentIdentifier || canonicalRelaySet)`. The application must bind every manifest endpoint identifier to the exact reviewed relay set and to one concrete Tor-only capability; that execution proof belongs to G2.

## 5. Availability And Candidate-Set Agreement

An availability core contains private-deployment identifier text, alpha.4 protocol text, mainnet genesis hash32, aligned discovery epoch start, opaque pool identifier32, one-time discovery x-only key32, relay-set digest32, proof-of-work nonce `u64`, and beacon expiry equal to the beacon cutoff. `workDigest = deploymentHash("private-deployment/availability-beacon-work", privateDeploymentIdentifier || canonicalCore)`. The exact leading-zero count is encoded as `u16`; it must equal the digest’s actual leading-zero count and be at least 20. The discovery key signs `deploymentHash("private-deployment/availability-beacon-signature", privateDeploymentIdentifier || canonicalBody)`, where the body is `text(privateDeploymentIdentifier) || bytes(core) || leadingZeroCount u16`.

For one epoch, pool, and relay set, beacons are keyed by discovery identity. Different core bytes under one identity are equivocation and abort the attempt. Multiple valid signatures over the same core canonicalize to the lexicographically lowest full signed beacon so relay arrival order cannot change the selected value. Valid identities sort by work digest and then discovery key; the first nine are selected, and fewer than seven is invalid. The candidate-set bytes are `text(privateDeploymentIdentifier) || vector(bytes(selectedBeaconBody)...)` in that order and `candidateSetDigest = deploymentHash("private-deployment/candidate-set", privateDeploymentIdentifier || canonicalCandidateSet)`.

Every selected discovery identity signs one candidate-set acknowledgement containing the private-deployment identifier, alpha.4 protocol identifier, mainnet genesis hash, epoch start, candidate-set digest, signer discovery key, and expiry at candidate-set agreement. The complete acknowledgement set covers every selected identity exactly once in discovery-key order. Missing, extra, duplicate, unknown, differently bound, expired, invalidly signed, or noncanonical entries are invalid.

Each selected candidate then publishes one dual-signed admission binding its discovery identity to a distinct one-time control identity. The admission contains the private-deployment identifier, alpha.4 protocol identifier, mainnet genesis hash, epoch start, candidate-set digest, discovery key, control key, and expiry at control-roster agreement. Both keys sign the same deployment-domain digest. Discovery and control keys must be globally disjoint across the complete roster, not merely distinct within one admission. The control-roster digest binds the candidate-set digest and the discovery-key-sorted complete admission vector. The existing role-commitment and role-reveal bodies additionally carry the private-deployment identifier and retain their frozen alpha.4 role formulas.

## 6. Contributor Nonce Allocation And Manifest Agreement

After role election, the conductor’s application generates one distinct 32-byte public allocation source for every contributor. Each source must be independent of wallet material and must not encode an amount, outpoint, address, script, wallet identifier, salt, secret nonce, or signing key. These public sources do not replace the production material owner’s fresh private entropy.

The canonical allocation document contains private-deployment identifier text, alpha.4 protocol text, mainnet genesis hash32, control-roster digest32, and a contributor-control-key-sorted vector of `contributorControlKey32 || publicSource32` covering every contributor exactly once. Its digest is `deploymentHash("private-deployment/contributor-nonce-allocation", privateDeploymentIdentifier || canonicalDocument)`. The role-elected conductor publishes the complete document on private event kind `26546`; every peer validates the conductor, roster, ordering, uniqueness, epoch, and manifest-agreement expiry before accepting it. There is no side channel. A peer signs the later manifest only when the proposed allocation digest equals the locally accepted document, so the complete manifest signatures are the allocation acknowledgement.

The conductor publishes the manifest proposal only after the exact candidate set, acknowledgement set, control roster, role election, opaque pool, relay set, allocation document, and deadline schedule are locally available. Every peer validates all of those inputs before signing. The manifest’s `phaseStart` must equal the discovery epoch’s manifest-agreement boundary, and its post-manifest deadlines and reservation lease must equal Section 3. Manifest proposal and signature bodies carry the private-deployment identifier outside the unchanged alpha.4 `RoundManifestCore`; a manifest-signature sender role is derived from the validated roster and cannot be caller-labeled.

## 7. Private Nostr Mapping

The private-deployment mapping uses signed NIP-01 ephemeral events with exactly one tag `[["d", "nostr-tor/0-opal-mainnet-alpha-private-deployment.1"]]`. Content is the lowercase hexadecimal encoding of one canonical payload with no padding or alternate case. The payload contains private-deployment identifier text, alpha.4 protocol text, mainnet genesis hash32, discovery epoch start `u64`, payload kind `u8`, signer role `u8`, signer x-only key32, expiry `u64`, and `bytes(body)`. Bodies are nonempty and at most 65,536 bytes. Event creation time must be at or after the epoch start, at or before the signed expiry, and not in the receiver’s future; current time must not exceed expiry.

| Event kind | Payload | Required signer |
| --- | --- | --- |
| `26540` | Availability beacon | Beacon discovery identity |
| `26541` | Candidate-set acknowledgement | Selected discovery identity |
| `26542` | Candidate admission | Admitted discovery identity; body also carries the valid control signature |
| `26543` | Role commitment | Validated control-roster member |
| `26544` | Role reveal | Validated control-roster member |
| `26545` | Manifest proposal or manifest signature | Actual conductor for a proposal; actual roster role derived for a signature |
| `26546` | Complete contributor nonce allocation | Actual conductor |
| `26547` | Abort | Phase-specific recognized participant from Section 8 |
| `26548` | Completion | Actual manifest conductor |

Nostr event identifiers and BIP340 signatures are validated by the existing strict event constructor/decoder. Selector, kind, tag, signer identity, actual signer role, epoch, expiry, body kind, inner signer, canonical hex, and body-specific context must all match before a typed payload exists. These ephemeral discovery events are not alpha.5 NIP-59 post-manifest envelopes and do not alter alpha.5 kinds, padding, timestamps, tags, replay, or relay quorum.

## 8. Abort And Completion

An abort body contains the private-deployment identifier, alpha.4 protocol identifier, mainnet genesis hash, epoch start, reducer phase, exact latest locally agreed context kind and digest, and canonical abort reason. A receiver accepts it only when the signed phase and full context digest equal its own current phase and context and the signer is derived from current validated state: the exact beacon identity for discovery; a selected discovery identity during candidate-set or control-roster agreement; a validated control-roster member during role selection; an actual roster member and role derived from the exact validated proposal during manifest agreement; and an actual roster member and role derived from the matching complete signed manifest during any post-manifest phase. Manifest-agreement authority does not require a complete manifest, so a missing manifest signature can still produce an authenticated abort. Premanifest aborts expire at epoch end. Post-manifest aborts expire at the manifest BCH-signing deadline. An abort is a terminal notice for that exact attempt only; it cannot roll back or terminate a different context.

A completion body contains the private-deployment identifier, alpha.4 protocol identifier, mainnet genesis hash, epoch start, round identifier32, and complete-transaction digest32. Only the actual conductor of the matching complete signed manifest may sign it, its expiry is exactly the BCH-signing deadline, and a receiver accepts it only against the exact complete transaction after previous-output-backed validation. An unsigned manifest validation or structurally parsed transaction payload is insufficient. Completion is not broadcast permission, network acceptance, confirmation, or wallet commit authority.

## 9. Cross-Layer Recovery Decisions

The application owns one encrypted, atomically replaced outer attempt record containing the exact OpalFusion runtime/publication state, OpalBase wallet disposition, transport state, and minimum recoverable attempt material under one revision. Independent package files must not be treated as an atomic attempt. Keychain-backed key and rollback anchors, file and directory synchronization, cataloging, cross-process exclusion, and terminal erasure remain G1 application obligations.

Durable missing-input tombstones are part of that application-owned outer record, not an OpalBase or OpalFusion store. An ambiguous OpalBase locally-signed or commit-intent recovery prefix may classify an absent selected input as removed by this exact attempt only when one authenticated inventory/tombstone snapshot binds the outer-record revision, wallet reservation UUID and generation, Fusion attempt, generation, and material identifiers, the exact outpoint and selected-input payload digest, and the exact committed transaction hash. The application must compare-and-replace and read back that snapshot with wallet inventory, enumerate it at startup, anchor rollback and deletion detection, exclude concurrent processes, and retain it through composed terminal cleanup. Missing, unknown, stale, tampered, extra, duplicate, rolled-back, deleted, or outcome-uncertain evidence remains quarantined and fail-closed. An authenticated OpalBase committed record remains the package-owned proof that selected-input absence is the required post-commit condition; it is not proof of application durability or readiness.

A recovered signing intent without durable locally signed bytes aborts and releases; it never reconstructs material or signs again. A recovered locally signed state uses the exact stored signed bytes to finish idempotent commit; it never signs again. An ambiguous broadcast intent first reconciles exact transaction presence through the network-attested chain client and performs no dispatch while presence is unknown. Broadcast requires one durable cross-process owner, and terminal material is retained until the wallet has reached its exact chain disposition. Corruption, rollback, deletion, stale ownership, source loss, or uncertain state keeps affected inputs quarantined and cannot enable signing or broadcast.

These decisions define the required G1 and G5 behavior; this supplement does not claim their implementation or evidence.

## 10. Ownership, Disable, And Non-Proofs

OpalFusion owns the canonical documents, phase semantics, private mapping, runtime restoration semantics, and transport behavior. OpalBase owns wallet selection, reservations, signing, recovery execution, previous-output validation, approval, broadcast, and chain reconciliation. SwiftFulcrum owns chain-client correctness. OpalCrypto owns primitives. The Wallet application owns durable persistence, Keychain integration, Tor/relay provisioning, lifecycle supervision, user controls, cross-process ownership, and policy. OpalDiagnostics may record only approved privacy-safe state and error categories.

Disable is structural: `.opalMainnetAlpha` remains nondefault, the generic `RuntimeSessionDriver` rejects it, the Wallet application must keep the private feature disabled unless its exact dependency and policy record is accepted, and no public Mosaic session or public release claim may be added. Rollback is to disable the private feature, stop discovery and relay work, preserve quarantine and recovery evidence, reconcile any approved broadcast through the exact chain client, and erase attempt material only after terminal wallet disposition.

This supplement does not prove durable storage, key erasure, runtime restoration, concrete Tor routing, relay delivery, circuit or operator independence, reconnect, timing privacy, traffic-analysis resistance, anonymity, Sybil resistance, application integration, broadcast exclusion, chain reconciliation, external review, canary safety, mainnet readiness, production readiness, or permission to use real funds.
