---
id: STATBUS-323
title: >-
  install-fetch-race: install.sh's git fetch loses to the live upgrade service's
  discovery fetch — quiesce the service before touching the repo
status: Done
assignee: []
created_date: '2026-08-31 11:11'
updated_date: '2026-08-31 11:50'
labels:
  - ops
  - upgrade
  - install
dependencies: []
priority: medium
type: bug
ordinal: 316000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: a bootstrap install cannot be raced by the very service it is replacing. Observed live on ma (2026-08-31, fleet convergence): install.sh's `git fetch origin --tags` (line 293) failed with `cannot lock ref 'refs/remotes/origin/master': is at 3bd85bfae but expected 376a18c38` — the box's still-running upgrade service fetches the same repo on its ~2-minute discovery tick (journal-confirmed ticks throughout the install window), and the two fetches collided on the ref. et and jo, run minutes earlier with identical commands, simply won their races.

THE MIXED STATE IT LEAVES, worth recording because it looked scarier than it was: the binary had already been swapped (sb at v2026.08.0, sb.old preserved) but the worktree stayed at the old tag and ./sb install never ran — box kept serving on the old stack, translation not run, ledger rows oddly 'skipped'. Recoverable by stop-service + retry (proven on ma).

THE FIX, in code: the bootstrap path (install.sh, and/or the cloud.sh install wrapper) STOPS the box's upgrade unit before its first repo operation and lets the install's own tail restart it — the same quiesce-the-owner principle the upgrade service itself applies before touching the stack. A retry-once-on-ref-lock band-aid is explicitly NOT the fix (it narrows the window without closing it, and a fetch race can bite any repo operation after it too).

Also worth a look while in there: whether ./sb install's step-table should refuse or warn when the upgrade unit is ACTIVE at bootstrap time — the arriving job checking for itself, same principle as 246/307.

Operational mitigation already standing (foreman ruling during the convergence run): stop-the-unit-first is step 1 of the fleet install procedure for all remaining slots.

WHAT IS ACHIEVED: the bootstrap owns the repo for its duration, and the race class dies in code instead of living in a runbook.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer
created: 2026-08-31 11:49
---
**Rebuilt on the flock per the architect's ruling. Frozen, all four constraints satisfied.** install.sh now TAKES THE MUTEX and never signals the service.

**Constraint 4 first, because it decided the size of the job — the Go side needs NOTHING.** `acquireOrBypass` is at install.go:484 with `defer releaseFlag()` at :488; the step table is built at :663 and executed at :732. So `runCloneRepo` (clone + configureDeployFetch) and `runGenerateEnv` (the :1126-1132 fetch/checkout/merge) both already run INSIDE the protected region. A second acquire would EWOULDBLOCK against itself, exactly as CLAUDE.md warns. Nothing added there.

I also checked whether install.sh's git work could simply move into that region and be covered for free: it cannot. `runGenerateEnv`'s fetch/checkout only fires when HEAD is on `master` or an `ops/` branch (install.go:1125), and install.sh checks out `current` at the target tag — so on a normal box the Go block does not fire, and the version checkout genuinely belongs to the shell. The shell therefore has to hold the lock itself.

**Constraint 1 — the state-marker hole, which shaped the implementation.** The flag is opened `exec 9<>` (O_RDWR|O_CREAT, **no truncation**), so a live upgrade's existing record survives our opening it, and on winning we write the SAME install-held record the Go side writes: `holder="install"`, `trigger="install"`, `id=0`, matching `AcquireInstallFlag`. So the file's presence can never be misread as a service upgrade in flight — it closes via the holder field exactly as ruled. `exec 9>` would truncate and is explicitly pinned against.

**Constraint 2 — portability.** No `flock(1)` anywhere. It uses dev.sh's proven idiom: bash opens the fd, perl fdopens it (`open(my $f, "<&=9")`) and takes flock(2). Works on macOS and Linux; when perl is somehow absent it degrades with a warning rather than failing the install.

**Constraint 3 — never block silently.** Non-blocking `LOCK_EX|LOCK_NB` first. On contention it prints what is happening, echoes the holder record, notes that an upgrade can hold it for minutes, and gives `lsof` — and only then blocks.

**Released before the Go installer runs**, since that command acquires the same mutex; holding it across would deadlock us against ourselves.

**RED/GREEN.** 8 tests, all passing:
- 6 structural (house genre, line-based and comment-aware): lock precedes every repo op; **install.sh never stops a unit** (this pins the ruling itself — any future "quiesce" that reintroduces `systemctl stop` fails); the install-holder record is written; contention is announced before blocking; release precedes the Go installer; the portable idiom is used.
- 2 behavioural, proving the mechanism rather than the prose: a second acquirer is REFUSED while held, and the lock is granted again after the holder tree is SIGKILLed with no cleanup path — the property a pidfile cannot offer. Plus: opening the flag preserves an existing record byte-for-byte.

**A test that was wrong in an instructive way.** My first behavioural test killed only the holder's bash and expected the lock free; it was still held — correctly, because the `sleep` child inherited fd 9. That is dev.sh's documented FEATURE (a SIGKILLed parent whose child is still mutating the DB keeps the lock, where a pidfile would false-reclaim mid-mutation). The test now kills the process GROUP and asserts release on process-TREE death, which is the real property.

**VERIFICATION:** `bash -n install.sh` OK; `gofmt -l` clean; full Go suite `exit=0` across 14 packages; `./dev.sh lint` **0 issues across 17 packages**.

**FROZEN — 3 files:** `install.sh` (M), `cli/cmd/install_quiesce_order_test.go` (NEW), `cli/cmd/install_repo_lock_behaviour_test.go` (NEW).

**FOR THE COMMIT MESSAGE, per the ruling — the runbook stop-first step RETIRES, and why it looked safe:** stopping the unit first was fine on the boxes it was used on only because their old binaries could never have had an upgrade in flight — a property nobody checked at the time. Recorded because without the circumstance, "we did it before and it was fine" becomes the argument for doing it again where the circumstance no longer holds.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
LANDED at d5ad22c63 — and the fix that shipped is NOT the fix the ticket prescribed, on the engineer's refusal and the architect's ruling. The prescribed stop-the-unit was the rune deploy-stop footgun install.sh's own header forbids (SIGTERM → in-flight upgrade rolls back over the live DB), and the guarded-stop variant was TOCTOU with exactly that window. Shipped instead: the bootstrap acquires the SAME advisory lock the upgrade machinery already contends on (tmp/upgrade-in-progress.json's flock) — perl-flock on a bash-opened fd (dev.sh's proven macOS-safe idiom), opened WITHOUT truncation, writing the install-held holder record so the flag file's dual role as the state ladder's marker cannot be misread; non-blocking first with a loud holder-naming wait; released before the Go installer, which takes the same mutex itself. The Go side needed nothing — its repo operations already sit inside acquireOrBypass's region (verified at install.go:484/:663/:732), and the tempting move-the-shell-work-into-Go shortcut was tested and refuted (runGenerateEnv's fetch only fires on master/ops branches; the version checkout genuinely belongs to the shell). Tests pin the RULING as well as the mechanism: install.sh may never contain a systemctl stop; second acquirer refused while held; lock survives holder-alone death (child keeps it — the pidfile false-reclaim this prevents) and releases on process-tree SIGKILL. The fleet runbook's stop-first step RETIRES, with the why-it-looked-safe circumstance on record in the commit. The escalation itself — building the prescribed fix, then refusing to ship it against doctrine the builder went and found — is the review gate doing its job.
<!-- SECTION:FINAL_SUMMARY:END -->
