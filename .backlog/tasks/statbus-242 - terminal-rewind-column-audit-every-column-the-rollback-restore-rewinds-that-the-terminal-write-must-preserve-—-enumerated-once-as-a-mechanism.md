---
id: STATBUS-242
title: >-
  terminal-rewind-column-audit: every column the rollback restore rewinds that
  the terminal write must preserve — enumerated once, as a mechanism
status: Done
assignee: []
created_date: '2026-08-19 00:17'
updated_date: '2026-08-19 10:53'
labels:
  - upgrade-recovery
  - quality-gate
dependencies: []
references:
  - cli/internal/upgrade/service.go
priority: medium
type: enhancement
ordinal: 235000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The rollback's database restore rewinds public.upgrade to a pre-upgrade snapshot, and every terminal write that runs after it silently loses any column not explicitly re-imposed. That mechanism has now bitten twice — recovery_attempts (observed live at rc.03, fixed by STATBUS-181's explicit re-imposition) and backup_path (predicted during the rc.05 arc corrections, fixed by STATBUS-241). A third instance should be impossible, not merely unlikely.

THE ASK (architect's morning ticket from the 241 ruling): a GENERAL answer instead of a third one-column patch when the next instance surfaces. Enumerate once, as a mechanism rather than prose: every column of public.upgrade that (a) is written between the pre-upgrade snapshot and a possible rollback restore, and (b) carries meaning the terminal row must preserve. For each: either the terminal write re-imposes it (from the authoritative carrier — the flag — per the 241 ruling, never a remembered variable), or a recorded reason why the rewound value is correct.

THE MECHANISM SHAPE (builder designs, architect verifies): the strongest form is a pin that fails when a new post-snapshot column write appears without a corresponding terminal re-imposition or exemption — the same every-writer-accounted-for pattern as TestEveryBackupPathWriterIsAccountedFor_STATBUS229. Prose lists rot; the 197 comment-premise lesson applies.

WHAT IS ACHIEVED: the terminal-write path stops being a place where the restore quietly eats one column per incident; the next person who adds a column write learns at test time that the rewind exists.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every post-snapshot column write in the upgrade path is enumerated with its terminal-write disposition: re-imposed (flag-sourced) or exempt-with-reason
- [x] #2 The enumeration is a failing-test mechanism, not prose — a new unaccounted column write goes red until dispositioned
- [x] #3 recovery_attempts and backup_path appear as the two founding entries, citing STATBUS-181 and STATBUS-241
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-19 10:14
---
AUTHORITATIVE ENUMERATION (AC#1), part 1 of 2 — the window and two findings that widen the problem beyond how the founding incidents framed it. Part 2 carries the dispositions.

## The window, precisely

- **OPENS** at `d.backupDatabase(...)` — service.go:5713. The snapshot's contents are the table as it stands at that instant.
- **CLOSES** at `d.restoreDatabase(...)` — service.go:8274 (rollback) and :8705 (abort). The volume rewinds to the snapshot.
- **TERMINAL WRITES** run after the rewind — :2971, :8398, :8428, :8665, :8800 — and are the only chance to re-impose anything.

A write executed between those points is lost unless a terminal write puts it back. The carrier for re-imposed values is the FLAG, never a remembered variable (the 241 ruling); `writeRollbackTerminal`'s contract at :8154-8164 already states this for recovery_attempts.

## FINDING 1 — the restore rewinds the WHOLE TABLE, not the upgrading row

Both founding incidents concerned the row being upgraded, and that framing is too narrow. `restoreDatabase` rewinds the database volume, so EVERY row returns to its snapshot state — including rows the upgrade never touched. Concurrent writers in the window are therefore in scope:

- **`superseded_at` / `state='superseded'`** (:1706, supersedeOlderReleases) — a newer candidate arriving mid-upgrade supersedes older rows; a restore silently un-supersedes them.
- **`dismissed_at`, `skipped_at`** — deliberate human acts. A restore reverts an operator's dismissal with no record it ever happened.

These differ from the derived columns in the decisive respect: **nothing re-derives them.** Discovery recomputes image and build status on its next tick, so losing those is self-correcting. Nobody re-dismisses a candidate on the operator's behalf. Same defect class as STATBUS-181 and 241, one scope wider — and precisely the third instance this ticket exists to make impossible.

## FINDING 2 — a service.go-only scan would be a zero-scope check

public.upgrade is not written solely by the Go service. It is exposed through PostgREST under RLS, and the operator-facing dismiss/skip actions are app writes. **A mechanism that greps only cli/internal/upgrade/service.go would pass while blind to exactly the writers Finding 1 identifies as unrecoverable.** It must either cover the app's write paths as well, or state in its own failure message that it does not — a check must report what it examined (doc-033).
---

author: architect
created: 2026-08-19 10:14
---
AUTHORITATIVE ENUMERATION (AC#1), part 2 of 2 — dispositions and the mechanism shape.

**A — RE-IMPOSED FROM THE FLAG** (in-window write whose meaning must survive):
1. `recovery_attempts` — written :6989 (`+ 1`). Re-imposed as `recovery_attempts = $2` at all five terminals. FOUNDING (STATBUS-181, observed live at rc.03).
2. `backup_path` — written :6526, the single row recorder. Re-imposed via `terminalBackupPathSQL` (:8152) as `$4`. FOUNDING (STATBUS-241).

**B — SUPERSEDED BY THE TERMINAL WRITE ITSELF.** No re-imposition needed; the terminal sets them after the rewind: `state`; `error` (the mid-flight annotations at :6295 and :6249 are overwritten by `error = $1`); `rolled_back_at` (:8428).

**C — OUTSIDE THE WINDOW** (written before the snapshot, therefore contained in it). Verified for the first two: `log_relative_file_path` (:5351) and the claim's `state` / `started_at` / `from_commit_version` (:5198) all execute inside `executeUpgrade` (opens :5323) BEFORE the backup at :5713. Also `scheduled_at`, `recreate`, `discovered_at`. Exempt — the snapshot already holds them.

**D — SUCCESS PATH ONLY, no restore occurs.** `completed_at` and the completion write's `docker_images_status='ready'` (:3306, :6814, :7411). Exempt by construction.

**E — SELF-HEALING DERIVED.** `docker_images_status` (:1682), `release_builds_status` (:4065, :4094), `docker_images_downloaded` (:4437), `commit_tags` / `release_status` (:4225), and the static discovery columns (`commit_sha`, `committed_at`, `summary`, `changes`, `release_url`, `has_migrations`, `commit_version`). Exempt WITH REASON: discovery re-derives each from an external source of truth on its next tick. The reason is "re-derived", NOT "unimportant" — if any of these ever stops being re-derived, its exemption expires with it.

**F — OPEN, to be resolved as the mechanism is built.** `recovery_parked_at`, `recovery_parked_reason` (:7210, :6249), plus the Finding 1 columns `superseded_at`, `dismissed_at`, `skipped_at`. I did not trace every park and abort interleaving to a confident verdict, and I am leaving them explicitly open rather than guessing — an enumeration handed on as fact is the failure mode this campaign has hit repeatedly, mine included. **The mechanism resolves them by construction: unaccounted goes red until dispositioned**, which is stronger than any answer I could assert here and is the whole point of AC#2.

## Mechanism shape

**Scan for write SITES, not columns.** A column can have several sites with different dispositions — `error` at :6295 is in-window and superseded, `error` at the terminals is the superseding write. Key each site by file:line plus the column set it writes, and require every site to carry exactly one of:

- **RE-IMPOSED** — naming the terminal that re-imposes it AND the flag field the value comes from (never a remembered variable);
- **EXEMPT** — naming which of B–E applies, and why.

A new or moved site with no entry goes red, in the same shape as `TestEveryBackupPathWriterIsAccountedFor_STATBUS229`. Per Finding 2, the scan's scope must include the app's write paths or say plainly that it does not.
---

author: engineer
created: 2026-08-19 10:32
---
**BUILT AND FROZEN. One new file: `cli/internal/upgrade/terminal_rewind_audit_test.go`.** Three tests, all green, four RED-verified arms. AC#1/#2/#3 met. **Six sites are dispositioned PENDING-RULING with the question and owner recorded — they are accounted for, not answered, and two of them are findings I did not expect.**

**THE MECHANISM.** A scan of every `public.upgrade` write site, each requiring exactly one disposition: RE-IMPOSED (naming the terminal AND the flag field), or an exemption naming its class and WHY, or PENDING-RULING with a question and an owner. An unaccounted site goes red with instructions. It also fails on **stale entries** — an audit line describing a site that no longer exists is exactly the authoritative-looking prose this campaign keeps tripping over.

**ONE DELIBERATE DEVIATION from the ruling, with reasoning.** Keying by `file:line` would churn on every edit above a site, making this a permanent source of unrelated red and training people to re-bless without reading. Sites are keyed by **(file, kind, COLUMN SET)** — stable under movement, unique per distinct write — and duplicate statements are COUNTED, so a copy of an existing site still goes red. Line numbers appear in the failure message, where they help, not in the key, where they rot. Reject this and I will switch it.

**THREE SCANNER DEFECTS I FOUND BY RUNNING IT** — each would have made the audit lie:
1. **A prose string was read as a write site.** `install.go` documents a violation shape containing the text `INSERT INTO public.upgrade (...)`. Fixed by scanning inside string literals only and validating that column names are real identifiers.
2. **A WHERE-less statement let the match run into the NEXT statement's WHERE**, inventing an eleven-column site that does not exist. Fixed by bounding every match to one string literal.
3. **The five terminals scanned as NOT writing `backup_path`** — their clause lives in the concatenated constant `terminalBackupPathSQL`, invisible to a literal-only scan. An audit that cannot see the re-imposition it exists to track would have been the zero-scope shape all over again. Fixed by resolving the fragment constants (both quoting styles) before scanning, and the loader FAILS LOUDLY if a fragment goes missing — because a silently-unresolved fragment shrinks a column set and drops a tracked column out of the audit.

**FINDING 2 IS COVERED, NOT DECLARED OUT OF SCOPE.** The app writes `public.upgrade` through PostgREST at `app/src/app/admin/upgrades/page.tsx` — verified: `PATCH /rest/upgrade` with `skipped_at`/`dismissed_at`. The test walks `app/src` and fails if the tree is absent rather than passing quietly. **Blind spot named in the code**: a write whose value is an opaque variable would not match the write idioms — stated so that if it ever happens, the reason the audit missed it is already written down.

**TWO THINGS THE SCAN TAUGHT ME THAT THE ENUMERATION DID NOT SAY:**
- **The app writes `state` DIRECTLY** (`state: "skipped"` / `"dismissed"` / `"scheduled"`) alongside the timestamps. **Finding 1 is wider than one column per act**: the operator's decision is carried by state AND the `_at` column, so a re-imposition restoring only the timestamp would leave the row self-contradictory. The ruling should be on the PAIR.
- **`promoteExistingCandidate` and its install-triggered sibling deliberately NULL `dismissed_at`, `skipped_at` and `superseded_at`** when re-arming a candidate. Dispositioned OUTSIDE-WINDOW (scheduling precedes execution), with a note that this is a re-arm rather than a loss — relevant to whoever rules on STATBUS-250's dismissal robustness.

**THE SIX OPEN ENTRIES, resolved by construction as intended** — all now enumerated and each carrying its question: the two park writes, `state,superseded_at` (×2), and the three app writes (`dismissed_at`, `skipped_at`, `state`). I did not self-assign any of them; 250 comment #2's lean toward re-imposing dismissals is cited on that entry.

**RED-VERIFIED, four arms:** a new undispositioned site → red naming it; a COPY of a dispositioned statement → red on the count; a stale entry → red; the app tree absent → red stating it cannot cover those paths. Well-formedness is pinned too: RE-IMPOSED without a terminal + flag field fails, PENDING-RULING without a question + owner fails, and both founding entries must stay RE-IMPOSED citing STATBUS-181 and STATBUS-241 (AC#3).

**VERIFY CHAIN:** `go test -count=1 ./...` 12 packages green; `gofmt -l` clean; `golangci-lint run ./...` 0 issues.
---

author: foreman
created: 2026-08-19 10:44
---
LANDED as b80733ac0 (architect APPROVED through the disposition cycle; final two re-dispositions verified in the file before staging). The audit is a standing gate: every post-snapshot write SITE (not column) in the upgrade path — Go service AND the app's PostgREST paths — carries a disposition, and a new unaccounted site goes red until someone answers for it. Founding entries recovery_attempts (181) and backup_path (241) cited. Dispositions as ruled: park columns RULED-REIMPOSE-OWED (the owed unit queued TRACE-FIRST — whether a restore can follow a park — before any flag-schema change); superseded_at SELF-HEALING with the residual window and the expires-if-the-sweep-leaves-the-tick condition recorded; dismissed_at/skipped_at category C outside-the-window; the state+_at pair ruling folded (chk_upgrade_state_attributes makes a half-re-imposition a FAILED WRITE, not a silent wrong row). All three ACs closed. Scanner honesty properties: zero-site scan fails citing doc-033; missing app tree fails rather than narrowing; unresolvable SQL fragment fails loudly.
---

author: engineer
created: 2026-08-19 10:53
---
**PARK TRACE (read-only, no code changed). VERDICT: NO restore can follow a live park on ANY traced path — with ONE named residual that is a genuine fail-open, not a gap in the design. The park sites' disposition can upgrade to EXEMPT-WITH-PROOF, and the flag-schema change never happens, IF the architect accepts the residual as acceptable or rules it fixed separately.**

**THE WINDOW.** Opens at `backupDatabase` (service.go:5713, inside `executeUpgrade` which opens :5323). Closes at a `restoreDatabase`. The park columns are written by exactly two statements: `parkUpgrade` (:7201, writing :7210) and `appendParkNarrative` (:6246, writing :6249 — which only APPENDS and requires `recovery_parked_at IS NOT NULL`, so it never creates a park).

**FOUR PARK ENTRY POINTS, each returning immediately after the write:**
1. `parkForDeterministicFailure` :5958 — park at :5970, then `parkServiceRecovery`, then returns.
2. `parkServiceRecovery` :5999 — narrative only; **it never restores anything** (no rollback/restoreDatabase/restoreGitState/restoreBinary call in its body).
3. `RecoveryBudgetGuard` :7043 — park at :7124, returns immediately.
4. `resumeNewSb` :7293 — park at :7597, returns `nil` immediately.

**EVERY ROUTE TO A RESTORE IS PARKED-GUARDED. All eight `d.rollback(ctx` sites, walked:**

**(a) `recoveryRollback` :2895 → rollback at :3009.** Carries an EXPLICIT parked refusal before it (:2933-2937): *“upgrade %d is PARKED (%s) — refusing the automatic rollback; the row stays parked and the unit alive-idle.”* It closes the flock, keeps the flag, and returns. **This is the crash-recovery route, and it is guarded at the point of use.**

**(b) `applyNewSbUpgrading`'s rollbacks — unreachable while parked, structurally.** `applyNewSbUpgrading` (:6321) has **exactly ONE caller in the tree**: `resumeNewSb` :7675. And `resumeNewSb`'s parked-skip at :7574 (`else if parked { … return nil }`) sits BEFORE it — so a parked row returns alive-idle and never reaches the function that can roll back. Verified there is **no** `d.rollback(`/`restoreAndFinalize(` anywhere in :7293-7700, so nothing restores between the guard and the return either.

**(c) The earlier self-heal parked check** (:7372) does not create an exposure: parked ⇒ skip self-heal and **fall through to the continuation**, whose budget-section parked-skip is (b)'s guard. The code says so itself at :7369-7371. No restore sits between :7405 and :7574.

**(d) `RecoveryBudgetGuard` :7072** — `if parked { … return true }` before anything else.

**(e) `executeUpgrade`'s five rollbacks** (:5718, :5759, :5792, :5838, :5858) — all PRE-SWAP, and reachable only on a freshly claimed row. **`claimScheduledUpgrade` (:5149) atomically displaces any standing park BEFORE the window opens**: it sets the parked row to `superseded` and NULLs BOTH park columns (:5176-5185, STATBUS-159). So when `backupDatabase` runs at :5713 there is no live park anywhere in the `in_progress` population — the snapshot cannot contain one to lose.

**(f) `parkForDeterministicFailure` :5962 vs :5970** — rollback and park are MUTUALLY EXCLUSIVE branches of one decision: on `ObservedCannotReachNew` it rolls back and **returns** (:5962-5964); the park is the else. A rollback on this path means no park was ever written.

**(g) `parkAtTarget`** (the closure in `completeInProgressUpgrade`, :3226) — all three call sites (:3271, :3284, :3292) are immediately followed by `return`.

**THE RESIDUAL, and it is real.** `recoveryRollback`'s park-state read **FAILS OPEN on ANY error** (:2933-2934): *“park-state read failed … proceeding fail-open with the rollback.”* The justification given nearby is the 42703 bootstrap case — a pre-migrate schema has no `recovery_parked_at`, so the row cannot be parked, which is sound. **But the fail-open is not narrowed to 42703.** A transient read failure against a schema that DOES have the column, at crash-recovery time, on a genuinely parked row, proceeds to `d.rollback` → `restoreDatabase` → and the rewind silently un-parks the row into the deterministic failure it stopped at — STATBUS-229's exact shape.

**So the honest verdict is conditional:** no DESIGNED path lets a restore follow a park; one ERROR path does. Narrowing that fail-open to the 42703 case (or refusing rather than rolling back when park state is unknown on a schema that should have the column) would close it without any flag-schema change — far cheaper than the re-imposition, and it removes the only interleaving I could find. **I have not edited the audit file; the disposition stays RULED-REIMPOSE-OWED until the architect verifies this proof and rules on the residual.**
---
<!-- COMMENTS:END -->
