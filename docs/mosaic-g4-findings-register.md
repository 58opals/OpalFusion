# Mosaic G4 Findings Register

Status: open for independent review intake. No independent finding or lane disposition has been submitted; this means review is incomplete, not that the target is clean.

## Scope

This register indexes independent-review assignments, findings, remediation, retest, and dispositions for the exact target in [`mosaic-g4-independent-review-packet-2026-08-23.md`](mosaic-g4-independent-review-packet-2026-08-23.md). It does not own normative protocol behavior, source changes, test evidence, external authorization, G4 closure, G5 canary approval, or G6 residual-risk acceptance.

## Identifier And Status Rules

- Finding identifiers use `M4-<LANE>-NNN`, where `<LANE>` is `CRY`, `SEC`, `PRO`, `PRI`, `WAL`, `OPS`, or `UXC`.
- Finding statuses are `New`, `Triaged`, `Remediation In Progress`, `Ready For Independent Retest`, `Resolved`, `Deferred Outside Private Alpha`, or `Residual-Risk Decision Required`.
- Review dispositions are `Unassigned`, `In Review`, `Hold`, `Conditional`, or `Accept for the bounded private-alpha gate`.
- Only the independent reviewer or another explicitly accepted independent reviewer may mark a finding `Resolved` after retest. An implementation owner may link remediation and local validation but cannot supply the independent disposition.
- Every row must retain the affected source and packet revisions. Do not rewrite a finding to target newer code; add a remediation and retest revision.

## Severity

| Severity | Meaning |
| --- | --- |
| `Critical` | Plausible loss of funds or signing authority, catastrophic secret compromise, or a fundamental break in the reviewed security model |
| `High` | Release-blocking violation of authenticity, transaction safety, recovery, clearnet exclusion, secret lifecycle, profile isolation, or a core security invariant |
| `Medium` | Material weakness, ambiguity, denial or correlation vector, unsafe operational behavior, or misleading claim that is release-blocking when it touches a required G4 boundary |
| `Low` | Bounded weakness, hardening opportunity, incomplete defense in depth, or maintainability issue with no demonstrated required-invariant break |
| `Informational` | Clarification, evidence request, observation, or future-scope recommendation with no current defect assertion |

## Review Assignment And Disposition

| Lane | Reviewer | Independence and conflict record | Packet and source revisions | Started | Disposition | Conditions or blockers | Final record |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `CRY` | Unassigned | Not recorded | Not reviewed | — | Unassigned | Independent cryptographic reviewer required | — |
| `SEC` | Unassigned | Not recorded | Not reviewed | — | Unassigned | Independent side-channel and secret-lifecycle reviewer required | — |
| `PRO` | Unassigned | Not recorded | Not reviewed | — | Unassigned | Independent protocol reviewer required | — |
| `PRI` | Unassigned | Not recorded | Not reviewed | — | Unassigned | Supported-environment traffic-analysis evidence and independent privacy reviewer required | — |
| `WAL` | Unassigned | Not recorded | Not reviewed | — | Unassigned | Independent wallet-policy and recovery reviewer required | — |
| `OPS` | Unassigned | Not recorded | Not reviewed | — | Unassigned | Signed isolated runbook drill and independent deployment or operations reviewer required | — |
| `UXC` | Unassigned | Not recorded | Not reviewed | — | Unassigned | Independent verification of the no-user-surface boundary, future-interface contract, and safe claims required | — |

## Independent Findings

No findings have been submitted because no independent lane review has completed. Add one row per finding; never use an empty register as closure evidence.

| Finding | Lane | Severity | Status | Affected revisions and files | Invariant or requirement | Scenario and evidence | Required remediation | Local validation | Independent retest | Disposition |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

## Known Evidence Gaps

These are predeclared program gaps, not independent findings and not substitutes for reviewer analysis.

