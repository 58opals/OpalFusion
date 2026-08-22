# Mosaic G4 Independent Review Packet — 2026-08-23

Status: ready for independent reviewer assignment; no review lane is complete and no G4 disposition is implied.

## Purpose

This packet freezes the private-alpha review target, separates the required review lanes, maps authoritative specifications to exact first-party source and evidence, states known non-proofs before review begins, and defines the reviewer deliverable needed by the G4 findings register. It is a coordination artifact, not an audit, approval, release record, anonymity claim, or substitute for independent work.

Reviewers may cover more than one lane only when they declare the relevant expertise, relationship to the implementation owners, prior design or implementation participation, financial or organizational conflicts, and the exact lanes covered. An implementation owner may answer questions and remediate findings but cannot provide the independent disposition for their own work.

## Frozen Review Target

| Repository or artifact | Exact revision | Review role |
| --- | --- | --- |
| OpalCrypto | `23425db04075a48405d65cf6a3e2254911e626eb` | Owned cryptographic calculation, recoverable RFC 9474 request state, Pedersen operations, authenticated encryption, key-domain types, and constant-time helpers |
| OpalFusion runtime | `79ba5f91449b2c0d5cd6ec73c38fafd58cae0b46` | Frozen private-alpha protocol, transport, bootstrap, restoration, exact-host, and terminal-recovery implementation consumed by OpalBase |
| OpalBase | `35709a24fa3122c55181d93c79745a7018d1fc31` | Sole Wallet-facing runtime facade, wallet reservation and transaction validation, journal recovery, guarded broadcast, and chain-policy authority |
| SwiftFulcrum | `24b44bb2458822d14121dfbd57321fda7ae539ea` | Exact graph member and future isolated chain-client boundary; no G5 live-chain proof is claimed |
| OpalDiagnostics | `7cd2e383309821e01903077c1e534174f9c8a964` | First-party typed diagnostics and privacy-classification foundation |
| Wallet production source | `6fcfca789087f77ec556b22feec37e7b7226ad1d` | Sole application session owner, authenticated persistence, Keychain custody, concrete disabled transport, recovery, and aggregate observability |
| Wallet executed test controls | `d0f232fb998730fad6282b536d51b6b4c5e210c9` | Exact-selector enumeration and the preserved 3/3 result bundle |
| Wallet current test controls | `11ae405a1d6cf894934f512ef1e5b981672b6c19` | Timeout-only successor that begins graceful termination at 55 seconds and force-kills at 60; unchanged tests were not rerun |
| Wallet G4 evidence | `14e0a6795acce5db4fc1f40705ad50f7ca58dcf4` | Privacy contract, bounded results, command non-proofs, and recovery-disable runbook |
| Wallet G4 manifest | `43d405ebe389025363cf7f14ca41893beb289736` | Exact graph, stage states, budgets, run conditions, and authorization boundaries |
| OpalFusion private status before this packet | `2d725ddbbe980442d8f1d899d9fa5b1abe385de1` | Private authoritative G4 progress checkpoint; public runtime revision remains unchanged |

The packet itself is frozen by the OpalFusion Git revision containing this file and [`mosaic-g4-findings-register.md`](mosaic-g4-findings-register.md). Review conclusions must name that packet revision and every reviewed source revision. A later source, configuration, specification, test, or evidence change invalidates only the affected lane unless the reviewer records a broader dependency.

## Frozen Profiles And Authority Boundaries

- Protocol profile: `Mosaic/0-opal-mainnet-alpha.4`.
- Post-manifest transport profile: `nostr-tor/0-opal-mainnet-alpha.5`.
- Authenticated bootstrap profile: `nostr-tor/0-opal-mosaic-private-alpha-bootstrap.1`.
- Private-deployment profile: `nostr-tor/0-opal-mainnet-alpha-private-deployment.1`.
- Wallet depends directly on OpalBase, OpalCrypto, and OpalDiagnostics. OpalFusion and SwiftFulcrum remain transitive through OpalBase; a transitive Xcode package row is expected and is not a duplicated Wallet dependency.
- OpalCrypto owns cryptographic calculation. OpalFusion owns reusable Mosaic protocol behavior. OpalBase owns wallet, transaction, journal, recovery, broadcast, and chain policy. Wallet owns Apple-platform persistence, Keychain custody, concrete transport capabilities, sole-session lifecycle, operator presentation, and application disable policy. SwiftFulcrum owns reusable Fulcrum contracts. OpalDiagnostics owns diagnostics primitives.
- Production Mosaic transport, the generic mainnet runtime driver, external networking, broadcast, value movement, canary execution, public enablement, main promotion, tags, releases, and publication remain disabled or separately approval-gated.

