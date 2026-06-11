---
id: STATBUS-025
title: >-
  install-recovery-6h-ceiling: serial scenario suite exceeds GitHub's 6h job
  limit → cancelled, can never report success for the stable gate
status: To Do
assignee: []
created_date: '2026-06-11 03:17'
updated_date: '2026-06-11 15:43'
labels:
  - install-recovery
  - ci
  - harness
  - blocker-stable
dependencies: []
documentation:
  - >-
    doc-007 -
    Roadmap-completing-install-upgrade-robustness-—-Norway-rollout-then-external-standalone.md
priority: high
ordinal: 25000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
STRUCTURAL BLOCKER discovered 2026-06-11. The install-recovery-harness.yaml runs all ~28 scenarios SERIALLY in a SINGLE job ("Provision Hetzner VMs + run full install-recovery scenario suite"), each on its own ephemeral Hetzner VM (~12-13 min/scenario). Total ≈ 6h, right at GitHub Actions' hard 360-min job ceiling.

Run 27306718138 @ cd2f5d51f (the validation of tonight's fixes) was CANCELLED at exactly 6h00m (21:13Z→03:13Z) — NOT a concurrency cancel (only run at that SHA), the 6h timeout. The previous run 27242482272 finished just under 6h with conclusion=failure. The IRONY + root cause: a FAILING scenario often exits fast, but a PASSING scenario runs its full convergence tail (health checks, data-intact asserts, restart-counter, teardown) — so as tonight's fixes turned reds GREEN, the suite got SLOWER and tipped over 6h. More green = slower = more likely to time out.

IMPACT: the `release stable` gate checks the install-recovery-harness WORKFLOW conclusion == success (release.go:989). A run that times out is `cancelled`, never `success` — so even if every scenario passes, the stable gate can NEVER be satisfied by the current single-serial-job shape. This gates STABLE (the actual NO deploy), NOT the RC cut (harness reds/cancel don't block prerelease).

FIX OPTIONS (architect/engineer to design): (a) MATRIX — fan the scenarios across parallel jobs (GitHub matrix), each job a subset or a single scenario, so wall-clock per job is ~12 min and the 6h ceiling is per-job not per-suite; needs HCLOUD quota headroom for concurrent VMs + the reap step per job. (b) BATCH — split into 2-3 sequential jobs (e.g. by prefix 2-/3-/4-5-), each <6h, gate on all green. (c) Reduce per-scenario time. Matrix (a) is the clean answer (also gives per-scenario logs + faster feedback). Cost note: more concurrent CX23 VMs, but each lives ~12 min not ~6h.

NOTE: tonight's run still validated most fixes before the cancel — see tmp/operator-comprehensive-27306718138.md. This ticket is about the GATE MECHANISM, separate from any individual scenario red.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ROADMAP DESIGN (architect, 2026-06-11, doc-007 Track B1 — first in line on the stable critical path): MATRIX (option a), grounded in the current yaml (which anticipates it at :23). Shape: discover job enumerates scenarios/*.sh → JSON + builds sb ONCE (artifact, keep the one-build property); matrix job per scenario (download artifact, one VM, one scenario, per-scenario log artifact), max-parallel ~8 (checklist: confirm Hetzner project server quota ≥ max-parallel + any production VMs), per-job timeout-minutes ~45. THE ONE TRAP: the current always() reap deletes EVERY statbus-recovery-* VM (yaml:219-227) — inside a parallel matrix that kills sibling jobs' live VMs; per-job reap must scope to the job's own VM name, the global sweep moves to a final needs:[matrix] if:always() cleanup job. Stamps: run.sh's all-scenarios stamp (:174-178) never fires under per-scenario selectors — CI needs no stamp (gate reads the workflow conclusion: CheckWorkflowAtCommit/workflow_check.go:81 = AND of matrix jobs, zero release.go edits); keep the local full-run stamp + fold in the agreed per-scenario stamp design so the local pre-push observe-evidence hook stays meaningful. Wall-clock ≈ ceil(30/8)×~15min ≈ ~60min (vs 6h+); cost unchanged ~€0.22/run (1-hour VM minimum per scenario already). Note: rc.01's tag-push run hitting the 6h cancel is the live exhibit of this problem — expected, not a regression.
<!-- SECTION:NOTES:END -->
