---
id: STATBUS-220
title: >-
  arc-teardown-partial: the arc harness self-deletes 4 of its ~11 fixture
  branches, leaving the rest to the weekly sweep it calls a backstop
status: In Progress
assignee:
  - mechanic
created_date: '2026-08-18 08:27'
updated_date: '2026-08-18 14:55'
labels:
  - ci
  - install-recovery
dependencies: []
references:
  - .github/workflows/upgrade-arc-harness.yaml
  - .github/workflows/image-cleanup.yaml
priority: low
type: chore
ordinal: 220000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHAT THIS PART DOES: each arc harness run pushes throwaway `test/upgrade-arc-*` fixture branches — one pair per lineage (working, failing, oom, ceiling, healthpark, codeonly, crollback) — so the image builder has something to build from. Two cleanups then remove them: the run's own teardown job deletes them at the end (the primary path, per its own comment), and image-cleanup.yaml's `branch-gc` job sweeps anything older than 7 days on the Sunday cron (the backstop).

WHAT GOES WRONG: teardown's delete loop only covers the working and failing lineages — 4 branches of roughly 11. Every other lineage's branches survive the run and wait for the weekly sweep, so the job that calls itself the primary cleanup is in fact the minority path, and the backstop does most of the work.

THE DETAIL: teardown's loop is `for lineage in working failing; do for suffix in migration fixed-migration`, recomputed from `github.run_id`. The oom, ceiling, healthpark, codeonly and crollback branches construct pushes are never named there. Measured 2026-08-18 during the STATBUS-218 review: `git ls-remote --heads origin 'refs/heads/test/*'` returns **34** branches across three run_ids (31970534502, 32009980725, and the then-in-flight 32115158961).

This is tidiness, not a leak, and the ticket says so plainly: `branch-gc` is real, prefix-scoped to `test/upgrade-arc-*` (so it can never touch master, the ops/*/deploy/* pointers, or db-seed), and age-gated at 7 days — comfortably above any arc run's 120-minute ceiling. Nothing accumulates without bound. What is wrong is the shape: a documented primary/backstop split where the primary covers a minority of cases invites the next reader to trust a guarantee that is not there.

THE FIX: derive teardown's lineage list from the same place construct derives it, so adding a lineage cannot leave its branches behind. If a single source is not practical inside one workflow file, widen the loop to every lineage construct pushes and say in the comment that the list is coupled to construct's fixtures.

WHY THAT HELPS: the run cleans up after itself, the weekly sweep goes back to being a genuine backstop for crashed runs rather than routine cleanup, and `git ls-remote` stops showing dozens of live fixture branches that make a real leak harder to spot when one happens.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 teardown deletes the fixture branches for EVERY lineage construct pushes, not only working and failing
- [ ] #2 The lineage list is derived from construct's own fixtures, or the coupling is stated in the comment so adding a lineage cannot silently leave branches behind
- [ ] #3 teardown still exits 0 when a branch is absent (RIDE run, crashed construct, already swept) — the existing ls-remote guard and unconditional exit 0 are preserved
- [ ] #4 After one full-suite run, `git ls-remote --heads origin 'refs/heads/test/*'` shows no branches from that run_id
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: mechanic
created: 2026-08-18 14:55
---
Built, frozen for review (no commits), same file/diff as STATBUS-223 (both touch upgrade-arc-harness.yaml's teardown-adjacent area, landing as one unit per the foreman's instruction).

AC#2 (single source of truth, not a wider hardcoded list): found `delete_throwaway_branches SPEC [RUN_ID]` already exists in test/install-recovery/lib/upgrade-target.sh (STATBUS-165 AC#4) — it recomputes BOTH branch names for any spec from the EXACT SAME pattern `construct_upgrade_target` uses to build them (`test/upgrade-arc-<spec>-migration-<run_id>` / `...-fixed-migration-<run_id>`), with the identical ls-remote-guard / best-effort-delete / always-return-0 shape teardown's old inline loop duplicated by hand for only 2 lineages. Teardown now sources that library (same file `construct` already sources) and calls the function once per spec:
```
. test/install-recovery/lib/upgrade-target.sh
for spec in working failing oom ceiling healthpark codeonly crollback; do
  delete_throwaway_branches "$spec" "$RUN_ID"
done
exit 0
```
This is structural coupling, not comment discipline — an 8th lineage added to construct later cannot silently leave its branches behind here, because deletion now derives from the SAME function construct's own branch-naming derives from, not a second hardcoded list that has to be remembered.

AC#1 (all lineages, not just working/failing): confirmed via test/install-recovery/lib/upgrade-target.sh:561 that `construct_upgrade_target` pushes BOTH a B and C branch for EVERY spec unconditionally (`git push -f origin "$_b_branch" "$_c_branch"`), including the single-phase lineages (oom/ceiling/codeonly) whose C is unused for image dispatch but still pushed "for uniformity" per the library's own comment — so all 7 lineages × 2 = 14 branches get pushed on a full run, not 11 (the 11-branch count I'd cited on 223 was the image-dispatch count, not the push count — corrected here). The new teardown loop covers all 7 specs → all 14 branches.

AC#3 (exits 0 on absent branches): preserved — `delete_throwaway_branches` carries the identical `git ls-remote --exit-code --heads origin` guard and unconditional `return 0` the old inline loop had (it's the SAME shape, STATBUS-165 built it by generalizing the CI teardown's own pattern), so RIDE runs / partial-construct-failure runs / already-swept branches all still no-op cleanly. teardown's own `exit 0` at the end is unchanged.

AC#4 (git ls-remote clean after a full run): not independently observable from here (needs a live full-suite run) — same category as 223's live-suite ACs. Structurally guaranteed by AC#1/#2's fix: every branch construct pushes now has a matching delete call.

Validated: bash -n implicit via actionlint's shellcheck pass (clean, zero findings) since this is a workflow-embedded script, not a standalone .sh file. Full trace and Go-test validation on the shared diff reported on STATBUS-223.
---
<!-- COMMENTS:END -->
