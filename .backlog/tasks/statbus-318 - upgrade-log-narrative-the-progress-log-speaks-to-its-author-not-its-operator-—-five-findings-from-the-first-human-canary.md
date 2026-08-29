---
id: STATBUS-318
title: >-
  upgrade-log-narrative: the progress log speaks to its author, not its operator
  — five findings from the first human canary
status: To Do
assignee: []
created_date: '2026-08-29 20:06'
labels:
  - upgrade
  - ops
dependencies: []
priority: medium
type: enhancement
ordinal: 311000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: every line of the upgrade progress log follows one principle — zoom out, then in: first say plainly WHAT is happening at the level an operator thinks at, then give the precise low-level detail. The first human-canary run (Norway, rc.17, read by the King from Erik's install) found five places it fails, none blockers, all real.

THE FINDINGS (all verified present in current master, cli/internal/upgrade/service.go:6393+ and exec.go):
1. INDIRECTION: "Engaging read-only upgrade window (external writes blocked until completion/rollback)..." — the parenthetical is the message. Say it directly: "External writes blocked until completion/rollback."
2. IMPLEMENTATION JARGON: "Stopping listen-loop goroutine (canceling listener context)..." — goroutines and contexts are the author's vocabulary. Describe the machinery's ROLE: e.g. "Stopping the notification listener (the part that hears new-release announcements)..." — simple sentence, what the piece does, then detail if needed.
3. THE ZOOM PRINCIPLE VIOLATED: "Listen-loop goroutine stopped." followed by "Closing listen connection to the database..." — an operator cannot tell what distinguishes these two steps or why both exist. Neither line is the high-level statement, neither is precise-for-a-reason. Restructure the disconnect sequence as one plain what-is-happening line plus its details.
4. MISSING COMPLETION: "Backing up database..." / "Still backing up (Ns elapsed, X copied)..." then straight to "Installing..." — nothing ever says the backup FINISHED, so the operator cannot tell completion from abandonment. Add "Database backed up (X in Ys, at <path>)." (Note: the "0 B copied" in the same lines was the already-fixed statfs bug — Erik's pre-swap phase ran rc.09's old code; no action.)
5. WRONG STORY ON THE PLANNED PATH: "Recovering an interrupted upgrade — found a service marker..." printed during the DESIGNED post-swap handoff (binary swap → exit → fresh process finds its own flag). Nothing was interrupted; the operator reasonably reads a logic error. The code's own comment at service.go:1284 already admits "'interrupted' was misleading for the planned post-swap continuation case" — but the string never followed the comment. Branch the wording: the planned continuation says "Continuing the upgrade under the new binary (planned handoff)"; genuine crash recovery keeps recovery language.

THE STANDING PRINCIPLE to record where the progress writer lives: this log IS the product for the person watching an upgrade — the King's rule: high level first, clearly, then the exact detail for precision; never only one of the two.

Not release-blocking (King's ruling at observation time); rides after the stable.

WHAT IS ACHIEVED: the next operator watching an upgrade reads a story they can follow, and the planned handoff stops accusing itself of having crashed.
<!-- SECTION:DESCRIPTION:END -->
