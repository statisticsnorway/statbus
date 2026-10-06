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

## Original implementation plan (released in rc.16, cleanup supersedes the ownership protocol below)

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
- [x] #3 The STATBUS-436 rehearsal no longer retries, and the operator path passes against the candidate in a single installer run.
- [x] #4 cloud.sh prints the signing-key hint only on a signature-verification failure.
- [ ] #5 The owner's official `./cloud.sh install demo <candidate>` repairs demo in one run, observed over ≥10 min: binary, checkout and resident daemon at the candidate; v2026.09.3 row superseded; zero refusals; **the site is usable** (a page loads and stays; not judged by HTTP status).

## KISS cleanup queue: owner direction, 2026-10-06 12:10-12:18 UTC

The owner requested cleanup of the flock handover, then the separate ledger repair, with low-level todos and delegation driving autonomous progress. Detailed plan: `tmp/kiss-handoff-and-ledger-plan.md`. Coordinator todo group `Handoff cleanup`, F1-F7, records mapping, implementation, real-FD checks, local gates, independent review, integration/CI-idle push and observed CI.

Contract: keep the actual open descriptor across the process boundary and pass the owned `FlagLock` within Go. Remove token authentication and the independently opened contention proof from the new receiver. Keep only checks tied to observed descriptor lifetime failures, plus ordinary close-on-exec hygiene and canonical-file identity. Recovery holder/phase are routing data, not a second ownership credential.

Two concrete boundaries prevent a blind deletion:
- `install.sh:542-554` currently closes fd9 for a pre-existing recovery marker. The previously stated gapless property applies to install-owned records and inline exec, not every marker case. Any extension must preserve the original recorded recovery/restart intent and use the existing held-lock recovery path, rather than overwrite it as an ordinary install.
- Released rc.16 receivers require the legacy FD/TOKEN format. Sender removal must not break them. A small compatibility bridge may remain while new code no longer authenticates ownership with the token.

Source mapping finished in `tmp/447-kiss-handoff-plan.md`. Implementation delegated to goat (`session_goat_1791289388801_237574acefd7e0d0`), isolated branch `fix/447-kiss-handoff` from origin/master `cf158dbd5`. At 12:32 UTC, coordinator inspected production commit `7322acf29`: four files, +44/-66. The new receiver keeps the inherited open-file description, removes token authentication and the separately opened probe, captures/consumes private inputs once, owns close-only cleanup on early/service returns, and closes fd9 in tee/filter children. Sender uses a fixed matching compatibility token for the released rc.16 receiver.

Observed prototypes before edits: real same-description flock excludes an independent open; baseline scheduled WithLock config-error leaks the adopted lock while leaving recovery marker intact. Focused GREEN logs inspected at 12:33 UTC in `scratch/fix-447-kiss-handoff/tmp/`: `focused-final.log` (FD adoption/exclusion, stale/rejected candidate survival, child FD/environment hygiene, failed-exec restoration, held recovery); `rc16-bridge.log` (original rc.16 receiver, real install/service children); `pipeline-fd.log` (baseline tee/filter fd9 held, current both closed); `shell-gapless.log` (single looping-holder attempt and healthy-holder wait). New config-error test proves descriptor release without changing marker bytes.

Frozen clean cleanup HEAD is `381b47644`, parent `7322acf29`. Full actual CI-equivalent `cd cli && go test ./... -count=1` exited 0 at 12:38 UTC, 159.41 s elapsed (cmd 47.613 s, upgrade 152.738 s), with `tmp/go-test-all-final.log` and `.exit`. Build, vet, golangci-lint (0 issues), gofmt, `bash -n` and diff check also exited 0. The original three affected packages passed separately. A cancelled earlier run misread intentionally synthetic connection-refused output as a DB problem. Source/log trace corrected that mistake; no real DB attempt, blockage or mutation occurred.

Independent reviewer lion (`session_lion_1791290106279_0d190dfa025736f5`, GPT-6.1 Sol xhigh) returned **MERGE for exact `381b47644`** at 12:43 UTC, report `tmp/447-kiss-review.md`. Its actual syscall.Exec handoff, last-owner close, HOME/restore/recovery early errors, original rc.16 child receiver and pipeline/holder reruns passed, plus affected Linux cross-build. Receiver provenance is exact blob `5260f9db17da3a6cb9f9fae79e2562d9527b7f72`; peeled rc.16 product commit is `7e92d1151189a165d45dc365ee72cec63d657c16`, not annotated tag object `e17ec7c3...`. Reviewed cleanup integrated locally as `7b715e3d4` and `cba8dd7e3` at 12:46 UTC. Stable patch IDs match, all seven source/test files equal reviewed HEAD, diff check passed (`tmp/447-kiss-integration-20261006.log`). No push/deployment, unrelated `.yarn/` untouched. Local checks are not released-image installation proof.

Frog finalized `tmp/447-existing-marker-next.md`, source-only mapping, F2b complete. The next small route preserves all pre-existing JSON rather than token-stamping it. After matched binary/target checkout, presence of the real held-restart entrypoint in target source enables the new recovery FD handoff. Absent/unreadable source retains the shipped close-fd9 fallback, so pinned rc.16 behavior is not broken and is explicitly outside the continuous-recovery claim. This is a small forward compatibility check like the existing target filter fallback, not an ownership credential or a new registry/protocol.

F2c delegated to goat in NEW `scratch/fix-447-existing-marker`, branch `fix/447-existing-marker` from `381b47644`, keeping the first cleanup frozen for its reviewer. At 12:41 UTC coordinator read RED prototypes before edits: `tmp/baseline-shell-red.log` shows an independent real flock contender entering after the actual shell closes existing-marker fd9 despite a capable-target source fixture; `tmp/baseline-restart-red.log` shows actual `restartServicesWith` self-refusing on an already held PREPARED restart, before stack work. Both exit 1 as expected (`tmp/baseline-red.exit`), new tracked worktree still clean at observation.

