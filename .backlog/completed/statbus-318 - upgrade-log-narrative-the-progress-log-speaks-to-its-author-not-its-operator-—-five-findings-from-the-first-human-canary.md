---
id: STATBUS-318
title: >-
  upgrade-log-narrative: the progress log speaks to its author, not its operator
  — five findings from the first human canary
status: Done
assignee: []
created_date: '2026-08-29 20:06'
updated_date: '2026-08-29 20:14'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer
created: 2026-08-29 20:13
---
**All five findings built and frozen.** No test or expected output pinned any of these strings — I grepped cli/, test/, app/ and ops/ first; every one appeared exactly once, in service.go.

**1. INDIRECTION.** `Engaging read-only upgrade window (external writes blocked until completion/rollback)...` → **`External writes blocked until completion/rollback.`** The aside was the message; it is now the message.

**2. JARGON.** `Stopping listen-loop goroutine (canceling listener context)...` → **`Stopping the notification listener — the part that hears new-release announcements.`** What the machinery DOES, not what it is called in the source.

**3. THE ZOOM PRINCIPLE.** The old sequence emitted `Listen-loop goroutine stopped.` then `Closing listen connection to the database...` — two adjacent lines where neither is the headline and neither earns its precision. What is actually happening is ONE thing, so it now reads as one headline with its details indented beneath:

    Disconnecting from the database so it can be stopped.
      Stopping the notification listener — the part that hears new-release announcements.
      Listener connection closed.
      Query connection closed.

**4. MISSING COMPLETION.** Added **`Database backed up (X in Ys, at <path>).`** Placed immediately after the atomic syncing→active rename, because that rename IS the completion by the code's own definition ("the snapshot is COMPLETE iff it is named active") — announcing earlier would report a finish that had not happened. It reuses the SAME statfs delta and the same clock the "Still backing up" heartbeats use, so the closing number is continuous with the ones before it rather than a second, differently-derived figure the reader must reconcile.

**5. THE WRONG STORY — message logic, handled as such.** I read how the entry point distinguishes the cases before writing anything. The discriminator is `flag.Phase`, and it is exact rather than inferred (service.go:278-289):
- `PhaseNewSbSwapped` — *"stamped after binary swap, before exit-42 handoff"*. A fresh process meeting this flag is meeting a marker its own predecessor left one moment earlier. **The design working. Nothing was interrupted.**
- `PhaseNewSbUpgrading` — the resume began and that process **died**. Genuine crash.
- `PhaseOldSbUpgrading` — crash before the swap, on the old binary. Genuine crash.

So: planned continuation → **`Continuing the upgrade under the new binary (planned handoff).`**; the other two keep recovery language, because the word has to stay meaningful for the day something really has crashed. Both branches keep the identifier suffix — high level first, exact detail after.

I extracted the wording into a pure `recoveryOpeningLine(flag, holder)` (new `recovery_wording.go`) rather than leaving a branch inline in a DB-dependent function, so the logic is directly testable and cannot silently drift back.

**RED/GREEN on the branch, as required.**
- GREEN: 3 new structural tests pass — planned handoff must not say "interrupted" or "recovering" and must lead with the plain statement before `(detail:`; genuine crashes must keep recovery language; and a table pinning that ONLY the swapped phase is planned, so a future phase added to the enum cannot inherit "planned" by falling through.
- RED, proven not assumed: disabling the branch (`if false`) failed exactly the planned-handoff assertions and the phase table, while the crash-language tests correctly still passed. Restored, 0 markers left.

**THE STANDING PRINCIPLE is recorded where the progress writer lives** — `ProgressLog.Write` in progress.go, not at one call site. It states the rule (high level first, clearly, then the exact detail; never only one of the two) and lists the five failure shapes this canary found, so the next person writing a line here has the whole pattern in front of them.

**VERIFICATION:** `gofmt -l` clean, `go build` clean, full Go suite `exit=0` across 14 packages, `./dev.sh lint` **0 issues across 17 packages**.

**FROZEN — 5 files:** MOD `cli/internal/upgrade/service.go`, `cli/internal/upgrade/exec.go`, `cli/internal/upgrade/progress.go`; NEW `cli/internal/upgrade/recovery_wording.go`, `cli/internal/upgrade/recovery_wording_test.go`.

**COMMIT-ORDER NOTE for the foreman:** `service.go` now carries BOTH this unit and the still-uncommitted STATBUS-308 work (import, one state field, start/tick announce). The two cannot be separated by file path — they are separate hunks in one file. Commit 308 and 318 together, or split by hunk; either is fine, but it needs a deliberate choice rather than a `git add <file>`.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
LANDED at 6c89bffe5, the night it was found. All five findings fixed: the read-only line says its message directly; the notification listener is described by role, not source vocabulary; the disconnect sequence follows the zoom principle (one plain headline, indented precise details); the backup announces completion at the atomic syncing→active rename — the code's own definition of complete — using the same statfs delta as its heartbeats; and the recovery opening branches on the EXACT discriminator (flag.Phase, service.go:278-289): only PhaseNewSbSwapped says "Continuing the upgrade under the new binary (planned handoff)", while genuine crash phases keep recovery language so the word stays meaningful when something has actually crashed. The wording lives in a pure recoveryOpeningLine function with structural tests (planned may never say interrupted/recovering; crashes must; a phase table pins that only the swapped phase is planned, so a future enum value cannot inherit 'planned' by fall-through) — red-verified on the branch. The King's standing principle is recorded at ProgressLog.Write itself with all five failure shapes listed, so the next line-writer sees the whole pattern. None of the five strings were pinned anywhere (grepped before editing); zero expected files moved. Rides rc.18 for the King's morning install — the log he reads tomorrow is the one his findings rewrote.
<!-- SECTION:FINAL_SUMMARY:END -->
