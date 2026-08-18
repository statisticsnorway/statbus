---
id: STATBUS-218
title: >-
  arc-ride-not-free: the RIDE shortcut skips the VMs but still spends 20-30
  minutes building images it will not use
status: In Progress
assignee:
  - mechanic
created_date: '2026-08-17 21:46'
updated_date: '2026-08-18 14:54'
labels:
  - ci
  - release
dependencies: []
references:
  - .github/workflows/upgrade-arc-harness.yaml
priority: low
type: enhancement
ordinal: 218000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHAT THIS PART DOES: when a release tag contains no upgrade-relevant changes, the arc workflow deliberately "rides" — it selects zero test scenarios and finishes green, inheriting the previous release's proof instead of re-spending 31 VM boot-and-test cycles. A ratified cost shortcut (STATBUS-199 D2).

WHAT GOES WRONG: the shortcut only skips the final stage. The two preparation jobs still run in full, so a riding run spends 20-30 minutes preparing for tests it has already decided not to run. Found 2026-08-17 by the architect during the STATBUS-215 review; cost and latency only, no correctness impact.

THE DETAIL: construct and image-wait (.github/workflows/upgrade-arc-harness.yaml) carry no skip condition. A riding run therefore still pushes its throwaway test/* fixture branches, kicks off an image build for each, and polls the registry until every image exists — about 20-30 minutes cold. Then teardown deletes the branches nothing used. The bill: a GitHub runner held for the whole window, a full set of throwaway image builds, and — worst — the shared hetzner-vm-fleet queue slot held the entire time, delaying install-recovery-harness and test-install behind a run that will execute nothing.

THE FIX, with the STATBUS-215 lesson applied: give construct and image-wait the same ride decision run-arc effectively has. Care required — making construct skippable puts a skipped job into every downstream needs chain, which is exactly the implicit-success() trap 215 just fixed. So: re-audit every downstream `if:` for that class, keep teardown always-on, and make teardown tolerate branches that were never created.

WHY THAT HELPS: a riding run then costs nearly nothing and releases the fleet queue immediately. The shortcut delivers the saving it was designed for, and real test runs stop waiting behind empty ones.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A RIDE run skips construct and image-wait (no fixture branches pushed, no images.yaml dispatch, no ghcr poll) while still concluding green
- [x] #2 Every downstream job's `if:` is re-audited against the STATBUS-215 implicit-success() poisoning class once construct becomes skippable
- [x] #3 teardown still runs and succeeds when no fixture branches were ever created
- [x] #4 A non-RIDE tag push and a workflow_dispatch both still run the full construct → image-wait → run-arc chain unchanged
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: mechanic
created: 2026-08-18 08:18
---
AC#1-#4 done in .github/workflows/upgrade-arc-harness.yaml, frozen for review. Two structural changes only:

1. `construct` gained `needs: [decide]` and an explicit `if:`:
```
if: >-
  ${{ !cancelled() &&
      !(github.event_name == 'push' && needs.decide.outputs.sensitive == 'false') }}
```
Same RIDE-exemption clause as `no-arcs-guard`'s existing exemption (textually identical, for grep-consistency across the file). `!cancelled()` is required, not decorative: construct now has `decide` as a need, and `decide` is SKIPPED (not failed) on workflow_dispatch (`decide`'s own `if: github.event_name == 'push'`) — a bare `if:` would implicitly AND success() over needs and silently skip construct on every dispatch, the exact STATBUS-215 trap. The clause is dispatch-safe without an extra guard: on dispatch `github.event_name != 'push'` so it's false regardless of decide's (empty, skipped) outputs, and construct runs.

2. `image-wait` (needs: construct, previously bare `if:`) gained an explicit:
```
if: >-
  ${{ !cancelled() && needs.construct.result == 'success' }}
```
The bare form already cascaded correctly (implicit success()-wrap, no status-check function in play) but I made it explicit per the 215 audit discipline — so a later edit adding `!cancelled()`/`always()` here for e.g. a retry can't silently reopen the poisoning class without someone also re-adding the construct-result check.

Everything else downstream was AUDITED, not changed — already correct given how the 215 fix shaped it:
- `run-arc`: explicit `needs.construct.result == 'success' && needs['image-wait'].result == 'success'` already in place — on RIDE, construct is skipped (not success) so run-arc stays skipped. Verified, not touched (AC#1 'run-arc must stay skipped on RIDE' held).
- `no-arcs-guard`: unaffected (doesn't need construct/image-wait).
- `teardown`: `if: always()`, needs [construct, image-wait, run-arc]. Its branch-delete step recomputes branch names from `RUN_ID` directly (never reads `needs.construct.outputs.*`) and does `git ls-remote --exit-code` before every delete — on RIDE, both branches are absent, it logs 'not present ... nothing to delete' and exits 0. AC#3 satisfied with zero code change, verified by reading the script.
- `cleanup`: `if: always()`, needs [discover, run-arc]; queries hcloud directly, unaffected by construct/image-wait state.

Three-path trace (mentally executed):
- **Sensitive tag push**: decide runs→sensitive=true. construct's RIDE clause false→runs. image-wait runs. discover (always()) runs, RIDE=false, nullglob finds 31 arcs, builds full matrix. no-arcs-guard: count!=0→skipped. run-arc: all needs success, count!=0→runs full matrix. teardown/cleanup run, delete real branches. Everything runs, zero skips outside the norm.
- **RIDE tag push** (no upgrade-sensitive change since prev RC): decide runs→sensitive=false. construct's RIDE clause true→construct SKIPPED. image-wait: construct.result!='success'→SKIPPED. discover (always()) runs, RIDE=true→early-exits matrix=[]/count=0 before ever reaching the nullglob check, success. no-arcs-guard: count=='0' but RIDE-exemption true→skipped (no false alarm). run-arc: construct.result!='success'→SKIPPED. teardown (always()): runs, finds no branches, exits 0 clean. cleanup (always()): runs, finds nothing to reap. Workflow concludes GREEN with zero fixture branches pushed, zero images.yaml dispatches, zero ghcr polls, zero VMs — AC#1 satisfied.
- **workflow_dispatch**: decide SKIPPED (if: event_name=='push' is false) → outputs.sensitive is empty. construct's RIDE clause: `event_name=='push'` is false regardless of the empty sensitive value→clause false→construct RUNS (dispatch-safe, doesn't matter that decide was skipped). image-wait runs. discover (always()) runs, RIDE=false (not push), enumerates arcs via SCENARIOS_INPUT (blank/all or a subset), builds matrix. no-arcs-guard: only fires if count somehow ends up 0, which can't happen via a valid dispatch (unknown selectors already exit 1 loud before reaching count). run-arc runs the (possibly subset) matrix. teardown/cleanup run as normal. Full chain unchanged — AC#4 satisfied.

Validated: `ruby -ryaml` parses clean; `actionlint .github/workflows/upgrade-arc-harness.yaml` exits 0, no findings. This diff shares the file with the STATBUS-216 AC#3 fix (same commit-scope, both frozen in the working tree together, no commits made).

CAVEAT flagged, not fixed (out of AC scope): teardown's branch-delete loop only covers the `working`/`failing` lineages (2 of 7: oom/ceiling/healthpark/codeonly/crollback branches are never explicitly deleted by teardown, relying entirely on the weekly image-cleanup-style GC or manual sweep for those). Pre-existing, not introduced or worsened by this change — noting it here rather than silently walking past it.
---

author: architect
created: 2026-08-18 08:27
---
REVIEW VERDICT — APPROVED, no re-freeze. I traced all four trigger shapes through the whole job graph rather than checking the two the freeze report names.

THE construct RIDE CLAUSE IS CORRECT ON EVERY PATH.
• workflow_dispatch: decide is SKIPPED, github.event_name != 'push' → the RIDE clause is false → construct RUNS. The `!cancelled()` prefix is what makes this true rather than a repeat of STATBUS-215 — construct now needs decide, so a bare `if:` here would have implicitly ANDed success() over a skipped need and silently killed every dispatch. He applied the lesson correctly and explained it in place.
• tag push, sensitive='false': construct SKIPS — the intended saving.
• tag push, sensitive='true': construct RUNS full.
• tag push, decide FAILED: outputs.sensitive is unset, never 'false' → clause false → construct RUNS FULL. BLESSED, and it is the right direction: RIDE is a cost optimizer, so its absence must never be inferred from a broken decision. The run is red from decide's own failure regardless, so the extra work is never mistaken for proof.

THE SKIP CASCADES CLEANLY — CHECKED, NOT ASSUMED. image-wait's explicit `!cancelled() && needs.construct.result == 'success'` skips on RIDE; run-arc's per-need checks (landed in STATBUS-215) then skip it too, independently of count. no-arcs-guard is exempt on the RIDE path. teardown and cleanup are both always() and immune. So a RIDE run concludes green with construct, image-wait and run-arc all skipped — the ratified 199 D2 shape — and the release gate still refuses it as an anchor, because all 31 required arcs land in Missing. The optimisation cannot be mistaken for proof anywhere.

AC#3 SATISFIED BY EXISTING DESIGN — CORRECTLY LEFT ALONE. teardown already tolerates branches that were never created: it recomputes names from github.run_id rather than construct's outputs (so an empty-output skip changes nothing), guards each delete with `git ls-remote --exit-code`, and ends `exit 0` unconditionally. Not touching it was the right call; recorded here so nobody later "fixes" a job that is already correct.

MAKING image-wait's IMPLICIT GUARD EXPLICIT: approved. It changes no behaviour today — a bare `if:` already cascades the skip — but it means a future edit that adds always()/!cancelled() for a retry cannot silently reopen the poisoning class. That is the STATBUS-215 audit discipline applied forward rather than only backward.

POINT 7 — TICKETED AS STATBUS-220 (Low). The mechanic's premise was right and I verified it rather than taking it: image-cleanup.yaml really does carry a `branch-gc` job for `test/upgrade-arc-*` with a 7-day age guard on a Sunday cron, and it is prefix-scoped so it can never touch master or the deploy pointers. So this is tidiness, not a leak. But the empirical picture says the labels are backwards: `git ls-remote --heads origin 'refs/heads/test/*'` returns 34 branches right now across three run_ids (31970534502, 32009980725, and the in-flight 32115158961), covering the ceiling, codeonly and other lineages teardown never deletes. teardown deletes 4 of roughly 11 per run, so the "PRIMARY cleanup" its own comment claims to be is in fact the minority path and the weekly GC is doing most of the work. Worth correcting; not worth blocking this round.
---

author: foreman
created: 2026-08-18 08:29
---
LANDED at d02550da5 as one unit with 216 and 217, architect-approved. AC#2 (downstream if audit), AC#3 (teardown tolerates never-created branches — verified pre-existing design, deliberately untouched), AC#4 (three-path trace: sensitive push, RIDE push, dispatch) closed. AC#1 stays OPEN as the observation arm: it closes on the first real RIDE tag push observed skipping construct/image-wait — which cannot be the next RC (this very commit touches the arc workflow, a sensitive path, so the next cut runs the full suite). Ticket stays In Progress until that observation.
---

author: architect (relayed by foreman)
created: 2026-08-18 14:54
---
RULED: this ticket closes as ACHIEVED BY SUPERSESSION when 223 lands — not abandoned. The ride decision moves to the orchestrator, which simply does not dispatch the arc fleet for a non-sensitive RC: 218's goal reached more completely than 218 could reach it (not-dispatching beats dispatching-and-skipping on every axis — no runner, no fixture branches, no image builds, no queue slot). The landed hardening stays (image-wait's explicit if is 215-class protection that survives the ride machinery's deletion). AC#1 re-points to 223's own observation: a non-sensitive RC dispatches no arc fleet at all. Close at the 223 landing sweep.
---
<!-- COMMENTS:END -->
