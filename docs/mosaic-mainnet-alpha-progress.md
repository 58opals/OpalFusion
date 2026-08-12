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
| 6 | Private execution gate | The owner-provisioned path rejects foreign bootstrap, role substitution, and a second claim before constructing ingress and the specialized driver. The sole-constructor stop condition remains open because fan-in still exposes an internal raw route-group initializer for component tests. | `6884256` |

## Ownership

| Concern | Authority |
| --- | --- |
| Phase semantics | OpalFusion attempt/runtime reducers and the selected contributor or conductor coordinator. |
| Admission and replay | OpalFusion `AdmissionLedger` plus the post-manifest admission journal for accepted replay facts. |
| Wallet lifecycle | OpalBase host actor and wallet attempt journal; OpalFusion returns exact release, commit, or recovery requirements but does not persist wallet recovery. |
| Outbound publication | OpalFusion attempt transport owner, control/anonymous bridges, batch publishers, and one-shot relay publisher over injected routes. |
| Inbound fan-in | Intended production composition uses the owner-issued inbound provisioning value; fan-in and ingress own subscription startup, bounded serialization, recipient authentication, and typed delivery. |
| Cryptography | OpalCrypto supplies BCH, NIP-44, Pedersen, and RSABSSA primitives without phase, wallet, transport, or broadcast authority. |

## Package Boundary Assessment

The dependency direction is acyclic: OpalBase depends on OpalFusion and OpalCrypto, while OpalFusion depends on OpalCrypto and OpalCrypto has no upward dependency. OpalFusion defines the protocol-required host capabilities, OpalBase implements them with independent wallet validation and durable intent, and OpalCrypto remains a computation-focused leaf.

The boundary shape is sound, but live enablement still requires an exact cross-repository integration-contract identifier instead of relying indefinitely on the `.opalMainnetAlpha` enum case across moving `develop` dependencies, a network-attested transaction client above the existing OpalBase broadcast coordinator, and an authenticated durable codec/store/loader for wallet and runtime recovery. OpalFusion's single Swift target also means an `internal` test-convenience constructor is callable by future production composition code, which is why the raw fan-in path is a real authority gap rather than merely a test detail.

## Validation Lanes

The latest bounded validation passed `swift build` in 3.04 seconds, `swift test list` with a 6.51-second build phase, `swift test --skip-build --filter MosaicMainnetAlphaExecutionGateValidator` with 1/1 test passing in 14.273 seconds, and `git diff --check`. The focused execution-gate filter does not generate RSA authorization evaluators.

The serialized `./scripts/run-validation-loop.sh mosaic-rehearsal` lane remains the intentionally slow milestone proof because it generates real RSABSSA signing keys. It was not rerun during the final fast-gate slice.

## Open Gates

1. Make owner-issued inbound provisioning the sole module-internal runtime construction authority and make route adoption failure-safe, while retaining RSA-free fan-in validation through a non-constructing test seam. Stop when no raw route-group initializer can create ingress or the mainnet runtime, every failure after route transfer closes or safely returns the transferred routes, and the focused RSA-free filter still passes within its budget.
2. Supply authenticated recipient distribution, encrypted persistence, authoritative relay selection, concrete Tor route and isolation proof, acknowledgement persistence, reconnect policy, and complete runtime/coordinator crash restoration. Stop at a durable fresh-process recovery proof with no replayed coordinator or wallet effect.
3. Add app-owned public composition only after independent protocol and security review. Preserve the private `OpalFusion.Session` initializer and disabled generic mainnet driver until that review explicitly authorizes a public execution surface.
4. Validate real wallet and node integration on BCH mainnet with explicit user approval and the existing OpalBase broadcast gates. Stop before value movement unless the app has persisted approval and broadcast intent for the exact committed candidate.

No next implementation slice begins from this record.
