---
id: STATBUS-160
title: >-
  superseded-cannot-complete: markCurrentVersionCompleted's gate can complete a
  displaced-superseded row after a C rollback returns the box to B's binary
status: In Progress
assignee:
  - architect
created_date: '2026-07-11 22:46'
updated_date: '2026-07-12 01:41'
labels:
  - upgrade
  - recovery
  - architecture
dependencies: []
references:
  - STATBUS-159
  - STATBUS-154
priority: medium
ordinal: 161000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a row that ended as 'superseded' (displaced by a fix-release claim) stays superseded forever; no later boot may quietly promote it to completed.
> STAGE: upgrade recovery / state-model integrity. FOUND: 2026-07-12 — residual identified by the architect while ruling STATBUS-159 (displacement-at-claim); explicitly OUT of 159's scope, pre-existing class, unchanged by 159's fix ("gate ignores app health, same before/after").
> COMPLEXITY: needs an architect ruling on the gate shape before build.

THE RESIDUAL (from 159's ruling comment): markCurrentVersionCompleted (service.go — 154 added the state/parked guard) completes "the row whose commit_sha matches the running binary and completed_at IS NULL". Sequence: B parks → C claims (displacing B to superseded) → C FAILS and rolls back → the box is back on B's binary. On the next boot, the gate can match the displaced-superseded B row and mark it completed — a superseded row silently becoming the completed current version, contradicting the displacement's meaning and the state log's narration.

SHAPE QUESTION for the architect: does the completer's WHERE exclude terminal states (code gate), or does 'superseded' get the same DB-enforced cannot-be-completed treatment 154 gave parked rows? Per the always-add-constraints principle the DB-level guard is the likely floor; ruling needed on exact geometry AND on the honest disposition for a box rolled back onto a displaced version's binary (fresh row? re-open B? refuse?).

Origin: STATBUS-159 ruling comment #1 (architect, 2026-07-12); wave-9 evidence tmp/wave9-healthpark-job.log.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Architect ruling recorded: the guard geometry preventing completion of a superseded row (code gate vs DB constraint) and the honest disposition for a box rolled back onto a displaced version's binary
- [ ] #2 A displaced-superseded row provably cannot reach completed_at/state=completed under the post-rollback boot sequence (test proves it)
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-07-12 01:41
---
ANALYSIS (architect, 2026-07-12) — the class is bigger and simpler than the AC framed it. Verified against the tree: (1) markCurrentVersionCompleted's UPDATE (service.go:2963) never sets log_relative_file_path, and chk_upgrade_state_attributes requires it NOT NULL on completed — so the function's CHARTER case (completing a discovery-created 'available' row for an install.sh-deployed version, which has no log path) is DB-IMPOSSIBLE today: the write errors and the function returns silently. The only rows it CAN complete are rows WITH log paths — rows that went through claim, i.e. machinery-owned rows: in_progress (excluded by the 154 guard), and superseded/failed/rolled_back — every one of which is a lie to complete. ITS LEGITIMATE DOMAIN IS EMPTY. (2) SECOND WRITER, same class: install.go's POST_COMPLETION install-record upsert (:2345) — ON CONFLICT DO UPDATE SET state='completed' ... WHERE upgrade.state != 'completed' — resurrects a superseded (or failed, or rolled_back) row to completed. Its gate is 'the step-table succeeded', and the step table (install.go:596-628) verifies DB health + services started but has NO REST serve probe — on the post-C-rollback box at broken-B, the operator's PRESCRIBED remedy (./sb install) would complete superseded B while the application cannot serve. Same lie, different door, triggered by the operator doing exactly what we tell them to do. (3) The principled line that decides everything: 'completed' means THIS VERSION VERIFIABLY SERVES — the upgrade pipeline writes it only after healthCheck passes. A writer without a serve-proof must never write it. (4) Noted for coherence: the 154 constraint already makes any completed-write on a still-PARKED row error loudly; 160 closes the same door for displaced (superseded) rows.
---

author: architect
created: 2026-07-12 01:41
---
RULED (architect, 2026-07-12) — (a) GUARD GEOMETRY, three layers, 154-pattern (writer fix + class-level DB impossibility): LAYER 1 — DELETE markCurrentVersionCompleted entirely (function :2926, sole call Run :2061). Not a WHERE tweak: its legitimate domain is empty (charter case chk-blocked; everything reachable is a lie), and the house rule is remove wrong paths, don't guard them. Its side-calls (supersedeOlderReleases/-Prereleases) are redundant — every real completion path and the discovery cycle fire them. The UI 'Upgrade Now' dedup it claimed to serve is ALREADY unserved today (chk-blocked, silent) — if that ever matters, the UI compares against the running version from system_info; out of scope. LAYER 2 — narrow the install-record upsert's ON CONFLICT: WHERE upgrade.state NOT IN ('completed','superseded','failed','rolled_back','skipped','dismissed') — install bookkeeping may complete only never-attempted rows (available, scheduled); a terminal row is never resurrected by bookkeeping. The deliberate route back to a displaced/failed version is register/schedule → claim → pipeline → healthCheck → an HONEST completion (RunSchedule's atomic reset exists precisely for this). LAYER 3 — DB floor, the always-add-constraints answer: trigger upgrade_block_terminal_resurrection — BEFORE UPDATE ON public.upgrade, WHEN NEW.state='completed' AND OLD.state IN ('superseded','failed','rolled_back','skipped','dismissed') → RAISE naming the remedy ('re-dispatch via ./sb upgrade schedule; terminal rows are not resurrectable'). No legitimate writer performs that transition after layers 1-2: pipeline completions are in_progress→completed, install INSERTs fresh rows or completes available/scheduled, re-dispatch is terminal→scheduled (stays legal). Migration + tests extend test/sql/330 (the canonical upgrade-invariant home, sibling of the 154 rows). The 154 state-log audits any future writer that trips it. (b) DISPOSITION for a box rolled back onto a displaced version's binary: REFUSE — no fresh row, no re-open, no completion. The ledger stays true: last-completed = the last version that verifiably served; B stays superseded with its park narrative; C stays rolled_back/failed. The RUNNING version is an observed fact (system_info / version endpoint), never a ledger edit. This is the three-tier doctrine's 'valid stored data': the absence of a completed-B row is a correct, principled absence. The operator's forward path is schedule-a-fix (or deliberately re-schedule B through the full pipeline, which completes honestly only if health passes). ORACLE: fast level — 330 trigger tests (superseded→completed REJECTED, available→completed allowed, terminal→scheduled reset allowed); e2e — a C-rollback leg on 071's map as [UNPROVEN]: fix release C2 that itself fails post-swap → rolls back → box at B's binary → daemon boots + operator ./sb install → assert B stays superseded, no completed transition for B in upgrade_state_log. Engineer-scoped; floor bump NOT needed unless the trigger migration touches daemon relations above the current floor — it does (public.upgrade), so expect the 145 bump guard to force a floor re-decision; both objects are additive, same reasoning as the 154 bump (approved precedent).
---
<!-- COMMENTS:END -->