## Normative And Status Sources

- [`mosaic-protocol-specification.md`](mosaic-protocol-specification.md) owns draft Mosaic behavior and later release gates.
- [`mosaic-mainnet-alpha-profile.md`](mosaic-mainnet-alpha-profile.md) owns the frozen alpha.4 and alpha.5 contract.
- [`mosaic-mainnet-alpha-private-deployment.md`](mosaic-mainnet-alpha-private-deployment.md) owns the accepted private-deployment.1 supplement and safe readiness wording.
- [`mosaic-private-alpha-transport-bootstrap.md`](mosaic-private-alpha-transport-bootstrap.md) owns bootstrap.1 and its application capability obligations.
- [`mosaic-security-model.md`](mosaic-security-model.md) owns threat assumptions, security invariants, safe claims, required verification, and review gates.
- [`mosaic-mainnet-alpha-progress.md`](mosaic-mainnet-alpha-progress.md) owns non-normative sequencing and closure status without weakening the sources above.
- [`mosaic-g0-closure-evidence-2026-08-21.md`](mosaic-g0-closure-evidence-2026-08-21.md), [`mosaic-g1-closure-evidence-2026-08-21.md`](mosaic-g1-closure-evidence-2026-08-21.md), [`mosaic-g2-closure-evidence-2026-08-21.md`](mosaic-g2-closure-evidence-2026-08-21.md), and [`mosaic-g3-closure-evidence-2026-08-23.md`](mosaic-g3-closure-evidence-2026-08-23.md) own the exact closed-gate evidence.
- Wallet `docs/readiness/mosaic-g4-assurance-manifest.json`, `docs/readiness/mosaic-g4-observability-evidence-2026-08-23.md`, and `docs/readiness/mosaic-private-alpha-recovery-disable-runbook.md` own the current application assurance state.

## Review Lane Status

| Lane | Required independence | Assignment | Disposition |
| --- | --- | --- | --- |
| `CRY` — Cryptographic construction | Independent cryptographic reviewer | Unassigned | Awaiting review |
| `SEC` — Side-channel and secret lifecycle | Independent implementation-security reviewer | Unassigned | Awaiting review |
| `PRO` — Protocol and state-machine behavior | Independent protocol reviewer | Unassigned | Awaiting review |
| `PRI` — Privacy, Tor, relay, and traffic analysis | Independent privacy and network-metadata reviewer | Unassigned | Awaiting supported-environment evidence and review |
| `WAL` — Wallet policy, recovery, and transaction safety | Independent wallet-policy reviewer | Unassigned | Awaiting review |
| `OPS` — Deployment, observability, incident response, and disable | Independent deployment or operations reviewer | Unassigned | Awaiting signed drill and review |
| `UXC` — UX, accessibility, and safe claims | Independent product-safety and accessibility reviewer | Unassigned | Awaiting application review |

“Unassigned” and “awaiting review” mean unknown, not pass. G4 cannot close until every required lane has an independent disposition and every release-blocking finding is resolved and retested at the exact affected graph.

## `CRY` — Cryptographic Construction

### Primary Source Map

- OpalCrypto `Sources/OpalCrypto/Cryptography/RSABSSA*.swift` and `Sources/OpalCrypto/PublicAPI/OpalCrypto.RSABSSA*.swift`.
- OpalCrypto `Sources/OpalCrypto/Cryptography/PedersenModel*.swift` and `Sources/OpalCrypto/PublicAPI/OpalCrypto.Pedersen*.swift`.
- OpalCrypto `Sources/OpalCrypto/PublicAPI/OpalCrypto.AuthenticatedEncryption.AES256GCM*.swift`.
- OpalFusion `Sources/OpalFusion/BlindSignature/` and Mosaic authorization, canonical-wire, transcript, manifest, and bootstrap types under `Sources/OpalFusion/Mosaic/`.
- OpalCrypto tests `RSABSSARequestForComments9474Validator.swift`, `PublicAPIRSABSSAContractValidator.swift`, `PublicAPIRSABSSAOperationValidator.swift`, `MosaicPrivateAlphaRSABSSASigningKeyValidator.swift`, and `PublicAPIPedersenValidator.swift`.

