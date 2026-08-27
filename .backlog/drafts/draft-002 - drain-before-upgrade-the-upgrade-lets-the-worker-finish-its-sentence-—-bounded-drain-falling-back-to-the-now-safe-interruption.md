---
id: DRAFT-002
title: >-
  drain-before-upgrade: the upgrade lets the worker finish its sentence —
  bounded drain, falling back to the now-safe interruption
status: Draft
assignee: []
created_date: '2026-08-27 16:14'
labels:
  - upgrade
  - worker
dependencies: []
priority: medium
type: enhancement
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AWAITING THE KING'S RULING (his question, 2026-08-27, leaving for the evening: "we can't run the upgrade now because work is pending — or what is a principal way to handle this?"). Architect's design, prepared for the evening walkthrough:

THE ANSWER: his instinct is right, and its principled form is FINISH the work, not refuse the upgrade. Refusing is the wrong shape three ways (a long import makes a box permanently un-upgradeable; a recurring refusal invites a bypass flag on an upgrade guard; the box's own work would prevent its maintenance) — and decisively, refusing doesn't work: check-then-stop is a race, and making it reliable requires first stopping intake, i.e. quiescing — at which point you may as well proceed. Option (a) done properly BECOMES option (b).

THE DESIGN: drain, bounded, falling back to what we have. (1) Worker finishes current tasks, claims nothing new; (2) bounded wait; (3) drained → upgrade a genuinely quiet box; (4) bound expires → proceed anyway, because interruption is now safe by construction (264+265). No state exists where a box refuses maintenance; worst case is today's behaviour, which is safe.

VERIFY BEFORE BUILDING — we may already own most of it: the upgrade runs docker compose stop (service.go:5834), which is graceful SIGTERM + timeout-kill. Questions: does the worker's shutdown handler finish its current task or abandon it (264 is shutdown-aware — something is there)? Is the ~10s default stop timeout simply too short for minute-long tasks? If the handler drains and only the timeout is short, this whole design is A TIMEOUT VALUE AND A VERIFICATION, not a new protocol.

OPERATOR SURFACE (the deciding argument in the King's frame): "Finishing current work before upgrading…" is what any competent person would do and needs no explanation; "Cannot upgrade: work is pending" alarms and strands; "your import will be redone" invites a support question.

HONEST PRIORITY: worth doing, NOT urgent — the wedge is closed by 264+265; this buys cleanliness (no manufactured interrupted work, faster convergence, unambiguous canary observation), honestly labelled as such. Nothing is at risk in waiting until after the stable ships.
<!-- SECTION:DESCRIPTION:END -->
