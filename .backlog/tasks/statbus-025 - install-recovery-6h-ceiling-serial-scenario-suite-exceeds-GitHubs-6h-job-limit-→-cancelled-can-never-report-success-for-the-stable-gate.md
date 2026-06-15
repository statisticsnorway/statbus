---
id: STATBUS-025
title: >-
  install-recovery-6h-ceiling: serial scenario suite exceeds GitHub's 6h job
  limit → cancelled, can never report success for the stable gate
status: In Progress
assignee:
  - engineer
created_date: '2026-06-11 03:17'
updated_date: '2026-06-15 14:39'
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
- [x] #1 Workflow restructured: discover job (scenario enumeration + one binary build/artifact) + matrix job per scenario + final global-reap cleanup job
- [x] #2 Per-job reap touches ONLY its own VM; the global statbus-recovery-* sweep runs only in the final cleanup job (no sibling-job VM kills)
- [x] #3 max-parallel set with verified Hetzner quota headroom; per-job timeout ~45 min
- [ ] #4 A full matrix run completes well under the 6h ceiling and reports a real workflow conclusion (success when all scenarios pass)
- [ ] #5 Stable gate satisfied unchanged: CheckWorkflowAtCommit returns green at an RC commit from a passing matrix run (zero release.go edits)
- [x] #6 Per-scenario log artifacts uploaded; single-scenario re-run still works via the scenarios input
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Decision history: options (a) matrix / (b) batch / (c) faster-scenarios were weighed; MATRIX chosen (clean gate semantics, per-scenario logs, ~60min). Deep-reference: doc-007 Track B1. The rc.01 tag-push harness run will show the 6h cancel — expected, the live exhibit. First in line in the gate-maker batch (engineer-sized, ~1 day).

DISPATCHED 2026-06-15 (King: 'get things going... ready by tonight'). Engineer implementing the matrix split per the design. THE #1 unblock — without it no comprehensive harness run can report success (6h ceiling). Engineer owns .github/workflows/install-recovery-harness.yaml. Operator verifying Hetzner quota headroom for max-parallel. do-not-self-commit → foreman reviews+commits.

REVIEW BOUNCE (foreman, 2026-06-15) — commit HELD. Structure/reap-scoping/AC#5 all correct (gate reads run-level conclusion by filename, job rename invisible). BUT a gate-breaking stdout-contamination bug: the discover step captures `--print-selected` via $(), and run.sh:105 echoes the known-RED exclusion notice to STDOUT in the default path. Empirically reproduced: count=30 (not 28), matrix JSON ingests 2 bogus '(excluding known-RED reproducer...)' entries → 2 always-failing matrix jobs → workflow conclusion=failure → gate never green (the exact bug 025 fixes, reintroduced). FIX: run.sh:105 append `>&2` (progress→stderr, data→stdout). Bounced to engineer with the empirical repro + the required re-verify (--print-selected | wc -l == 28; 0 'excluding' lines in matrix). Foreman re-reviews + commits once clean.

COMMITTED bd92d2ada (pushed). Foreman re-reviewed + re-verified after the bounce: discover pipeline now emits 28 names, matrix length 28, 0 'excluding' contamination (the stderr fix at run.sh:105 + a comment so it can't regress). AC#1 (3-stage restructure), AC#2 (per-job reap own-VM-only, matches run.sh's statbus-recovery-<base>; global sweep isolated to cleanup), AC#3 (max-parallel 8 quota-confirmed, 45m per-job) = code-done + verified. AC#5's 'zero release.go edits' half independently verified (CheckWorkflowAtCommit reads the run-level conclusion by workflow filename). REMAINING (LIVE — confirm on the next harness dispatch): AC#4 (full matrix run under 6h + real conclusion), AC#5 live (gate green at an RC commit from a passing run), AC#6 (per-scenario logs + single-scenario re-run). These fall out of the comprehensive harness GREEN the operator drives once 027/029 + the 031 scenario are also in.

MACHINERY VALIDATED ON A LIVE RUN (foreman, smoke run 27549262413, single-scenario 0-happy-upgrade): discover built the sb binary once + enumerated the matrix to EXACTLY ["0-happy-upgrade"] (AC#6 single-scenario re-run ✓), one run-scenario matrix job ran on its own VM, the per-job reap + the final cleanup job were both green, and the run reported a REAL conclusion (failure — correctly, because the scenario job failed) in ~45min (well under the 6h ceiling). So the 025 restructure works end-to-end: AC#6 DONE (per-scenario log artifact uploaded + downloaded; single-scenario narrowing works); AC#4's under-6h + real-conclusion mechanics PROVEN (the all-pass success-conclusion still needs a green scenario set); AC#5 pending an all-pass run. NOTE: the run's failure was NOT a 025 defect — it surfaced a SEPARATE daemon-startup blocker (0-happy-upgrade fails restarting statbus-upgrade onto the staged HEAD binary; `./sb upgrade service` exits ~3s in; journal not captured). That's exactly 025 doing its job — the old cancelled-suite could NEVER have reported this. The daemon-startup blocker is being root-caused separately (harness journal-capture fix + engineer staleness-guard/SHA-chain investigation).

FOLLOW-ON DEFECT + FIX (engineer root-cause, foreman reviewed+committed 31db8cec0). The matrix split introduced a SHA-drift the old serial job was immune to: build (discover job) and run (run-scenario job) are SEPARATE jobs with SEPARATE checkouts; on workflow_dispatch each checks out the branch TIP at its own time, so a commit landing on master between them (e.g. a backlog auto-commit) makes the staged binary's stamped commit (build-sb: git rev-parse HEAD, dev.sh:67) != the scenario's upgrade-target HEAD. That tripped the staleness guard on `./sb upgrade service` (selfheal=true, root.go:62) -> RebuildAndReexec `make -C cli build` -> fails on the toolchain-less VM -> os.Exit(2) -> unit dies ~3s post-restart (the 0-happy-upgrade smoke failure). FIX: pin BOTH checkouts to `ref: ${{ github.sha }}` (constant across a run) -> binary-commit == VM-HEAD by construction; restores the single-checkout invariant. Tag-push (the real gate) already pinned github.sha so it was never affected; only dispatch-validation runs hit it. Engineer correctly REJECTED a freshness-bypass alt (would mask genuine drift). Also committed: unit-diagnostics capture (49441c54b) so any future unit-start failure dumps journalctl+status+version+HEAD before VM reap. Re-running 0-happy-upgrade against fixed master (49441c54b) to confirm AC#4 all-pass mechanics.
<!-- SECTION:NOTES:END -->