### Mandatory Questions

1. Does the RFC 9474 variant, encoding, PSS configuration, blinding, verification, and recoverable request state preserve the intended one-more-authorization boundary without request or response confusion?
2. Are the two component-bound authorization purposes domain-separated across attempt, generation, material, component index, and signing key, including recovery and duplicate handling?
3. Do Pedersen setup, commitment, opening, point validation, scalar handling, and canonical encoding reject invalid or ambiguous values without changing the frozen alpha.4 contract?
4. Are AES-256-GCM keys, nonces, authenticated-data labels, sealed-box formats, HKDF/SHA-256 derivations, and error semantics purpose-bound and non-reusable across Wallet records?
5. Does any package or application layer accidentally implement a second cryptographic calculation, expose private signing keys, substitute general wallet secrets, or introduce an external production crypto dependency?
6. Which positive and negative vectors are portable, and which required vector or parser-fuzz artifacts remain missing before G4 closure?

### Declared Non-Proofs

Passing local vectors and the real-RSABSSA G3 rehearsal do not constitute an independent cryptographic review, side-channel review, formal proof, or production approval. The accepted off-commitment accountability limitation and non-Sybil admission posture remain explicit private-alpha tradeoffs rather than cryptographic guarantees.

## `SEC` — Side-Channel And Secret Lifecycle

### Primary Source Map

- OpalCrypto `Sources/OpalCrypto/Support/Data~ConstantTimeComparison.swift`, secp256k1 scalar and private-key types, RSABSSA integer operations, and secret-material diagnostics tests.
- Wallet Keychain and secret clients `MosaicPrivateAlphaKeyClient.swift`, `MosaicPrivateAlphaAuthorizationKeyClient.swift`, `MosaicPrivateAlphaConductorAuthorizationKeyClient.swift`, `MosaicPrivateAlphaComponentSlotSecretClient.swift`, and `MosaicPrivateAlphaRouteMaterialClient.swift`.
- Wallet authenticated persistence and erasure in `MosaicPrivateAlphaPersistenceActor.swift`, `MosaicPrivateAlphaAttemptRepository.swift`, and the record and anchor codecs.
- G1 fresh-process, fault-injection, cleanup, and Keychain evidence plus the G3 terminal-recovery evidence.

### Mandatory Questions

1. Are comparisons, branches, allocations, integer conversions, and error paths involving secret material suitable for the private-alpha threat model, and are any secret-dependent timing or memory-lifetime behaviors release-blocking?
2. Are attempt keys, blind-request state, salts, nonces, mailbox keys, route credentials, authorization identities, and component-slot secrets created, persisted, restored, rotated, and erased at the exact intended boundaries?
3. Can cancellation, crash, rollback, stale inventory, duplicate records, Keychain uncertainty, file synchronization failure, or terminal cleanup leave reusable or ambiguously owned secret material?
4. Do diagnostics, descriptions, crash paths, test fixtures, or error adapters expose keys, identities, transaction data, paths, or recoverable correlation material?
5. Which secret-lifecycle assertions require physical-device, instrumentation, memory-analysis, or timing evidence beyond the current automated matrix?

### Declared Non-Proofs

The existing implementation and tests do not claim constant-time behavior for every high-level Swift operation, secure-memory zeroization guarantees, resistance to a compromised host, or physical-device side-channel validation.

## `PRO` — Protocol And State-Machine Behavior

### Primary Source Map

- OpalFusion `Sources/OpalFusion/Mosaic/` attempt, local-attempt, role-election, manifest, transcript, canonical-codec, private-deployment, runtime-driver, transport-ingress, publication, replay-journal, bootstrap, private-alpha owner, post-manifest execution, and terminal-recovery families.
- OpalFusion `Sources/OpalFusion/Host/` Mosaic reservation, transcript binding, complete-transaction, signing, and host contracts.
- OpalFusion canonical, role, manifest, transcript, host, private-deployment, transport, replay, bootstrap, runtime, and terminal-recovery validators.
- The frozen profiles and G0 through G3 closure records named above.

### Mandatory Questions