| Gap | Manifest stage | Current state | Closure evidence required |
| --- | --- | --- | --- |
| `G4-GAP-001` | Exact-graph package CI | Definition ready / manual paid-CI dispatch pending | One successful manual Xcode 27 matrix with exact revisions, resolved-checkout parity, package results, per-job timing, and preserved run URL or logs |
| `G4-GAP-002` | Golden vectors | Locally verified: 62 cached exact-graph tests pass across eleven suites / independent review intake remains open | Review the selected standards, canonical-wire, Nostr, journal, record, and anchor cases plus cached-build non-proofs; rerun only when an owning input changes |
| `G4-GAP-003` | Parser fuzz | Partial: first-party deterministic OpalFusion campaign covers 85 seeds across 21 focused test bodies; the 52-file map records 49 covered, three partial recovery variants, and zero closure-budget files / composite and cross-repository reconciliation remain open | Complete the named recovery variants, composite parents, and cross-repository root map with coverage evidence for every parser before live profile enablement |
| `G4-GAP-004` | Simulator fault matrix | Partial: 106 focused tests pass; OpalBase and Wallet plus OpalFusion durable relay continuation are green / eleven OpalFusion runtime and overflow selectors remain a timed hold | Complete only the held exact OpalFusion selectors in the package closure lane and preserve per-selector timing; do not rerun broad suites or the real-RSABSSA rehearsal |
| `G4-GAP-005` | Multi-device reliability | Pending external environment | Repeated supported-device composition evidence at the frozen deployment target |
| `G4-GAP-006` | Supported Tor and relay traffic analysis | Pending external environment | Approved capture plan, supported-environment results, interpretation, and independent privacy disposition |
| `G4-GAP-007` | Operations runbook | Partial | Signed secret-free isolated runtime observability, recovery, and disable drill with sanitized artifacts |
| `G4-GAP-008` | Conservative UX and accessibility | Local no-user-surface boundary verified / independent review pending | Independently confirm current Mosaic unreachability and structural coverage; review the future-interface and safe-claim contract; require rendered assistive-technology validation if an interface is introduced |
| `G4-GAP-009` | Independent review | Pending independent review | Current dispositions for all seven lanes and no unresolved release-blocking finding |

## Change Log

| Date | Change | Revision | Authoritative effect |
| --- | --- | --- | --- |
| 2026-08-23 | Register created with required lanes and predeclared evidence gaps | Git revision containing this file | Review intake only; no lane assigned or disposition granted |
| 2026-08-23 | Bound Wallet's locally verified no-user-surface evidence and reframed the UXC gap without assigning a reviewer | Git revision containing this update | Local evidence intake only; UXC and every independent disposition remain open |
| 2026-08-23 | Bound Wallet's manual-only exact-graph package CI definition without dispatching it | Git revision containing this update | CI preparation only; package CI execution and every independent disposition remain open |
| 2026-08-23 | Bound OpalFusion's first-party deterministic mutation campaign for 20 initial parser seeds | Git revision containing this update | Parser-fuzz gap advanced to partial; every-parser reconciliation and every independent disposition remain open |
| 2026-08-23 | Expanded OpalFusion's first-party deterministic mutation campaign to 54 seeds across five focused test bodies | Git revision containing this update | Parser-fuzz evidence broadened without changing production source or dependencies; reviewed parser-root reconciliation and every independent disposition remain open |
| 2026-08-23 | Expanded the campaign to 70 seeds across ten focused test bodies and added the 52-file implementation registry gate | Git revision containing this update | Parser-fuzz evidence and drift detection broadened without changing production source or dependencies; complete root reconciliation and every independent disposition remain open |
| 2026-08-23 | Covered the manifest-proposal-candidate root, validated-manifest recovery, both NIP-59 composite opens, and the publication-permit record, reaching 75 seeds across twelve focused test bodies | Git revision containing this update | The generic large-snapshot mutation loop was stopped over budget and replaced by six focused discriminant mutations; remaining root reconciliation and every independent disposition stay open |
| 2026-08-23 | Stopped three transport-bootstrap parser-test shapes after each crossed the ordinary 60-second ceiling | Git revision containing this update | No bootstrap result is claimed; use a digest-pinned first-party fixture or the single 600-second closure lane instead of repeating runtime RSA fixture generation |
| 2026-08-23 | Bound locally verified golden-vector evidence and the consolidated partial fault-selector record | Git revision containing this update | Vector execution is locally verified; fault closure remains held only on the named OpalFusion runtime and overflow selectors; no independent disposition is implied |
| 2026-08-23 | Added the one-to-one 52-file parser root map with 41 covered, three partial recovery variants, and eight closure-budget bootstrap files | Git revision containing this update | OpalFusion root accounting is explicit and drift-checked; composite, cross-repository, and every-parser closure remain open |
| 2026-08-23 | Replaced runtime-heavy transport fixture generation with a digest-pinned first-party proof and covered all eight closure-budget files through ten seeds across nine focused mutation bodies | `5e237bfcb1d8402ba8f1f86b4d8260b18fa23f49` | The OpalFusion map advances to 49 covered, three partial recovery variants, and zero closure-budget files without changing production source or package dependencies; composite, cross-repository, and every-parser closure remain open |
