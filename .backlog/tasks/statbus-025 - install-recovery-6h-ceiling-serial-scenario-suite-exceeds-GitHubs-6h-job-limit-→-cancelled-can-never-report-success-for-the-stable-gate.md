---
id: STATBUS-025
title: >-
  install-recovery-6h-ceiling: serial scenario suite exceeds GitHub's 6h job
  limit → cancelled, can never report success for the stable gate
status: To Do
assignee: []
created_date: '2026-06-11 03:17'
updated_date: '2026-06-12 07:52'
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
STRUCTURAL BLOCKER for the stable gate. The harness workflow runs all ~28 scenarios SERIALLY in ONE job (~13 min each ≈ 6h) and GitHub kills jobs at 360 min → run 27306718138 was CANCELLED at exactly 6h00. The stable gate (release.go:989 → CheckWorkflowAtCommit, workflow_check.go:81) needs the WORKFLOW conclusion == success at the RC commit; `cancelled` is never `success` — so even an ALL-GREEN suite can never satisfy the gate. Worse, more green = slower = more cancelled (passing scenarios run their full convergence tails). Gates STABLE (the Norway deploy), not the prerelease. The rc.01 tag-push run repeating this cancel is EXPECTED — it is the live exhibit of this ticket, not a regression.

THE FIX (decided — MATRIX, design ready to implement):
1. Discover job: enumerate scenarios/*.sh → JSON matrix; build the sb binary ONCE and upload as an artifact (keep today's one-build-for-all property).
2. One matrix job per scenario: download the binary artifact, provision its own Hetzner VM, run the ONE scenario, upload its log artifact. max-parallel ~8 (checklist: confirm the Hetzner project server quota covers max-parallel + any other VMs in the project). Per-job timeout-minutes ~45.
3. THE ONE TRAP — reap scoping: the current always() reap step deletes EVERY statbus-recovery-* VM (install-recovery-harness.yaml:219-227). Inside a parallel matrix that murders sibling jobs' live VMs. Per-job reap must target only the job's own VM name; the global sweep moves to a final cleanup job (needs: [matrix], if: always()).
4. Stamps: run.sh's all-scenarios stamp (run.sh:174-178) never fires under per-scenario selectors — fine: the CI gate reads the workflow conclusion (= AND of all matrix jobs), so ZERO release.go changes; keep the stamp for local full runs.
5. Result: wall-clock ≈ ceil(30/8)×~15min ≈ ~60 min (vs 6h+); cost unchanged ~€0.22/run (each scenario already bills a 1-hour VM minimum); bonus per-scenario logs + re-runs via the existing `scenarios` input.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Workflow restructured: discover job (scenario enumeration + one binary build/artifact) + matrix job per scenario + final global-reap cleanup job
- [ ] #2 Per-job reap touches ONLY its own VM; the global statbus-recovery-* sweep runs only in the final cleanup job (no sibling-job VM kills)
- [ ] #3 max-parallel set with verified Hetzner quota headroom; per-job timeout ~45 min
- [ ] #4 A full matrix run completes well under the 6h ceiling and reports a real workflow conclusion (success when all scenarios pass)
- [ ] #5 Stable gate satisfied unchanged: CheckWorkflowAtCommit returns green at an RC commit from a passing matrix run (zero release.go edits)
- [ ] #6 Per-scenario log artifacts uploaded; single-scenario re-run still works via the scenarios input
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Decision history: options (a) matrix / (b) batch / (c) faster-scenarios were weighed; MATRIX chosen (clean gate semantics, per-scenario logs, ~60min). Deep-reference: doc-007 Track B1. The rc.01 tag-push harness run will show the 6h cancel — expected, the live exhibit. First in line in the gate-maker batch (engineer-sized, ~1 day).
<!-- SECTION:NOTES:END -->
