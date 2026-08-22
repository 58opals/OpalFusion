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
| `G4-GAP-002` | Golden vectors | Partial | Portable positive and negative vectors for every required canonical encoding, digest, and message contract |
| `G4-GAP-003` | Parser fuzz | Partial: first-party deterministic campaign covers 20 initial seeds / every-parser reconciliation remains open | Fuzz target, seed-corpus, and coverage evidence for every parser before live profile enablement; the current deterministic seeds may feed that lane but do not waive it |
| `G4-GAP-004` | Simulator fault matrix | Partial | Complete required failure, cancellation, replay, retry, reservation-release, and downgrade-attempt coverage |
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