1. Do role election, roster agreement, manifest signatures, transcript agreement, contributor acknowledgements, and exact complete-transaction assembly prevent equivocation or cross-attempt substitution before signing?
2. Are conductor exclusion, contributor counts, 23-slot material, the two anonymous mailbox sequences, complete-recipient publication, and phase ordering enforced across fresh and recovered execution?
3. Do duplicate, malformed, stale, reordered, cross-round, source-loss, cancellation, retry, and partial-recovery paths fail closed without replaying effects or reconstructing a fresh runtime around partial state?
4. Are canonical parsers strict about lengths, bounds, order, trailing bytes, profile identifiers, network, attempt, generation, material, role, phase, sequence, and expiry?
5. Are the frozen alpha.4, alpha.5, bootstrap.1, and private-deployment.1 bytes and domain values internally consistent, and does any implementation-defined behavior remain at a security boundary?
6. Does the accepted off-commitment accountability limitation create an additional private-alpha release blocker beyond the recorded semantic decision?

### Declared Non-Proofs

The current deterministic suites and exact G3 host commit do not establish interoperability with another implementation, complete parser fuzz coverage, portable vectors for every schema, liveness against malicious majorities, or public `Mosaic/1` readiness.

## `PRI` — Privacy, Tor, Relay, And Traffic Analysis

### Primary Source Map

- [`mosaic-security-model.md`](mosaic-security-model.md) transport, diagnostic, Sybil, claims, verification, and review sections.
- [`mosaic-mainnet-alpha-private-deployment.md`](mosaic-mainnet-alpha-private-deployment.md) relay registry, discovery, timing, admission, and safe-wording requirements.
- OpalFusion NIP-44/NIP-59 codecs, fixed 8,192-byte application content, relay publisher, fan-in, route allocation, bootstrap mailbox, replay, and publication bridge families.
- Wallet `MosaicPrivateAlphaTransportConfiguration.swift`, `MosaicPrivateAlphaRelayClient.swift`, `MosaicPrivateAlphaTorWebSocketActor.swift`, route-material and timing clients, local transport harness, and G2 evidence.
- Wallet G4 aggregate observability source and evidence.

### Mandatory Questions

1. What can each relay, Tor entry or exit position, conductor, contributor, local observer, partial observer, and global observer correlate from event counts, timing, recipient keys, route reuse, discovery identities, control identities, mailbox identities, and transaction shape?
2. Do fixed application payload width, cover timestamps, randomized timing, distinct credentials, distinct connection objects, and three configured relays reduce only the risks actually claimed, without implying circuit or operator independence?
3. Can retry, abort, reconnection, source loss, publication acknowledgement, or recovery sequences relink control and anonymous roles?
4. Do the relay registry labels, endpoint normalization, no-NIP-42/no-proof-of-work policy, SOCKS domain-address requests, and no-clearnet construction fail closed under every supported deployment configuration?
5. Does the diagnostics contract prevent identifiers, endpoints, wallet state, amounts, transaction material, paths, timestamps, payloads, or free-form errors from becoming a second linkage surface?
6. What supported-environment traffic-analysis experiment, capture boundary, success criterion, and reviewer access are required before this lane can receive a disposition?

### Declared Non-Proofs

Local loopback, distinct SOCKS credentials, three connection objects, signed relay acknowledgements, fixed individual-event payload width, and participant count do not prove anonymity, operator independence, Tor-circuit independence, delivery durability, resistance to a global observer, or a measured anonymity set. Supported-environment traffic analysis is still pending and separately approval-gated.

## `WAL` — Wallet Policy, Recovery, And Transaction Safety

### Primary Source Map

- OpalBase `Sources/OpalBase/Account/Mosaic/` journal, recovery planner and owner, profile policy, reservation, exact-transaction, host, broadcast coordinator, chain observation, and network-attestation families.
- OpalBase `Sources/OpalBase/Public/OpalBase+Account+MosaicPrivateAlpha*.swift`, the sole Wallet-facing facade over OpalFusion.
- Wallet `MosaicPrivateAlphaPersistenceActor.swift`, `MosaicPrivateAlphaAttemptRepository.swift`, `MosaicPrivateAlphaSessionOwnerActor.swift`, authenticated record and anchor codecs, companion journals, concrete clients, and application composition.
- OpalBase Mosaic local tests; Wallet G1, G2, G3, and focused G4 observability and disable evidence.

