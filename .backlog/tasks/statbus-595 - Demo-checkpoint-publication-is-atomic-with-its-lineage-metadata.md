---
id: STATBUS-595
title: Demo checkpoint publication is atomic with its lineage metadata
status: Done
assignee: []
created_date: '2026-11-08T11:59:00Z'
updated_date: '2026-11-08T17:29:00Z'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 511204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
RC01 recovery job128722552493/run42477260886 refused its demo checkpoint before creating a scenario guest. First comparison read a missing or stale demo_parent, while the second read printed the correct parent. Current builder creates checkpoint before publishing demo_parent and candidate provenance, exposing a ready snapshot before its required identity is committed. Investigate and fix publication/readiness without weakening lineage rejection or disrupting the running battery.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A deterministic behavioral regression exposes concurrent readers between snapshot creation and lineage publication, fails before the fix and succeeds after it.
- [x] #2 Readers reuse only fully published matching demo checkpoints, reject genuinely mismatched lineage, and handle incomplete builders using existing bounded ownership/reclaim rules.
- [x] #3 Relevant checkpoint, snapshot-layer and harness regressions pass with first-attempt failure evidence preserved.
- [x] #4 The corrected harness runs the failed arc and full candidate recovery gates in real guests before candidate acceptance.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
First-attempt log: tmp/combined-591-594-after-commit-first-failure.log. Failure occurred before scenario guest creation, not in injected migration recovery. Observe battery freeze: do not land scenario or harness changes while current battery is active.

2026-11-08 12:12 UTC root independently reproduced same-source deterministic regression RED=1 and prototype GREEN=0, including matching publication reuse, snapshot/fork identity, genuine parent/candidate mismatch refusals and interruption at all four metadata writes plus snapshot, with live/dead builder ownership recovery preserved. tmp/595/root-red-green-status.log and root-{red,green}.log. Minimal prepared patch moves the readiness checkpoint after metadata. git apply --check passes. Eight existing shell suites pass in both unchanged/patched copies. Tracked harness remains untouched while current real battery runs. New regression must be explicitly registered in Harness Selftest when landed. Real corrected guest acceptance remains open. Latest owner Norway halt does not halt normal595test hygiene.

2026-11-08 12:28 UTC: Git history independently locates the snapshot-before-metadata ordering in Oct20 commit5f96870f70 and the same bytes in accepted RC04/929fe787. This is a newly exposed pre-existing harness race, not evidence that591introduced a recovery defect. Earlier green runs do not establish this publication interleaving; which prior jobs reused a completed snapshot versus arrived later has not been established. New deterministic regression forces the reader at readiness publication and validates frozen snapshot/fork provenance. Separate tmp/595/ci-registration.patch adds it to the explicit Harness Selftest list, apply-check verified without changing tracked harness. Real current battery remains active with the single preserved first failure, no blind rerun. All four acceptance criteria remain open pending landed/final verification and real corrected guest gates.

2026-11-08 12:37 UTC: Original Arc42477260886 completed/failure with all40jobs terminal and only known128722552493 failed before guest creation; LXD42477211979success, Orchestrator42475935661failure propagated from arc, alljobsterminal. Originalchainexit1/noPIDs. Root explicitly released freeze12:33, then REDc0dc9175d268ff93cbf39887be260bbd9b90c77e registered the deterministic regression in Harness Selftest; minimal GREEN20d60332bb03529c3aa9e22eacdf1cdcbefc34fa moves snapshot after four provenance writes. Root independently reviewed all three paths and ran final tracked publication regression plus eight related suites/syntax/shellcheck PASS15s, tmp/595/root-final-validation.log. Root also ran committed RED-parent backend with its complete relative helper library: actual readiness-boundary assertion fails as intended, tmp/595/root-committed-parent-red.log. First isolated-backend replay lacked relative data-helpers and is retained separately as fixture setup error, not defect proof. AC1/2 verified locally. Source/exactCI and actual corrected guest/full candidate gates remain outstanding, AC3/4 unchecked. No Norway or nextstable authorization.

2026-11-08 13:03 UTC: All seven exact-source workflows at8d543b4f4f12ebbd7aadd303562b97c2ac470ce3 completed/success before normal cut, including Harness42481154836 actual new publication step35success12:41:34 and Fast42481422223 actual Live-database tests. Root local publication+eight related suites/syntax/ShellCheck and intended committed-parent RED remain verified, AC3 checked. Normal full clean preflight tagged actual v2026.11.3-rc.02 at the same fullSHA, no bypass/stamp repair. Release42482654411 completed/success/published12:59:56. Actual nine assets/fullSHA/four downloaded binary checksums/five registry manifest digests verified13:02:34, tmp/595/repair-assets-corrected-verified.log. Initial temporary asset verifier incorrectly assumed RC01 has_migrations=true; workflow defines previous-tag delta and actual rc01-to-rc02 migrations diff is empty, so explicit false is correct. First refusal preserved, verifier corrected locally, no product or gate code change. Actual corrected Smoke/Hardening/Fast/LXD/Arcs/devcanary/Orchestrator acceptance remains open, AC4 unchecked. One independent combined-595-repair1 chain and one bounded individual-job observer, no blind retry. Tracked harness/scenarios remain frozen during new battery. Owner no-Norway/no-nextstable/no591productapproval holds unchanged.

2026-11-08 13:22 UTC: Corrected actual after-commit-before-recorded-kill job128741991622 in Arc42483598347 completed/success, full first-attempt log downloaded to tmp/595/repair-after-commit-before-recorded-kill.log. It reused the matching published demo checkpoint, created/booted its own scenario guest, observed baseline migration20261108104714, injected the committed-but-unrecorded state, confirmed SIGKILL of migrate PID8167, then independently observed rolled_back, restored-away fixture, unchanged baseline migration, preserved SU126/LU23/ES50/history48, cleared flag, bounded restart1 and CA HTTPS health200. This is genuine corrected original arc acceptance, not local transport proof. Real Smoke happy-install and released11.2-to-RC02 happy-upgrade, Hardening, tagFast and automatic devdeploy are also completed/success. Dev exact8d target completed; actual /monitor13:15:30 RC02 healthy5/5 worker0failed0stuck. Full LXD parity/rest of Arcs/Orchestrator remain active, so AC4 remains unchecked and ticket In Progress. No tracked harness/scenario edits until entire battery terminal, no Norway operations, no next stable or591product approval.

2026-11-08 17:28 UTC closure evidence: corrected rc.02 source8d543b4f4 fullactualgate GREEN13:56, Orchestrator42482654394 completed/success, independentchainexit0. Arcs42483598347 completed/success39jobs plus expected Refuse zero-arc run skipped; original fixed after-commit job128741991622 actualguest recovery proof retained in13:22note. Ad-hoc final assertion demanding everyjob success was wrong about the expectedskip, not a product/harness failure; original diagnostic retained and explicit status/conclusion inspected. LXD42483542316, Smoke42482753873, Hardening42482654400, tagFast42482654401, dev42483423774 allsuccess. Tracked RED/GREEN and8relatedsuites plus exactHarnessCI satisfyAC3, actualcorrectedguest/fullgate satisfyAC4. Serialrc.03 repeatedactualfullgate17:24, Arc42500990314/Orchestrator42499809081success. Stableheld, Norwayuntouched. Later evidence-onlye6Fast374failure remainsseparate openinvestigation.
<!-- SECTION:NOTES:END -->
