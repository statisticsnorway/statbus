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

## Investigation findings (buffalo, gpt-6.1-sol xhigh, read-only, 2026-10-06 08:53; full report `tmp/452-investigation.md`)

- **Q1, what cut the old daemon's connection:** most likely step 10 recreating the **proxy**, not the "Database sessions" cleanup or the migration pause.
  - The proxy container was Created at 08:30:29.934 and Started at 08:30:31.251. That overlaps the old daemon's last claim (08:30:29.486, which landed) and its lost `failed` write.
  - The DB had been ready since 08:30:18. `pg_stat_database.sessions_killed = 0`.
  - Status: strong inference. The exact socket close is not recorded.
- **Q2, the false notification:** the callback ran successfully (exit 0) with `STATBUS_EVENT=completed` for v2026.09.3. **Whether Slack actually received it is not established:** the script discards the HTTP response and logs nothing locally. The owner can check the Slack channel.
- **Q3, every reader of "running version":**
  - Reads v2026.09.3 now:
    - `public.running_identity()` (`completed_at DESC`), and through it the app footer (its only consumer)
    - the next install's `from_commit_version` (`install.go:3554`, `completed_at DESC`, no tie-break)
    - the admin stale-install-failure banner cutoff (`page.tsx:243-258`, 08:30:57)
  - Reads rc.16 now: `/admin/upgrades` "Currently running", which orders by `committed_at DESC` and is a different selector.
  - Readers based on the binary or HEAD are unaffected.
- **Q4, the transition guard:** it already allows unparked `in_progress → superseded`, with or without an operator actor. The only thing that excluded row 25829 is `upgrade_supersede_older`'s state filter (`available`, `scheduled`, `failed`, `rolled_back`).
- **Q5, why the rehearsal differed, and exposure:**
  - The operator rehearsal avoided the lost-write window: the refusal was persisted, then superseded. It also accepted rc.16's own row ending `superseded`, so it never proved the running-version ledger correct (a test gap).
  - The service path alone cannot produce two in_progress rows (partial UNIQUE index `upgrade_single_in_progress`).
  - **Norway (healthy v2026.09.3 daemon, `./sb upgrade schedule`) is not expected to hit this.** It is a one-row pipeline, and 09.3 has the pre-claim flock check. This is a source-based conditional conclusion, not a live rune run.
  - The recovery bug can still be reached by any daemon that finds a stale in_progress row after an independent newer install completed. That needs a box with an old looping or crashed claimant plus an operator install, as demo had.
- **Q6, predicate candidates for "overtaken, not finished" (sketches; r is the stale in_progress row, c is a different completed row):**
  - **P1:**
    - `r.commit_sha != binaryCommit`
    - AND a completed c exists with `c.commit_sha == binaryCommit` AND `c.completed_at > r.started_at`
    - AND r is a proven ancestor of the binary
    - Matches demo. A genuine crash-after-swap of r's own target does not match, because binary == r.
  - **P2:** P1 plus `c.started_at > r.started_at`. Stricter, but it can miss a reinstall of an existing row, because COALESCE keeps the old started_at (`install.go:3562`).
  - **P3:** the successor is an ancestor of the binary when the binary has moved on again. Weaker attribution.
  - **Not safe alone:** binary is a descendant of r, any or the latest completed row, id order, committed_at or version order, error text.
  - Evaluate against a re-read current row, because the completion UPDATE is keyed by id and not a CAS.

## Acceptance criteria (draft, finalize after the owner's decision)
<!-- AC:BEGIN -->
- [ ] #1 A reproduction (Go/livedb or rehearsal) shows the orphaned in_progress row being completed by flagless recovery after a newer install, RED on rc.16.
- [ ] #2 After the fix, the overtaken row ends superseded with no success callback, and the running version shown everywhere is the installed one.
- [ ] #3 Demo's ledger is corrected through the released software, and the footer shows rc.16 or later.
- [ ] #4 Independent review MERGE; the release gates and both 436 rehearsals pass on the candidate.
<!-- AC:END -->
