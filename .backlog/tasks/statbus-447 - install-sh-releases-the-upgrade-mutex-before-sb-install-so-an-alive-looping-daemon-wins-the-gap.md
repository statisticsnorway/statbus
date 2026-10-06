---
id: STATBUS-447
title: >-
  install.sh releases the upgrade mutex before ./sb install, so an alive
  looping daemon wins the gap and the official repair is refused
status: In Progress
assignee: []
created_date: '2026-10-05 10:20'
labels:
  - install
  - upgrade
  - field-report
  - operator-experience
dependencies: []
references:
  - STATBUS-039
  - STATBUS-436
priority: high
---

## Issue

The owner ran the official repair on demo (2026-10-05 10:17 UTC, `./cloud.sh install demo`, resolved to v2026.10.0-rc.14). It was refused:

    Waiting for the upgrade mutex — another party holds it.
    Upgrade mutex acquired; continuing.
    Installed program: sb version v2026.10.0-rc.14 (commit 7ccc9da0)
    HEAD is now at 7ccc9da09 ...
    An upgrade is already running. Wait for it to finish, then retry if needed.
    The installation stopped before it could finish.

Demo's resident v2026.09.2 daemon is ALIVE and looping. It claims row 25829, takes the upgrade mutex, refuses (the false STATBUS-436 capture), and releases. Then it does it again, ~1.9 s apart. It holds the mutex for ~1.7 s of every ~1.9 s cycle. NRestarts stays 0, because the process never dies.

### Mechanism (code facts)

- `install.sh`'s `statbus_repo_lock_acquire` (line ~448) opens `tmp/upgrade-in-progress.json` on fd 9 and takes `flock LOCK_EX` (blocking after a contended non-blocking try, line ~471-510). It swaps `./sb`, then checks out the target.
- `statbus_repo_lock_release` (called at line ~784) **closes fd 9, releasing the mutex**. `./sb install` starts only after that (line ~818/821).
- In that gap, which includes `./sb install`'s startup, settings restore and DB probe, the looping daemon re-takes the mutex.
- `./sb install`'s `install.Detect` (cli/internal/install/state.go ~146) sees the flag with a held flock (`upgrade.IsFlockHeld`, service.go ~1836) → `StateLiveUpgrade` → refusal (`logInstallState`, cmd/install.go ~3939). Every operator retry loses the same race.
- The existing safe takeover (STATBUS-039, cmd/install.go ~667, `upgradeUnitCrashLooping` in cmd/install_upgrade.go ~727) only fires on `NRestarts ≥ 3`, a crash-LOOPING unit. An alive loop has NRestarts=0, so it never fires.

State after the refusal: demo's checkout and on-disk binary are at rc.14, the old daemon (deleted binary inode) still loops, containers and data are untouched, and no maintenance flag is stuck. Consistent and harmless, but not repaired.

## Live measurements (read-only, demo 2026-10-05 ~10:58 UTC, row 25829, `public.upgrade_state_log`)

| window | `failed` transitions |
|---|---|
| 1 min | 32 |
| 3 min | 95 |
| 5 min | 161 |
| 10 min | 316 |

Median gap between failures: 1.90 s (min 1.65, max 2.15). Actor: 100% `statbus-upgrade-daemon-3288378`.

Comparison: the peak re-attempts of ONE row on healthy boxes (`in_progress` entries in any window). Legitimate cases peak at 8 in 5 min. Loops run at 160–184 in 5 min.

| box/row | what | peak 3 min | peak 5 min |
|---|---|---|---|
| dev 331014 (Jul 13) | waiting for CI images, `in_progress→available` every ~10 s, then rolled back | 7 | 8 |
| rune 222 (Jul 13) | 3 tries in 18 s | 3 | 3 |
| dev 447610 | 2 tries over 8 min | 2 | 2 |
| rune 43727 (Sep 22, ~6 h) | alive loop, 11,918 attempts | 111 | 184 |
| dev 453274 (Sep 18-20, ~2 d) | alive loop, 52,525 attempts | 103 | 167 |

## Design decision (owner, 2026-10-05): remove the race, do NOT detect-and-kill

A count-based takeover ("> 5 failed in 5 min → SIGKILL the lock holder") was rejected after simulating the owner's inverse case.

The counter-example: a person makes 6 manual attempts that fail, then starts a HEALTHY upgrade, which holds the lock mid-migration when the installer runs. The failure count describes the past, but a takeover kills the CURRENT holder. That would kill a legitimate upgrade.

