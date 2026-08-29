---
id: STATBUS-308
title: >-
  unit-floor-announce: a box missing its own scheduler must say so loudly —
  detection in code, repair stays the install verb
status: In Progress
assignee:
  - engineer
created_date: '2026-08-28 21:43'
updated_date: '2026-08-29 11:59'
labels:
  - upgrade
  - cli
  - ops
dependencies: []
priority: high
type: enhancement
ordinal: 301000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: a box that is structurally unable to follow its channel must SAY SO — loudly, on its health surface and in its journal, naming the fix. Detection ships in code; the repair stays the product's own idempotent install verb, run by a human.

THE INCIDENT THAT DEMANDS IT (STATBUS-303, 2026-08-28): demo's check scheduler unit was MISSING entirely — systemctl status: not-found — and the box sat nine days with a stale upgrade page, looking healthy while structurally unable to ever take the stable automatically. Nothing announced it. The silent-wedge class: the box whose whole job is auto-following could not follow, and no surface said so.

WHY DETECTION AND NOT SELF-REPAIR (doctrine, settled): the missing piece IS the machinery any automatic repair would ride (a box without its scheduler cannot schedule its own fix); a second watchdog just moves the who-repairs-the-watchdog question; CI-reaching-in only works for boxes we can reach and would make our fleet healthier than a real NSO's in exactly the way that hides product gaps; and standing self-heal paths are forbidden by the fix-once-keep-loud-guards rule — recurrence must fail loudly with the fix named, never be quietly repaired forever.

THE SHAPE: the product knows its own unit floor (the set the install step-table lays down — check scheduler, upgrade service, whatever it owns). A cheap verification — at service start, on each tick, and/or surfaced through the existing health endpoint — compares the floor against systemd reality. On a gap: a loud journal line naming the missing unit AND the fix (unit X missing — this box cannot follow its channel; run the install entrypoint), a health-surface field the admin UI can show, and ideally the upgrade page itself carrying the warning (the operator looking at a stale page should be TOLD why it is stale). The announce must be un-ignorable but honest — no self-modification, no unit writes, detection only.

CROSS-REFERENCES: STATBUS-303 (the incident), STATBUS-267 (the stuck-task detector — same detect-loudly family, different object), the 262 silent-wedge class.

WHAT IS ACHIEVED: no box sits silently below its own floor; the next demo announces itself within one tick instead of nine days.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PREMISE CORRECTION (2026-08-28 night): the demo incident that motivated this ticket involved a PHANTOM unit — no statbus-upgrade-check unit has ever existed in the product; check scheduling is the upgrade service's internal ticker + NOTIFY. The north star STANDS (a box structurally unable to follow its channel must say so loudly) but the mechanism reframes: the detection floor must be DERIVED from what install actually lays down (the step table's own unit set) rather than any assumed list — and the real demo failure modes to detect are discovery failing repeatedly/silently (stale refspec, rate limits, dead remotes) and the service being inactive, not missing timers. Design accordingly when built.

**Detection half LANDED at eb948e8ac** (engineer; foreman-reviewed shared-file diffs; lint 0 issues, full Go suite green, red-proven by mutation). The floor is DERIVED from install's own predicate — checkServiceDone now delegates to the one cli/internal/unitfloor implementation so two notions of unit-correctness cannot drift apart. Announce lives where humans look: operator verbs check/list/schedule (stderr, pipeline-safe; warn-never-refuse on schedule — the queued row is legitimate and runs after the operator repairs with ./sb install) and the daemon at start + poll tick, journaling only on TRANSITIONS in both directions. Typed states with not-Linux/cannot-tell counted healthy deliberately. One self-caught regression during the build: routing the install ladder's drift gate through the OS-gated Inspect silently disabled reconcile off Linux — existing tests caught it; byte-compare and OS gate now sit on opposite sides of a pinned seam. REMAINING (foreman-ruled follow-on, rides the next candidate): the health-surface field and the upgrade page's own warning — both need schema/API work, deliberately not started mid-cut. Ticket stays In Progress for that half.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer
created: 2026-08-29 11:58
---
**Built and frozen. Detection only — the box says it cannot follow its channel, and names `./sb install`. No self-repair anywhere.**

**THE FLOOR IS DERIVED, NOT ASSUMED — and the premise correction on this ticket is why.** I did not invent a unit list. `checkServiceDone` (cli/cmd/install.go:976) ALREADY encoded the floor the install step-table lays down: the templated user unit `statbus-upgrade@.service`, byte-identical to `ops/statbus-upgrade.service`, with its per-user instance active. There is exactly one unit; check scheduling is the service's own ticker plus NOTIFY, and the `statbus-upgrade-check` unit named in the original framing has never existed. So the work was to give that existing predicate a voice, not to build a second notion of correctness.

