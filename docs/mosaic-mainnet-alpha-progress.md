# Mosaic Mainnet-Alpha Progress

Status date: 2026-08-12. This is a non-normative implementation record; the protocol profile and security model remain authoritative.

## Current Claim

The private scaffold now composes the minimum roster of six contributors and one conductor, preserves one authoritative wallet lifecycle, journals semantically admitted replay facts before effects, owns attempt-scoped transport provisioning, and reaches exact in-memory host commit through the real-cryptography rehearsal path. A separate RSA-free filter provides focused construction and lifecycle feedback.

This is not a live BCH mainnet engine. No public Mosaic session, concrete Tor or relay deployment, durable runtime restoration, wallet application composition, network broadcast, or public-lane promotion is enabled.

## Completed Slices

| Rank | Slice | Result | Local evidence |
| --- | --- | --- | --- |
| 1 | Minimum-roster composition | Six contributors plus one non-contributing conductor compose through fan-in, ingress, role selection, and shutdown without wallet or RSA signing authority. | `3502472` |
| 2 | Lifecycle ownership | OpalFusion keeps one pending disposition; OpalBase keeps one wallet lifecycle enum and one write-ahead journal authority for release, signing, commit, recovery, and broadcast facts. | `2824ea2`, OpalBase `efc69e1` |
| 3 | Admission replay | One attempt-bound journal records only semantically accepted control and anonymous replay facts before coordinator effects; restored partial runtime state fails closed. | `79c366b` |
| 4 | Attempt transport provisioning | One peer-local owner provisions mailbox route groups, rejects local capability reuse, and can mint one role-complete inbound provisioning value. | `1fe3380` |
| 5 | Private rehearsal | The explicitly slow real-RSABSSA rehearsal covers conductor authorization and contributor BCH signing through exact host commit without wallet, relay, Tor, node, or broadcast access. | `70ba317` |
| 6 | Private execution gate | Owner provisioning is the sole runtime-construction authority. Fan-in alone requests the one claim, passes its immutable token through ingress to the specialized driver, rejects substitution or reuse, and closes transferred routes after construction failure. Pure route validation and an inert endpoint keep component feedback RSA-free without another runtime constructor. | `6884256`, current cleanup |

## Ownership

| Concern | Authority |
| --- | --- |
| Phase semantics | OpalFusion attempt/runtime reducers and the selected contributor or conductor coordinator. |
| Admission and replay | OpalFusion `AdmissionLedger` plus the post-manifest admission journal for accepted replay facts. |
| Wallet lifecycle | OpalBase host actor and wallet attempt journal; OpalFusion returns exact release, commit, or recovery requirements but does not persist wallet recovery. |
| Outbound publication | OpalFusion attempt transport owner, control/anonymous bridges, batch publishers, and one-shot relay publisher over injected routes. |
| Inbound fan-in | The attempt transport owner issues one role-complete provisioning value and owns its single claim; fan-in, ingress, and the specialized driver consume the resulting immutable token while fan-in owns subscription startup, bounded serialization, failure rollback, and drain. |
| Cryptography | OpalCrypto supplies BCH, NIP-44, Pedersen, and RSABSSA primitives without phase, wallet, transport, or broadcast authority. |

## Package Boundary Assessment

The dependency direction is acyclic: OpalBase depends on OpalFusion and OpalCrypto, while OpalFusion depends on OpalCrypto and OpalCrypto has no upward dependency. OpalFusion defines the protocol-required host capabilities, OpalBase implements them with independent wallet validation and durable intent, and OpalCrypto remains a computation-focused leaf.

The boundary shape is sound, but live enablement still requires exact enforcement of the existing versioned cross-repository profile pair instead of relying indefinitely on the `.opalMainnetAlpha` enum case across moving `develop` dependencies, a network-attested transaction client above the existing OpalBase broadcast coordinator, and an authenticated durable codec/store/loader for wallet and runtime recovery. OpalFusion's single Swift target still exposes internal types across source files, but no internal caller can mint the fan-in request plus claimed runtime token outside the owner-provisioned path.

## Validation Lanes

The fast structural lane is `swift test --skip-build --filter MosaicMainnetAlphaPostManifestRelayFanInRouteValidationValidator`; it has no dependency on the shared Mosaic mainnet fixture or an authorization evaluator. The owner-authorized `MosaicMainnetAlphaExecutionGateValidator` uses only embedded public verification keys and likewise does not generate RSA signing keys.

The serialized `./scripts/run-validation-loop.sh mosaic-rehearsal` lane remains the intentionally slow milestone proof because it generates real RSABSSA signing keys. It was not rerun during the final fast-gate slice.

## Open Gates

1. Enforce the existing exact profile and transaction-profile identifier pair at the OpalBase integration boundary. Stop when dependency/profile drift fails before wallet or recovery mutation and a deterministic focused policy filter passes.
2. Add authenticated durable recovery codec/store/loading boundaries and a fresh-process proof that recovery never repeats material construction, signing, release, commit, approval, or broadcast intent. Stop when corrupted, substituted, or incompatible records fail closed and one exact recoverable action is reconstructed.
3. Require a network-attested transaction client above the existing approval and persisted-intent gates. Stop when a mismatched network client cannot receive transaction bytes and no default or test path broadcasts.
4. Remove only remaining module-boundary debt that materially weakens these authorities. Stop when the authority graph has no alternate constructor or duplicated lifecycle owner; do not reorganize unrelated protocol code.
