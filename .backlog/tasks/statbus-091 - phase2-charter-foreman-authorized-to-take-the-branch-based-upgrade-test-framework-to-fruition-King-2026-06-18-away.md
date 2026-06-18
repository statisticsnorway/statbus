---
id: STATBUS-091
title: >-
  phase2-charter: foreman authorized to take the branch-based upgrade-test
  framework to fruition (King, 2026-06-18, away)
status: In Progress
assignee: []
created_date: '2026-06-18 14:55'
updated_date: '2026-06-18 15:38'
labels:
  - upgrade
  - phase-2
  - authority
  - framework
dependencies: []
priority: high
ordinal: 91000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AUTHORITY (King, 2026-06-18, explicitly granted before going away):
The foreman is BLESSED + CHARGED to drive the following to fruition autonomously while the King is away:
1. Fix ALL reported issues (STATBUS-087 history label, -088 log wording, -089 maintenance/config-drift + the upgrade-should-regen-config product gap, -090 status-lag race; the harness infra-transport flakiness).
2. Land the architecture improvements already designed + ratified (STATBUS-086 upgrade CLI verbs, -034 branch-channel, -072 amend-migration-conveyance).
3. IMPLEMENT THE WHOLE branch-based upgrade-test framework (STATBUS-071) + the failure-mode matrix on real upgrades (STATBUS-044).

GRANTED POWERS (verbatim intent): commit locally, push to master, create + push the test branches (test/base, test/<defect>, test/<defect>-fixed, …) and all required effects (images, CI workflows, channels). Take it all the way to fruition. "You've been blessed by me to do those things."

RATIONALE (King): it follows logically — we CANNOT test the upgrade failure/fix scenarios without this framework. The fabricated public.upgrade-row + injected-kill workarounds are being retired; real branch arcs (install A → upgrade to a defective B → fix via C, via the real web-approve→NOTIFY→service path) are the only faithful test.

QUALITY BAR the foreman holds (self-imposed, unchanged): review every diff before commit; master always builds + green; ship bit-by-bit (no heap); the run is the only oracle (commit→push→CI image→run→observe→iterate); commit via `git commit -F`; no --no-verify/FORCE=1; no #<digit> in commit messages; no manual DB writes on any environment (fixes ship via code + idempotent install); SSH reads OK, SSH writes forbidden.

BUILD ORDER (dependency-aware):
- WAVE 1 (parallel, disjoint files): engineer → STATBUS-086 (CLI verbs, the test-driver foundation; owns cli/cmd/upgrade.go + service.go + commit.go). mechanic → STATBUS-087 (frontend page.tsx count; King leaned "N applied · M superseded"). architect → implementable STATBUS-071 build spec + STATBUS-089 config-regen-on-upgrade design.
- WAVE 2 (product changes on the upgrade path, sequenced through the engineer to avoid service.go conflicts): STATBUS-072 (amend+re-stamp), STATBUS-034 (branch-channel), STATBUS-089 (upgrade regenerates config), STATBUS-090 (NOTIFY-after-completed + reconnect-refetch), STATBUS-088 (operator-facing wording).
- WAVE 3 (the goal): STATBUS-071 arc harness — test branches + upgrade-arc-harness.yaml + register+schedule driver + inject-on-real-upgrade for precise kills + clean-slate-after-rollback fingerprint; then STATBUS-044 the failure-mode matrix.

