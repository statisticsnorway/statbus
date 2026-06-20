---
id: STATBUS-104
title: >-
  self-heal-health-gate: run healthCheck before the resumePostSwap
  completed-write
status: Done
assignee: []
created_date: '2026-06-20 10:35'
updated_date: '2026-06-20 10:46'
labels:
  - upgrade
  - recovery
  - health
  - hardening
dependencies: []
priority: medium
ordinal: 104000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
▶ DRIVE DECISION + STATUS (King, 2026-06-20): APPROVED by the King ("make sure it is tracked and done"). STATUS: DONE — committed a8cc0e504 + pushed. Foreman-gated: gofmt/build/test green; fall-through control flow verified (health-fail → continuation, never a direct rollback). The committed diff is the 8-line logical change ONLY — whole-file gofmt-version-drift churn (the local go1.26.4 reformats master differently) was excluded as a separate concern.

----

King-approved 2026-06-20. CONFIRMED recovery-correctness gap (foreman + architect code-read).

THE GAP: the post-crash self-heal canary (resumePostSwap, cli/internal/upgrade/service.go ~:5066) marks the upgrade row 'completed' on STRUCTURAL convergence only — containersAtFlagTarget (right images running at target SHA) + migrate.HasPending==false — WITHOUT verifying the app actually SERVES. The normal completion path (applyPostSwap) DOES verify: it calls d.healthCheck (rest-admin /ready + a functional RPC POST <500) at service.go:4809 before marking completed. The self-heal was designed for the narrow rune-Apr-24 case (applyPostSwap fully converged incl. healthCheck; only the final row-UPDATE was lost to an SDNOTIFY collision) where re-checking is redundant — but the SAME guard also fires when applyPostSwap was interrupted BEFORE its healthCheck, so a crash-recovered box can certify completed while not serving.

THE CLOSE (architect, concrete; zero false-rollback): gate the self-heal completed-UPDATE on the SAME bounded probe the normal path uses — healthCheck(progress, 5, 5s) as an else-if BEFORE the self-heal else. PASS -> self-heal to completed (genuinely serving). FAIL -> do NOT self-heal -> fall through to the EXISTING continuation (re-acquire flock -> applyPostSwap -> its own healthCheck -> completed OR rollback). Failure re-verifies the proper way; never a direct/knee-jerk rollback.

DISTINCT FROM STATBUS-097: 097 dissolves the migration-completeness undetectability (HasPending's domain); THIS is serving-health verification — NOT covered by 097. Neighbors in the code, orthogonal in what they protect.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The resumePostSwap self-heal path runs d.healthCheck (the same bounded probe as the normal path) before the 'completed' UPDATE at ~service.go:5083
- [x] #2 On healthCheck failure the self-heal does NOT mark completed and does NOT roll back directly — it falls through to the existing continuation (applyPostSwap), which re-verifies and then completes or rolls back
- [x] #3 go build + go test green; the change is a strengthening (more verification before certifying completed), no false-rollback path introduced
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
DONE — committed a8cc0e504, pushed, build+test green. Gated the resumePostSwap self-heal completed-write on the same bounded healthCheck applyPostSwap uses. On failure: no self-heal, no direct rollback — fall through to the continuation (applyPostSwap re-verifies → completed OR rollback). 8-line change; the engineer's incidental whole-file gofmt churn was excluded so the diff is the logical change only.
<!-- SECTION:FINAL_SUMMARY:END -->