**ONE IMPLEMENTATION, NOT TWO.** New package `cli/internal/unitfloor` owns the question; `install.go` now DELEGATES to it. Two implementations of "is this box's unit correct" would drift, and the one that drifts silently is the one that stops announcing — the exact failure class this ticket exists to close.

**TYPED STATES, because the remedies differ and "not healthy" is the uninformative signal we are replacing:** `UnitFileMissing` (the demo case — cannot follow at all), `UnitFileDrifted` (running an old definition, stale watchdog/timeouts forever), `Inactive` (installed but not ticking), plus `NotApplicable` (non-Linux) and `UnknownUser` (`$USER` unset). The last two count as HEALTHY on purpose: alarming a developer laptop, or turning "cannot tell" into an alarm, is how a real alert gets trained into noise.

**WHERE IT ANNOUNCES, and why it is not only the service.** A service that does not exist cannot report its own absence — so announcing solely from the daemon would cover every case except the one that cost demo nine days. Hence:
- **Operator verbs** `upgrade check`, `upgrade list`, `upgrade schedule` (cli/cmd/unit_floor_announce.go). These are what a human runs when the page looks stale. To **stderr**, so a warning cannot corrupt a parsed `list` pipeline — a warning that breaks pipelines is a warning people route around.
- **The service**, at start and on the poll tick (cli/internal/upgrade/unit_floor.go). It catches what it can survive: a unit that DRIFTS under a long-running process. Journals **only on a transition**, not every tick — a line repeated each minute is read once and filtered forever, and a signal nobody notices is precisely this ticket's complaint. Restoration is journaled too, so the fix appears beside the complaint.

The message states the gap, what it COSTS (a missing unit reads as harmless until you know it means silent staleness), and the single command that fixes it.

**RED/GREEN.**
- GREEN: 9 tests in the new package, all passing; full Go suite `exit=0`, 14 packages, no failures; `./dev.sh lint` → **0 issues across 17 packages**; `gofmt -l` clean (STATBUS-290's gate is mine — it had flagged my struct-field alignment, now fixed).
- RED, proven not assumed: injecting `Healthy() { return true }` failed exactly the three breach tests (missing / drifted / inactive) and nothing else. File restored, 0 probe markers left.

**A REGRESSION I INTRODUCED AND THE EXISTING TESTS CAUGHT.** My first delegation routed `unitFileMatchesRepo` through `Inspect`, which short-circuits to `NotApplicable` off Linux — so on macOS the install ladder's drift gate answered "matches" unconditionally, silently disabling reconcile. `cli/cmd/unit_reconcile_test.go` failed immediately and was right to. Fixed by splitting the OS-INDEPENDENT byte compare (`FileMatchesRepo`, which `install.go` uses) from the OS-gated inspection (`Inspect`, which the announce uses), and I added `TestFileMatchesRepoIgnoresPlatformAndSystemd` so the seam is defended in the package that owns it, not only by its caller. The OS gate belongs to the announce, never to the byte compare.

**FROZEN — 6 files:**
- NEW `cli/internal/unitfloor/unitfloor.go`, `cli/internal/unitfloor/unitfloor_test.go`
- NEW `cli/cmd/unit_floor_announce.go`, `cli/internal/upgrade/unit_floor.go`
- MOD `cli/cmd/install.go` (delegates; `bytes` import dropped), `cli/cmd/upgrade.go` (3 announce calls), `cli/internal/upgrade/service.go` (import, one state field, start + tick announce)

**NOT BUILT, deliberately, and I want this ruled rather than assumed:** the health-surface field and the upgrade page carrying the warning. Both need a schema/API change, and adding a migration while an rc.17 cut is mid-flight is the wrong moment for a detection-only enhancement. The code-side detection stands alone and is useful today; the UI surface is a clean follow-on.

Not mine in the tree, do not stage with this unit: `cli/cmd/db.go`, `seed.go`, `seed_build.go`, `seed_verify.go`, `sequence_normalize*.go`, `migrations/20260829114700_*`, `test/sql|expected/127_*`, `test/setup.sql`, and the 303 explain + 109 perf baselines (STATBUS-316 and others). I verified the three shared files I touched contain ONLY my changes.
---
<!-- COMMENTS:END -->
