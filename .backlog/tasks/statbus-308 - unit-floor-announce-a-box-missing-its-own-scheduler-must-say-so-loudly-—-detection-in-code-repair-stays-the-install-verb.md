---
id: STATBUS-308
title: >-
  unit-floor-announce: a box missing its own scheduler must say so loudly —
  detection in code, repair stays the install verb
status: To Do
assignee: []
created_date: '2026-08-28 21:43'
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
