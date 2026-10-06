---
id: STATBUS-452
title: >-
  installer overtakes an orphaned in_progress row; the new daemon's flagless
  recovery then marks that older version completed, so the ledger and footer
  report the wrong running version
status: To Do
assignee: []
created_date: '2026-10-06 08:45'
labels:
  - upgrade
  - install
  - ledger
dependencies: []
references:
  - STATBUS-436
  - STATBUS-447
  - STATBUS-442
  - STATBUS-039
priority: high
---

## Status: OWNER DECISION PENDING. No code until the owner picks an approach (owner, 2026-10-06 08:35).

## Zoom out

On 2026-10-06 at 08:29:50 UTC the owner ran `./cloud.sh install demo v2026.10.0-rc.16`. Demo is repaired in substance:
- binary, HEAD, the resident daemon's executable and all containers are rc.16 `7e92d115`
- the maintenance flag is absent
- the false v2026.09.3 loop stopped: no activity on row 25829 after 08:30:57
- the legacy secrets moved to `.env.credentials`
- unit NRestarts 0

The ledger is wrong, though. Row 25829 (v2026.09.3) ended `completed` at 08:30:57, eight seconds after rc.16's own row (227493, completed 08:30:49). As a result:
1. The site footer shows "Statbus version v2026.09.3 (ebe058af)". It reads `public.running_identity()`, which returns the latest `completed` row by `completed_at`.
2. `/admin/upgrades` "Currently running" shows rc.16 (`history.find(u => u.state === "completed")`, a different ordering). The two views disagree.
3. The new daemon fired the success callback (`UPGRADE_CALLBACK=./ops/notify-slack.sh`) for "Upgrade to v2026.09.3 complete". A false Slack message was probably sent; not yet verified.
4. The next install's row gets `from_commit_version` from the latest completed row (`cli/cmd/install.go:3554`), so it would say "from v2026.09.3".

## Zoom in: timeline (demo journal, upgrade_state_log, install log)

- 08:29:54: the old v2026.09.2 daemon (PID 3288378) claims row 25829 again. `install.sh` prints "Waiting for the upgrade mutex — another party holds it", then "Upgrade mutex acquired; continuing". The 447 handoff waited and never killed anything, as designed.
- 08:30:16: the db container is recreated (step 10 "Apply config changes": db, worker, app and proxy recreated).
- 08:30:23–08:30:29: the old daemon keeps looping (state-log rows 801715–801726: claim, fail, reschedule).
- 08:30:29.486: its last claim, scheduled → in_progress (row 801727). It is refused with "another ./sb install is already running (install, invoked_by=install.sh:statbus_demo)", which is correct (447).
- 08:30:30: "Database connection lost". **Its `failed` write never lands**, so the row stays `in_progress`. It logs "removeUpgradeFlag: upgrade flock held by another live actor — leaving the flag file in place".
- 08:30:49: the installer records rc.16 row 227493 `completed`. The install output has **no "Superseded" line**: `upgrade_supersede_older` only touches `available`, `scheduled`, `failed` and `rolled_back`, never `in_progress`.
- 08:30:50: the unit restarts on rc.16 (PID 3639343).
- 08:30:55: the new daemon's boot runs `completeInProgressUpgrade` (flagless recovery) and logs "Service restarted. Found in-progress upgrade to v2026.09.3, verifying...".
  - `verifyUpgradeObservedStateEx` says the binary 7e92d115 is a **descendant** of 09.3 ebe058af (`git merge-base --is-ancestor`) and all migrations are applied, so the row counts as at target (`ObservedAlreadyAtNew`).
  - The health check passes.
- 08:30:57: row 25829 is set `completed` ("upgrade row [completed-from-in-progress]"), `runUpgradeCallback` fires, and the daemon logs "Upgrade to v2026.09.3 complete (verified serving after flagless recovery)."

## Defects (three, layered)

1. **Installer leaves an orphaned older `in_progress` row behind.** While the installer holds the upgrade mutex, no other row can legitimately be `in_progress`, so any such row is orphaned (its claimant lost the race or died). The installer's post-install supersede skips it.
2. **Flagless boot recovery completes an overtaken row.** Treating "binary is at or after the target" as "this row's upgrade finished" is deliberate (STATBUS-039) for a crash after the binary swap. It is wrong when a different, newer install completed in between: rc.16's row completed at 08:30:49, after 25829's last claim at 08:30:29. Recovery marks the older row completed and announces it.
3. **"Which version is running" has no single source of truth.** `running_identity()` takes the latest `completed_at`. The upgrades page uses a different order. Whichever row completed last wins, not the version actually running.

## Why the rehearsal passed and demo did not

In the rc.16 operator rehearsal, the old daemon's refusal was recorded as `failed` and the installer then superseded it. On demo, the old daemon's last claim landed just before its DB connection was cut, so `failed` was never written. This is timing-dependent. What cut the connection at 08:30:30 is **not yet verified**. Candidates: step 12 "Database sessions" (`cleanOrphanSessions` / `pg_terminate_backend`), or the traffic pause before Migrations.

## Options (owner to choose; they can combine)

- **A. Recovery side:** in flagless recovery, if a newer `completed` row exists that the running binary belongs to, mark the stale row `superseded`, not `completed`, and fire no success callback. This fixes defect 2.
- **B. Installer side:** after recording its own completed row, while still holding the mutex, also supersede older `in_progress` rows. They cannot be live because the installer holds the mutex. Needs the transition guard (`upgrade_guard_operator_transitions`) to permit `in_progress → superseded` for the install actor. This fixes defect 1 at the source.
- **C. Display:** derive the running version from the actually running commit (for example, the row whose `commit_sha` equals the installed binary or HEAD), not from `completed_at` order, and use one selector for the footer and the upgrades page. This fixes defect 3.
- **D. Demo's existing bad row:** repair it through the fixed software, for example a ledger-repair step in the next install, not hand-written SQL. A forward repair must also be correct for any box that hit this.

The agent's recommendation is A + B (both ends of the race), and C as its own decision, then D through the release that carries them.

## Open facts being verified (investigator, read-only)

- What cut the old daemon's DB connection at 08:30:30.
- Whether `ops/notify-slack.sh` actually posted a "v2026.09.3 complete" message.
- Every reader of "current/running version" (SQL, Go, app).
- Whether the guard allows `in_progress → superseded`, and for which actor.
- Whether the same race can hit the service path or Norway's canary.

Report: `tmp/452-investigation.md`.

## Acceptance criteria (draft, finalize after the owner's decision)
<!-- AC:BEGIN -->
- [ ] #1 A reproduction (Go/livedb or rehearsal) shows the orphaned in_progress row being completed by flagless recovery after a newer install, RED on rc.16.
- [ ] #2 After the fix, the overtaken row ends superseded with no success callback, and the running version shown everywhere is the installed one.
- [ ] #3 Demo's ledger is corrected through the released software, and the footer shows rc.16 or later.
- [ ] #4 Independent review MERGE; the release gates and both 436 rehearsals pass on the candidate.
<!-- AC:END -->