### Mandatory Questions

1. Can any path reserve, sign, commit, release, recover, clean, or later broadcast outside the sole OpalBase wallet and transaction authority?
2. Are selected inputs, fresh outputs, previous-output data, exact transaction bytes, transcript binding, signatures, wallet disposition, and broadcast approval correlated without trusting conductor claims?
3. Do cancellation, crash, concurrent dispatch, duplicate callback, stale generation, missing or extra records, rollback, Keychain uncertainty, chain uncertainty, and terminal recovery execute exactly one conservative action?
4. Does Wallet remain a thin application owner without direct OpalFusion declaration, import, product link, or second runtime constructor?
5. Are G3 terminal recovery and zero-connection/no-broadcast evidence sufficient for the pre-G4 application boundary, and which complete fault-matrix cases still block G4?
6. Which G5 chain presence, confirmation, reorganization, rollback, accounting, and isolated Fulcrum-process obligations are deliberately not part of the current G4 disposition?

### Declared Non-Proofs

G3 reaches explicit broadcast approval but does not authorize or prove a broadcast, chain reconciliation, confirmation, reorganization, value accounting, concurrent dispatch exclusion under live chain conditions, or canary safety. Those remain G5 responsibilities after G4 closes.

## `OPS` — Deployment, Observability, Incident Response, And Disable

### Primary Source Map

- Wallet `docs/readiness/mosaic-g4-assurance-manifest.json`, `docs/readiness/mosaic-g4-observability-evidence-2026-08-23.md`, and `docs/readiness/mosaic-private-alpha-recovery-disable-runbook.md`.
- Wallet `scripts/check-mosaic-g4-assurance-manifest.sh`, static, Debug, Release, and exact observability runners.
- Wallet production composition, diagnostics configuration, observability interactor, and disabled session owner.
- OpalFusion progress, security model, private-deployment supplement, this packet, and the findings register.

### Mandatory Questions

1. Are exact graph, branch, package, build-tool, plug-in, cache, result-bundle, and authorization boundaries reproducible without silently advancing dependencies?
2. Does production remain structurally disabled, and is any future enablement impossible without a reviewed application change and separate external authority?
3. Are observability signals actionable, low-cardinality, silent by default, Release-disabled, and free of secret or linkage fields while still distinguishing hold, quarantine, cleanup, suspension, and disabled denial?
4. Does the recovery-disable runbook prevent destructive manual repair, secret-bearing evidence capture, unchanged retries, external operation, and self-certification?
5. Which clean repository CI, signed isolated runtime, multi-device, supported Tor/relay, incident drill, supply-chain, provenance, and staffing evidence remains required?

### Declared Non-Proofs

Local static checks, unsigned test builds, a passing Release compile, and focused xcresults are not archive, signing, notarization, deployment, live telemetry, service-level, incident-response, disaster-recovery, or staffed-operations evidence. The prepared runbook has not yet completed its signed isolated drill.

## `UXC` — UX, Accessibility, And Safe Claims

### Primary Source Map