Implementation reuses the held handle for service, stale-install/legacy-empty and restart routes. Restart is holder=install, trigger=restart; prepared profile/unit/daemon intent and existing readiness/failure cleanup stay unchanged. Production `8df231e23` frozen at 12:48 UTC: six files, +95/-17, full diff inspected by coordinator. Separate tests `d85a4a5e788c160d13347eaf5b1bad047e045c6e` frozen clean at 12:52 UTC: five files, +359/-2. Total follow-on delta eleven files +454/-19. No token stamping, new health gate, automatic-restart policy, 452, database or server changes.

F2d complete at 12:53 UTC: coordinator read frozen tests and actual saved GREEN logs. `tmp/focused-existing-marker.log` / `.exit` prove FD9 service/install/restart/legacy routing, original same-FD fresh precedence, prepared/unprepared restart, failure cleanup and existing revalidation. `tmp/install-inherited-restart-route.log` passes the real runInstall pre-barrier path with external stack seams. `tmp/shell-existing-marker-final.log` / `.exit` exit 0 prove current service/install/restart/legacy exact unchanged marker bytes and real contender exclusion; actual rc.16 source, missing source and unreadable source preserve shipped fallback; original looping/healthy-holder checks pass. No guest acceptance claimed. The typed compose launch authority suite passed, two inventory method names mechanically follow WithLock, no count/gate weakening; lint 0 issues. F2e completed at 12:56 UTC: exact `d85a4a5e7` full `go test ./... -count=1` exited 0, elapsed 235.39 s (cmd 59.357 s, upgrade 228.493 s). Build, vet, lint (0 issues), bash syntax, gofmt (empty) and diff check all exited 0, with `tmp/static-gates-final.exit`, full-suite `.exit` and committed-diff `.exit`. Tree clean and HEAD unchanged. These gates did not establish merge readiness: F2f lion independently reproduced a real missing-config interrupted-first-install BLOCK, described below.

**Review BLOCK, 12:56 UTC:** actual `runInstall` with valid noninteractive answers, pre-existing holder=install/trigger=install and no `.env.config` adopts the recovery descriptor, detects `StateFresh` before marker inspection (`state.go:166-183`), then passes only nil `adoptedInstallLock` to `acquireOrBypass` (`install.go:854`). It tries a separate open while its `adoptedUpgradeLock` holds the flock, reports another installation running and runs zero steps. This is a legitimate interrupted first install and an executed self-contention regression, not authentication speculation. Reviewer reproducer and RED log: detached reviewer `cli/cmd/scratch_447_existing_marker_review_test.go`, `tmp/independent-missing-config-current.log`. Follow-on remains unmerged.

F2g delegated to goat at 12:56 UTC: preserve frozen d85 commit, commit real-route RED regression, route the existing owned handle to the fresh step-table without release/reopen or hiding service/restart intent, prove contender exclusion and close/marker cleanup through actual first step, preserve configured siblings. No detection-ladder rewrite, new protocol or health gate. F2h records renewed exact final gates, F2i fresh independent re-review before follow-on integration. Initial cleanup MERGE is unaffected.

Next: bounded fix and real-route GREEN, renewed local gate exits and independent exact follow-on MERGE, then integrate matching patch IDs/source and perform a fresh all-CI-idle check before push. Follow explicit CI conclusions. No database identity or retention redesign in this task. No candidate cut for demo until STATBUS-452 is also fixed. No production install by agents.

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

2026-10-06 08:05 UTC, v2026.10.0-rc.16 (`7e92d1151`) evidence:
- Release gates all green. Orchestrator run 37424897889: decision, smoke, dev canary, LXD fault fleet (run 37426559632) and arc harness (run 37426638674, 06:56 to 07:51 UTC, 41 success, 0 failure).
  - The 9 arcs that failed on rc.15 all passed: postswap-between-migrations-kill, postswap-mid-migration-kill, boot-migrate-churn-alive-idle, flagless-selfheal-at-target, postswap-converged-selfheal, postswap-container-restart-kill, postswap-mid-tx-kill, preswap-fetch-returned-error and restore-broke-reattempt.
  - So did the 8 that never ran on rc.15: preswap-checkout-kill, rollback-pair-terminal, rollback-kill, un-park-to-completion, transient-db-backoff, worker-wedge-mid-derive, rollback-schema-floor-failure and working.
- STATBUS-436 operator rehearsal: PASS 06:42 to 07:00 UTC, single installer run, no retry (`tmp/436-operator-rc16.PASS.log`). The old daemon was refused during the install with "another ./sb install is already running (install, invoked_by=install.sh:statbus)", the v2026.09.3 row ended superseded, and there were zero refusals and zero re-attempts afterwards.
- STATBUS-436 scheduled rehearsal: run 1 (06:42 to 06:57) completed the product path, but the test's own carrier check ran `jq` inside the hardened guest, which has none (rc=127). That line had never been reached before. The check was fixed test-only to parse the carrier on the host (`test: parse the 436 capture carrier on the host`, review `tmp/436-jq-review.md` MERGE). Run 2 (07:01 to about 07:15) used the rc.16 product with only that test file overlaid, and PASSED (`tmp/436-scheduled-rc16.PASS.log`):
  - "Continuing the upgrade on the new binary after the planned handoff."
  - 18/18 steps.
  - The carrier binds the exact reference and immutable ID for app, worker, rest and proxy.
  - The resident program is v2026.10.0-rc.16 at ~/statbus/sb.
  - The health check passed at all 4 sustained checks, with no daemon restart.
