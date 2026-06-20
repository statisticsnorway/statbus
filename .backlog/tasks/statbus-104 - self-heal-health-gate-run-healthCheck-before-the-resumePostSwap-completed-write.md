---
id: STATBUS-104
title: >-
  self-heal-health-gate: run healthCheck before the resumePostSwap
  completed-write
status: In Progress
assignee: []
created_date: '2026-06-20 10:35'
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
King-approved 2026-06-20. CONFIRMED recovery-correctness gap (foreman + architect code-read).

THE GAP: the post-crash self-heal canary (resumePostSwap, cli/internal/upgrade/service.go ~:5053-5084) marks the upgrade row 'completed' on STRUCTURAL convergence only — containersAtFlagTarget (right images running at target SHA) + migrate.HasPending==false — WITHOUT verifying the app actually SERVES. The normal completion path (applyPostSwap) DOES verify: it calls d.healthCheck (rest-admin /ready + a functional RPC POST <500) at service.go:4809 before marking completed. The self-heal was designed for the narrow rune-Apr-24 case (applyPostSwap fully converged incl. healthCheck; only the final row-UPDATE was lost to an SDNOTIFY collision) where re-checking is redundant — but the SAME guard also fires when applyPostSwap was interrupted BEFORE its healthCheck, so a crash-recovered box can certify completed while not serving.

THE CLOSE (architect, concrete; zero false-rollback): gate the self-heal completed-UPDATE (~:5083) on the SAME bounded probe the normal path uses — `if err := d.healthCheck(progress, 5, 5*time.Second); err != nil { log; /* fall through */ }` BEFORE the UPDATE. PASS -> self-heal to completed (genuinely serving). FAIL -> do NOT self-heal -> fall through to the EXISTING continuation (:5097+ -> re-acquire flock -> applyPostSwap -> which re-runs its own healthCheck -> completed OR rollback). Failure re-verifies the proper way; never a direct/knee-jerk rollback. healthCheck CAN run there (rest-admin /ready is loopback; containersAtFlagTarget already confirms rest+proxy up).

DISTINCT FROM STATBUS-097: 097 dissolves the migration-completeness undetectability (HasPending's domain); THIS is serving-health verification — NOT covered by 097. Neighbors in the code, orthogonal in what they protect.

OWNERSHIP: architect confirms exact placement -> engineer builds -> foreman gates (go build/test) + commits. Gate-adjacent (recovery-completion) but a STRENGTHENING not a bypass.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The resumePostSwap self-heal path runs d.healthCheck (the same bounded probe as the normal path) before the 'completed' UPDATE at ~service.go:5083
- [ ] #2 On healthCheck failure the self-heal does NOT mark completed and does NOT roll back directly — it falls through to the existing continuation (applyPostSwap), which re-verifies and then completes or rolls back
- [ ] #3 go build + go test green; the change is a strengthening (more verification before certifying completed), no false-rollback path introduced
<!-- AC:END -->