Simulation (real flock in Perl, demo's measured cadence: lock held 1.7 s of every 1.9 s; script `tmp/lock-sim-447/sim3.pl`, with `sim2.pl` for the inverse; copy in tmp/ because scratch is ephemeral):

| design | A: alive looping daemon | B: inverse (manual failures, then a healthy holder) |
|---|---|---|
| today (lock released before `./sb install`) | REFUSED (reproduces demo) | waits, then runs ✅ |
| count takeover | works | **kills the healthy upgrade** ❌ |
| gapless handoff | install.sh wins the lock in the loop's ~0.2 s pause; the loop's attempts then fail harmlessly against the held lock; `./sb install` runs ✅ | waits for the healthy upgrade, then runs ✅ |

Decision: **gapless handoff**. `install.sh` keeps the mutex and hands it to `./sb install` without releasing it. No thresholds, no heuristics, nothing box-specific: it is the official installer for every box. The existing NRestarts crash-loop takeover stays as it is (a crash-looping holder is by definition not progressing).

## Implementation plan (each step concrete)

1. **install.sh:** do not release the mutex before `./sb install`. Keep fd 9 open (no `statbus_repo_lock_release` before line ~818/821). Pass the handoff to the child explicitly: export an env var naming the inherited descriptor and the holder token, e.g. `STATBUS_INSTALL_MUTEX_FD=9` plus `STATBUS_INSTALL_MUTEX_TOKEN=<random>`. Write the same token into the flag record `install.sh` writes (`_statbus_write_install_flag`, line ~442; add a `handoff_token` field). Release only after `./sb install` returns (the existing release at line ~836 stays as the final release).
   - Edge: when install.sh **did not** win the lock (the perl-missing path, "continuing without it", line ~507), it sets no handoff env, so `./sb install` behaves as today.
2. **`./sb install` (Go):** at startup, if `STATBUS_INSTALL_MUTEX_FD` and the token are set:
   - verify that the fd refers to `<projDir>/tmp/upgrade-in-progress.json`: fstat the inherited fd and compare dev+inode with the path (the canonical inode check that `openCanonicalFlagLocked` already does);
   - verify that we hold `LOCK_EX` on it (a flock on our own fd succeeds re-entrantly; a non-blocking flock on a fresh open returns EWOULDBLOCK);
   - verify that the flag record carries `holder=install` and the same token.

   If all three hold, adopt the lock as our own `FlagLock`. Then `install.Detect` must NOT read our own inherited hold as a live upgrade: pass the adopted lock into detection, or give `ReadFlag`'s liveness an explicit "held by us" result, so the state classifies by the DB as for a normal install. Any mismatch (wrong inode, not held, token mismatch, holder≠install) → ignore the handoff, log one clear line, and fall back to today's behavior. **Never adopt a lock we cannot prove is ours.**
   - The step table's own `acquireOrBypass` (cmd/install.go ~363) must reuse the adopted lock rather than trying to take it again and blocking on ourselves.
   - The inline scheduled dispatch, `executeUpgrade`'s own `writeUpgradeFlag`, and crash recovery must not deadlock against the adopted install-held lock. Check how `AcquireInstallFlag` (service.go ~1669) and the pipeline's flag rewrite interact. The pipeline already rewrites the flag while holding the flock (`updateFlagNewSbSwapped`); mirror that.
3. **The daemon is unaffected:** while the lock is held, its attempts fail fast as today (`Could not acquire upgrade-mutex flag file: another ./sb install is already running`). At the end, `./sb install`'s final act (STATBUS-432) restarts the unit onto the new binary, which ends the loop.
4. **cloud.sh misleading hint (cloud.sh ~678):** "If this failed because of an invalid signing key, re-run with FLEET_TRUST_KEY_USER=jhf" is printed after ANY failed install when no trust user resolves. Print it only when the install output shows a signature-verification failure. Grep the actual signature-failure text in install.sh / `sb` and match on it in the captured install output. It is a hint, so text-as-data is fine.
5. **Rehearsal honesty:** the STATBUS-436 scenario `5-install-source-image-identity-proof.sh`, function `run_official_installer`, retries on "An upgrade is already running". That retry hid this race. Remove the retry: the operator's single command must succeed first time, so any refusal is a FAIL with the full output preserved.

## Tests (both scenarios, as the owner required)

- **Go unit test (cmd):** a handoff adoption test. Create the flag, take `LOCK_EX` on an fd, and spawn the real `./sb install` adoption path with the env, as a seam or child process. Assert:
  - the lock is adopted
  - Detect does not return `StateLiveUpgrade`
  - token mismatch, wrong inode and not-held cases each fall back to today's behavior and never adopt
- **Shell test (test/install or the harness self-test tier, no VM):**
  - **(A)** a fake looping holder takes and releases the flock on demo's measured cadence (1.7 s held, 0.2 s free), while install.sh's lock functions plus a stub `./sb install` (which records whether it saw the lock as free, live, or inherited) run once. It must complete with no retry. It must be RED on current master (reproduces "already running").
  - **(B)** the inverse: 6 quick holder cycles, then a holder keeping the lock 12 s. The installer must WAIT and never kill or steal; it starts only after the holder releases.
  - Reuse the Perl flock model from `tmp/lock-sim-447/` as the starting point.
- **Guest proof:** the STATBUS-436 operator path (`CANDIDATE_PATH=operator`), with retries removed, against the candidate carrying this fix. One installer run must complete against the live loop.

## Acceptance criteria

- [x] #1 install.sh hands the held mutex to `./sb install` with no release in between, and `./sb install` adopts it only when the inherited fd, inode, flock and token all prove it is ours.
- [x] #2 Scenario A (alive looping holder at demo's cadence): one installer run completes, no retry, RED on master. Scenario B (healthy holder after manual failures): the installer waits and never kills or steals the lock.
- [ ] #3 The STATBUS-436 rehearsal no longer retries, and the operator path passes against the candidate in a single installer run.
- [x] #4 cloud.sh prints the signing-key hint only on a signature-verification failure.
- [ ] #5 The owner's official `./cloud.sh install demo <candidate>` repairs demo in one run, observed over ≥10 min: binary, checkout and resident daemon at the candidate; v2026.09.3 row superseded; zero refusals; **the site is usable** (a page loads and stays; not judged by HTTP status).

## Implementation Notes

2026-10-05 12:59 UTC: first implementation on branch `fix/447-gapless-handoff` (worktree `$JCODE_SCRATCH_DIR/fix-447`):
- d5f71126e `install:` the gapless fd-9 handoff, with Go adoption after inode, flock, holder and token proof; held-aware detection; reuse on the inline dispatch, recovery and restore paths; a private re-exec continuation; CLOEXEC on ordinary children.
- 805c244ce `ops:` the cloud.sh signing hint, shown only on a signature failure.
- 97320803f `test:` `test/install-recovery/tests/install-gapless-handoff-test.sh`, added to harness-selftest.yaml. With real flocks, scenario A fails on master ("already running") and passes on the branch in one run. Scenario B waits for a 12 s healthy holder. The rehearsal retry is removed.

The worker also corrected `fresh-installer-test.sh` expectations. That test was already red on master (verified independently), and the new strings match the current product output.

2026-10-05 13:09 UTC: adversarial review BLOCK (`tmp/447-review.md`). The core design passed: inode replacement keeps the canonical path continuously locked, there is no self-deadlock, and both scenarios hold. It blocked on fd ownership, in three ways:
1. The adoption wrapped the environment-nominated fd with `os.NewFile` and closed it on rejection, which can close an unrelated reused descriptor (reproduced).
2. A successful adoption left the private fd/token environment exported to later children.
3. A stale `STATBUS_UPGRADE_MUTEX_FD=9` alongside a valid install handoff on fd 9 closes the valid fd and recreates the refusal.

Fix in progress: validate on a duplicate fd, never close the original on rejection, and unset both environment pairs on every attempt. Subprocess tests are required.

Separate: the un-park arc's false failure on rc.14 (a statfs read immediately after `rm` on btrfs) is fixed on branch `test/unpark-arc-btrfs-free` with a poll of up to 60 s. Review: MERGE (`tmp/unpark-arc-review.md`).

2026-10-05 ~14:30 UTC: the fd-ownership fix landed (3328112e0): validation on a duplicate fd, the original never closed on rejection, and both env pairs consumed on every attempt, with subprocess tests. Re-review: MERGE (`tmp/447-review.md`). Merged onto master as 483824feb, cafa33889, 784ee8a3d and 7cf1cfe5a (patch-ids equal to the reviewed commits) and pushed 7cf1cfe5a. AC1, AC2 and AC4 are met by the reviewed code and the harness-selftest scenarios (Harness Selftest green at 7cf1cfe5a).

2026-10-05 17:50 UTC: Go Test went red at 7cf1cfe5a on golangci-lint, not on go test: 8 errcheck (unchecked Close in the new tests) and 1 ineffassign (a dead `adoptedUpgradeLock = nil` after runCrashRecoveryWithLock; ownership already passes via svc.AdoptFlagLock, and recovery's flag lifecycle releases it). Root cause of the miss: the pre-push check ran go test and go vet but not `cd cli && golangci-lint run`; that is now part of the pre-push routine. Fixed on fix/447-lint (b7f4a0337) with no behaviour change. Review: MERGE (`tmp/447-lint-review.md`). Cherry-picked onto master as 8fab44933 (patch-id equal), together with the reviewed arc test fixes 87b3a3b87, e3040444e and 99534b001 (`tmp/arc-test-fixes-review.md`). Push waits for Fast Tests at 7cf1cfe5a to finish.

Remaining: AC3 (the rc.15 operator rehearsal in one installer run) and AC5 (the owner's demo install of rc.15, observed for at least 10 minutes).


2026-10-06 06:20 UTC: rc.15 (`ebc77c5f5`) carried this fix.
- The STATBUS-436 operator rehearsal PASSED in a single installer run with no retry (`tmp/436-operator-rc15.PASS.log`). The old v2026.09.2 daemon's one attempt during the install was refused with "another ./sb install is already running (install, invoked_by=install.sh:statbus)", and that row then ended `superseded`.
- The same candidate exposed a regression in this fix's exec continuation, tracked as STATBUS-450. On the inline scheduled path, the post-swap re-exec adopted the upgrade mutex, and recovery then contended with it. 450 is fixed on master at 7e92d1151.
- AC#3 is re-proven on rc.16 (the operator rehearsal again), and AC#5 is the owner's demo install of rc.16.
