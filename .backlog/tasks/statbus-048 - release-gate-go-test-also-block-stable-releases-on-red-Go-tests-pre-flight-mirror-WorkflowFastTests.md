---
id: STATBUS-048
title: >-
  release-gate-go-test: also block stable releases on red Go tests (pre-flight,
  mirror WorkflowFastTests)
status: Done
assignee:
  - engineer
created_date: '2026-06-13 11:48'
updated_date: '2026-06-13 12:05'
labels:
  - ci
  - test
  - release
dependencies: []
priority: medium
ordinal: 48000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from STATBUS-024 (engineer, 2026-06-13). The per-change gate (.github/workflows/go-test.yaml, commit 5b4e518bc) blocks PRs + master on a red Go test. This adds defense-in-depth: wire go-test-green into the stable-release PRE-FLIGHT gate so a red Go test also blocks cutting a stable release — mirror release.WorkflowFastTests in cli/internal/release/workflow_check.go.

Left out of 024 to keep scope tight + avoid touching the release-gate code. LOW priority: the per-change gate already catches red Go tests before they could reach a release branch, so this is belt-and-suspenders, not a hole.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ENGINEER (2026-06-13): Implemented, verified, awaiting foreman review + commit (do-not-self-commit, same as 024).

WIRED the new 'Go Test' workflow into the stable-release pre-flight gate, mirroring WorkflowFastTests EXACTLY. Naming derives mechanically per doc/release-workflow-gates.md: go-test.yaml -> const WorkflowGoTest -> bypass SKIP_GO_TEST -> label 'go-test'.

FOUR FILES (+12/-1):
1. cli/internal/release/workflow_check.go: added const WorkflowGoTest = "go-test.yaml".
2. cli/cmd/release.go: added checkStableWorkflowGate(release.WorkflowGoTest, "go-test", ...) call right after the fast-tests gate (strict — &&-folds into allPassed, a red/pending/missing Go Test refuses the cut; SKIP_GO_TEST=1 is the loud per-gate operator bypass). Plus help-text (Long): added the gate to the pre-flight list + SKIP_GO_TEST=1 to the bypass list.
3. cli/internal/release/workflow_check_test.go: added WorkflowGoTest case to the URL-path parameterized test.
4. doc/release-workflow-gates.md: added the table row + a 'where it fires' bullet (triggers on master push, so a run exists at the RC's commit — same shape as images/fast-tests).

STRICT, no warn-and-proceed: reuses the existing checkStableWorkflowGate which returns false on pending/failed/missing/unknown; only an explicit SKIP_GO_TEST=1 bypasses, and it logs loudly. Matches the King's strict-gating rule.

VERIFIED (cwd cli/): `go vet ./...`=0, `go build ./...`=0, `go test ./...`=0 (all 11 packages green incl. the new test case + upgrade/recovery suite). The per-change go-test gate (024) will be green on this commit.

Disjoint from architect's cli/internal/upgrade work — no collision.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Resolved 2026-06-13 (commit 80f76934f, pushed). A red "Go Test" workflow now also refuses to cut a stable release, mirroring the fast-tests gate exactly: WorkflowGoTest constant + checkStableWorkflowGate call placed right after fast-tests (folds into allPassed with &&, so failed/pending/missing/unreachable refuses the cut), SKIP_GO_TEST=1 loud per-gate bypass, --help pre-flight+bypass lists updated, doc table+bullet, and a URL-path test case. Foreman review caught + fixed a doc regression the engineer's report missed: the doc Edit had overwritten the test-hardening "where it fires" bullet (replaced instead of inserted) — restored in the same commit. Verified independently green: go vet/build/test exit 0 across 11 packages (incl. release + upgrade/recovery).
<!-- SECTION:FINAL_SUMMARY:END -->