- [`mosaic-security-model.md`](mosaic-security-model.md#11-safe-public-claims) and the private-deployment safe-wording rule.
- Wallet CashFusion presenters and views under `Wallet/App/Presenter/CashFusion/`, `Wallet/App/View/CashFusion/`, and the account CashFusion pilot surfaces.
- Wallet Mosaic state, capability, policy, presenter, and view expectations in `docs/plans/mosaic-private-alpha.md`.
- Wallet readiness tracker, application evidence, observability evidence, and recovery-disable runbook.

### Mandatory Questions

1. Is any private-alpha Mosaic action or state user-accessible today, and if not, do internal or future-facing surfaces avoid implying availability?
2. Do preparation, waiting, recovery-required, quarantined, suspended, approval, cleanup, disabled, and error states use conservative language with an unambiguous safe next action?
3. Do labels, values, status, errors, progress, warnings, confirmation, stop, and disable affordances avoid “anonymous,” “untraceable,” “audited,” “production-ready,” participant-count anonymity, Sybil-resistance, or relay-independence implications?
4. Are VoiceOver, Dynamic Type, keyboard navigation, focus order, contrast, Reduce Motion, localization expansion, status updates, and destructive-action confirmation adequate on every supported Wallet surface?
5. Does broadcast approval remain explicit and separate from successful preparation or protocol completion, with amounts, fees, inputs, outputs, and consequences reviewed through Wallet policy?
6. Which wording is acceptable for private internal evidence, and which wording remains prohibited for public, App Store, fundraising, release, or investor use?

### Declared Non-Proofs

Architecture plans and conservative documentation do not constitute a rendered UX or accessibility review. No public Mosaic availability, privacy, anonymity, audit, production-readiness, or measured-anonymity claim is supported by the current evidence.

## Existing Evidence Summary

| Gate or slice | Evidence accepted for review intake | Still not proven |
| --- | --- | --- |
| G0 | Accepted profile decision, exact first-party graph, focused package contracts, dependency parity, and Wallet build | Independent review, deployment, networking, or value movement |
| G1 | Authenticated outer record, Keychain anchor, atomic persistence, cross-process exclusion, fresh-process fault matrix, and terminal cleanup | Compromised-host resistance or complete physical-device secret analysis |
| G2 | Disabled-by-default concrete Tor-only adapter, exact route policy, acknowledgement persistence, local production-adapter loopback, and restart cleanup | External route, operator, Tor-circuit, timing, delivery, or anonymity evidence |
| G3 | Sole application owner, exact host commit, 78 publications, real-RSABSSA rehearsal, route-loss terminalization, fresh composition recovery, zero recovery opens or sends, and no broadcast intent | Broadcast, chain reconciliation, value accounting, canary, or G4 assurance closure |
| G4 local slices | Release compile boundary, machine assurance manifest, exact Debug and Release entrypoints, aggregate diagnostics, 3/3 bounded signal and disable proof, and prepared no-network runbook | Exact package CI, complete vectors, parser fuzz, complete simulator faults, multi-device and supported-environment evidence, signed runbook drill, UX/accessibility review, and independent dispositions |

## Reviewer Deliverable

Each reviewer must submit a durable record containing:

1. Reviewer name or stable identifier, relevant expertise, affiliation, compensation or conflict statement, relationship to the implementation owners, and prior participation in the reviewed design or code.
2. Packet revision, every source and evidence revision actually reviewed, review lane or lanes, dates, tools and methods, files or components sampled, and any excluded surface.
3. One register row per finding using the lane-prefixed identifier, severity, status, affected revisions and files, violated invariant or requirement, exploit or failure scenario, evidence, required remediation, and required retest.
4. A statement for every mandatory question: assessed and acceptable, finding raised, not assessed, or blocked by missing evidence.
5. A lane disposition of `Hold`, `Conditional`, or `Accept for the bounded private-alpha gate`, with explicit conditions and residual risks. “Accept” cannot authorize external networking, value movement, canary execution, public enablement, main promotion, tags, releases, publication, or broader claims.
6. A signed or otherwise attributable final update after remediation and retest. Implementation-owner assertions may accompany but cannot replace this disposition.

## Finding And Closure Rules

- Use [`mosaic-g4-findings-register.md`](mosaic-g4-findings-register.md) as the sole cross-lane findings and disposition index.
- A `Critical` or `High` finding is release-blocking until independently retested and resolved.
- A `Medium` finding is release-blocking when it affects funds, signing authority, profile authenticity, recovery correctness, secret lifecycle, clearnet exclusion, privacy boundaries, disable behavior, safe claims, or a required G4 invariant. Otherwise the reviewer must justify any nonblocking disposition.
- A `Low` or `Informational` finding remains tracked until resolved, explicitly deferred outside private-alpha scope, or accepted by the later residual-risk authority. The implementation owner cannot silently close it.
- A missing required review, unanswered mandatory question, incomplete source coverage, missing supported-environment evidence, or reviewer conflict is a `Hold`, not an implicit pass.
- G4 may close only after every required lane has a current independent disposition and the register contains no unresolved release-blocking finding. A successful test, staging run, or later canary cannot waive a missing review.

## Handoff

Provide the reviewer read access to the exact first-party revisions and this private packet revision. Do not provide wallet seeds, private keys, real attempt records, SOCKS credentials, raw transaction proposals, signed private-alpha traffic, or existing user containers. Use synthetic fixtures and sanitized evidence unless a separately approved supported-environment protocol defines stricter handling. Record assignments and all questions in the findings register rather than editing normative specifications during review intake.