This task is the durable record of the authority + the master tracker for the Phase-2 drive. Supersedes the Phase-2 half of STATBUS-075 (which tracked the install RC, now cut as v2026.06.0-rc.04).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All reported issues fixed, reviewed, and committed: STATBUS-087 (history label), -088 (operator log wording), -089 (maintenance + upgrade-regenerates-config), -090 (status-lag race)
- [ ] #2 Architecture improvements landed on master: STATBUS-086 (check/list/register/schedule, apply+discover retired), -034 (branch-channel), -072 (amend-in-place + re-stamp)
- [ ] #3 Branch-arc framework (STATBUS-071) built: throwaway test branches (base + defect + fix), upgrade-arc-harness.yaml, the register+schedule test driver (real web→NOTIFY→service path), inject-on-real-upgrade for precise kills, clean-slate-after-rollback fingerprint
- [ ] #4 The framework RUNS the real failure/fix arcs GREEN on Hetzner VMs: install A -> upgrade to defective B (too-long/OOM + crash) -> failure observed -> fix branch C lands forward for BOTH populations (few-who-failed re-run + many-who-succeeded re-stamp) -> post-rollback fingerprint == post-A
- [ ] #5 Failure-mode matrix (STATBUS-044) covered on real upgrades
- [ ] #6 fabricate_scheduled_upgrade_row + the fabricated-row/injected-kill workarounds RETIRED
- [ ] #7 Master stayed green throughout; every code unit was architect-reviewed AND foreman-diff-reviewed before commit
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DRIVE PLAN — how this gets taken home (foreman, per King's orchestration guidance 2026-06-18):

ORCHESTRATION LOOP (every code unit, no exceptions): architect designs/specs -> engineer codes -> ARCHITECT code-reviews it adversarially (correctness, missing pieces, matches spec?) -> foreman reviews the diff + refines -> foreman commits + pushes. Mechanic takes small/disjoint fixes; tester runs tests (sole runner); operator does legwork. Use the WHOLE team; nothing lands without the architect's review + my diff review.

CADENCE: ship bit-by-bit, master green between units. For anything touching the upgrade/recovery path, the RUN is the oracle: commit -> push -> CI builds the per-commit image -> the branch-arc harness run validates it -> observe -> iterate. Disjoint-files discipline: service.go work is single-owner (engineer, sequenced 086->072->090->088); frontend (087) runs parallel via mechanic.

WAVES: W1 (in flight) 086 + 087 + (architect: 071 build-spec & 089 design). W2 072, 034, 089-impl, 090, 088. W3 071 framework then 044 matrix.

FRUITION = AC #4: the branch-arc harness runs the real failure/fix arcs green and the fabricated workarounds are retired -> we can finally test the upgrade failure scenarios faithfully (the King's stated reason). Progress tracked on THIS ticket each wave; King reviews on return.

DECISION (foreman, autonomous per this charter, 2026-06-18) — *-fixed-migration branch topology (STATBUS-071 §7 / doc-012 §7): RESOLVED = OPTION 1, the fix EDITS the migration in place + re-stamps (amend-in-place). RATIONALE: (1) it is the King's already-RATIFIED STATBUS-072 mechanism; (2) the architect's analysis proves Option 2 (add forward V+k) CANNOT rescue the hosts that failed (they'd re-run the same broken migration) without either also amending V — which collapses to Option 1 — or building a new supersede-skip mechanism. So Option 1 is the only clean working answer. The King's offhand 'never edit the immutable original' was a looser framing introduced mid-discussion; the ratified 072 governs. doc-012's Option-1 assumption stands; only JOB-1's fix-step would change if the King later picks Option 2. FLAGGED HERE for the King's review on return — he can redirect to Option 2 (+ a new supersede-skip dependency) if he prefers; until then the build proceeds Option 1.

PROGRESS (W1): STATBUS-087 DONE (de453b814). STATBUS-086 stage-scoped (engineer building: CLI core → fabricate retirement/AC#6 → AC#8 VM proof). STATBUS-071 build-spec = doc-012 (architect, engineer-ready, queued for STEP 2). STATBUS-089 design in progress (architect + operator).

DECISION (foreman, autonomous, 2026-06-18) — STATBUS-086 stage-2 kill-scenario scheduling: RESOLVED = OPTION C (architect's ruling, foreman-verified at the tag; overturns my earlier D lean). The kill scenarios keep their v2026.05.2 baseline and schedule the arbitrary HEAD SHA via the v2026.05.2 box's OWN `./sb upgrade apply <short>` after `git fetch`. VERIFIED at v2026.05.2: CLI apply accepts a commit-short (upgrade.go:176,183 IsCommitShort) AND service scheduleImmediate does INSERT…ON CONFLICT(commit_sha) DO UPDATE on the UntaggedTarget branch (service.go:2814,2829-2831) — so the old box really can schedule an arbitrary SHA. My D lean assumed it couldn't; the tag-read disproved that. C is MORE faithful than fabricate (which bypassed apply+scheduleImmediate), needs NO HEAD-binary pre-stage (binary-swap-kill stays faithful), keeps the Albania FROM-old baseline, and AC#6 (delete fabricate) FULLY applies in 086. SMOKE-GATE: prove C on ONE kill scenario on a VM before converting all ~18 (fall back to D if v2026.05.2 surprises). Not throwaway — final form; 071 only ADDS new arcs.

086 REVIEW (architect): core SOLID (lock-free one-shot safe; upsertCandidate verbatim/one-path; supersede correct). Must-fix into stage-1 before commit: (1) notify-all-clouds.yaml discover→check (workflow breakage); (2) AC#3/#9 unit tests (were NOT actually present); (3) apply-latest register-then-schedule (else deploy-to-X silently no-ops on the discovery race — keeps master deployable). Engineer doing these now → architect re-reviews apply-latest → foreman commits complete stage-1. Robustness (RunSchedule state-guard, --recreate double-NOTIFY) + AC#7 doc sweep = follow-on. STATBUS-089 design = doc-013 (verified maintenance 3-way-path bug); STATBUS-071 build-spec = doc-012.
<!-- SECTION:NOTES:END -->
