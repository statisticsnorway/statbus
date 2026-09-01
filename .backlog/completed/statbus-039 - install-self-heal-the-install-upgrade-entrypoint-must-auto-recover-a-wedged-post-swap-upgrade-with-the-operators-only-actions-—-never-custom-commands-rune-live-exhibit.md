---
id: STATBUS-039
title: >-
  install-self-heal: the install/upgrade entrypoint must auto-recover a wedged
  post-swap upgrade with the operator's only actions — never custom commands
  (rune live exhibit)
status: Done
assignee:
  - architect
created_date: '2026-06-12 08:54'
updated_date: '2026-06-15 10:34'
labels:
  - install-recovery
  - upgrade
  - recovery
  - self-heal
  - operator-ux
  - architect-plan
  - needs-king-ratification
  - norway
dependencies: []
references:
  - cli/internal/install/state.go
  - cli/internal/upgrade/service.go
  - cli/internal/upgrade/exec.go
  - STATBUS-015
  - STATBUS-031
priority: high
ordinal: 39000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
THE PRINCIPLE (North Star — this IS the product, not a cleanup). A StatBus standalone operator — e.g. an underdeveloped-country statistical office with NO remote access and NO way to receive custom commands — has exactly TWO recovery actions: (1) trigger the upgrade, and the triggered system runs it to correct completion on its own; or (2) run `./sb install`, and it fixes the problem. ANY recovery that needs a custom command (systemctl, manual flag-clear, SQL, SIGKILL) is a PRODUCT FAILURE — antithetical to a self-upgradable system. Making the install/upgrade entrypoint self-heal is MORE critical than any one-off fix; it is the entire reason for the install-recovery campaign. (King directive, 2026-06-12, direct.)

THE LIVE EXHIBIT (rune/Norway, found 2026-06-12). rune has sat in a watchdog kill-loop ~18 days, undetected (~10,000 service restarts). Mechanism (engineer-verified against rune's actual binary, commit 51670d9e — an OLD pre-012/031/032 build):
- Stale in_progress row id=187 (v2026.05.6-rc.01) from May 25, phase=post_swap. Artifacts reached target (db/app/worker on 51670d9e, up 2 weeks) EXCEPT the proxy is stale (673b650f != 51670d9e).
- Each service start re-runs resumePostSwap; it stalls >120s in the post-health COMPLETION path (a DB write on a stale connection; uses fmt.Println, no heartbeat) -> WatchdogSec=120 SIGABRT -> Restart=always -> flag still Phase=post_swap -> resume -> infinite. (healthCheck is bounded <=75s and heartbeats; "Verifying health..." is just the last progress line before the silent completion hang.)
- This old binary lacks BOTH guards HEAD has: the FlagPhaseResuming latch (2nd resume rolls back, not re-run) and the applyPostSwap WATCHDOG=1 ticker. HEAD likely prevents the LOOP — but that alone does NOT make an already-WEDGED box self-heal when the operator runs install.

THE TRAP — hard design constraint (engineer-verified). The pre-upgrade backup is May 25, ~2.5 weeks stale. ANY rollback that restores it destroys ~2.5 weeks of live Norway data. The watchdog kills via SIGABRT (Go runs no deferred funcs -> NO rollback -> THAT is why 18 days of looping stayed data-safe). But `systemctl stop` sends SIGTERM, which IS caught -> cancels the upgrade ctx -> rollback -> pg_restore(May-25) = catastrophic. The unit's TimeoutStopSec=15min exists precisely because stop->rollback->pg_restore is real (cites a prior rune incident). DO NOT send SIGTERM to that service. And today even `./sb install` is NOT guaranteed safe: if container tags don't match it can fall to applyPostSwap->health->rollback. The self-heal must NEVER trigger a rollback that restores a backup older than live data.

THE REQUIREMENT (architect designs; the King drives the principled solution). The newest `./sb install` (and/or the upgrade trigger) must DETECT a wedged in_progress post-swap upgrade whose artifacts are at-or-past target (ground truth available: binary == row commit_sha, migrations applied) and SELF-HEAL the row to `completed` automatically — zero operator commands, provably without ever restoring a stale backup over newer data. A lagging sub-artifact (the stale proxy) is reconciled FORWARD to target, never backward via rollback.

VERIFICATION FIXTURE — PRESERVE RUNE AS-IS. rune is in this exact wedged state right now. Do NOT manually clean it (no SIGKILL, no flag-clear, no manual finalize). It is the live, real-scale test fixture: the fix is PROVEN when the newest `./sb install` on wedged-rune self-heals it to completed — no commands, no rollback, no data loss — after which rune can upgrade to the campaign RC and serve as the stable-gate canary. (rune is the hardcoded canary and has been un-upgradeable for 18 days, so this self-heal is now a PREREQUISITE for the Norway/stable gate, not hygiene.)

RELATED: 015 (Resuming latch / applyPostSwap watchdog — confirm they prevent the loop on HEAD), 031 (rollback safety — extend with the stale-backup-vs-live-data guard), 032 (health/readiness). NO MANUAL COMMANDS in the recovery — the fix ships as code in the install/upgrade entrypoint.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Architect designs the principled self-heal: the newest `./sb install` (or upgrade trigger) detects a wedged at-or-past-target in_progress post-swap upgrade and converges the row to completed automatically — no operator commands
- [x] #2 The design guarantees no rollback ever restores a backup older than the live data (stale-backup guard); a lagging sub-artifact is reconciled forward to target, never via rollback
- [x] #3 Proven on wedged-rune: running the newest `./sb install` self-heals id=187 to completed — no SIGTERM/stop, no rollback, no data loss, no manual commands — preserving the ~2.5 weeks of live data
- [x] #4 After self-heal, rune upgrades to the campaign RC via the normal path and can serve as the stable-gate canary
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ROOT CAUSE — CONFIRMED (engineer, 2026-06-12; full working notes tmp/engineer-rune-wedge-recovery.md, load-bearing facts here).

Watchdog kill-loop confirmed: systemd NRestarts=10229, Result='timeout', 150s cadence (WatchdogSec=120 + RestartSec=30). The id=187 log has ONE "Health check attempt" line and ZERO "rolling back" lines across ~18 days → health PASSES silently; the >120s silent hang is the post-health COMPLETION path (a DB write on a stale connection; fmt.Println, no heartbeat), NOT the probe. 10229 SIGABRT kills with the DB still healthy + current = the SIGABRT path never rolls back (data-safe). [The SIGTERM/`systemctl stop` path is the one that DOES pg_restore the May-25 backup → data loss. Never send it.]

THE ROOT CAUSE — id=187 is a PARTIAL upgrade the resume can never finish:
- docker ps: db/app/worker = :51670d9e (target OK), rest = postgrest:v12.2.8 (fine), PROXY = statbus-proxy:673b650f (May 7, STALE; target = 51670d9e).
- The self-heal branch (containersAtFlagTarget) requires ALL of db/app/worker/proxy at target. proxy=673b650f → the check NEVER matches → every resume falls through to applyPostSwap → completion hang → watchdog kill → ×10229.
- WHY the proxy is stuck: the RESUME path's applyPostSwap recreates only app/worker/rest (Step 11) and ASSUMES "proxy already running from Step 2" — but Step 2 (start proxy) runs ONLY in the fresh executeUpgrade path, never in a resume. So Step 8's `docker compose pull` pulls proxy:51670d9e every cycle but Step 11 never recreates it → proxy frozen at the prior tag forever.
- The box already has everything to heal: proxy:51670d9e EXISTS in the registry and the generated compose already references it (COMMIT_SHORT=51670d9e). The entrypoint simply never recreated the proxy container.

THE PRINCIPLED FIX (design target for the architect): the resume/self-heal entrypoint must bring the FULL service set to target — a `docker compose up -d` over ALL services INCLUDING the proxy, not a subset — so a partial/crashed upgrade self-completes when the operator runs `./sb install` (or the upgrade trigger), with NO manual `docker compose up proxy` and NO rollback. Once all services match target, resumePostSwap takes the self-heal branch (a plain state=completed UPDATE + flag removal; no applyPostSwap, no rollback path), and "completed" is honest (proxy actually at target).

ALREADY IN HEAD (039 builds on, doesn't redo): the 015 FlagPhaseResuming latch (2nd resume rolls back instead of re-running) + the applyPostSwap WATCHDOG=1 ticker (keeps the completion path from going silent >120s). These prevent the LOOP on HEAD; the remaining gap is the FULL-service recreate-on-resume so the self-heal can reach the matched state on an already-wedged box.

OPEN SCOPING QUESTION (architect to resolve; engineer available to verify read-only): does HEAD's resume path already recreate the full service set (incl proxy), or is that still the gap 039 must close? The answer scopes 039 between "just make install converge an already-wedged old-binary box" and "also fix resume to recreate the full set (prevent recurrence)".

STALE-BACKUP GUARD (hard constraint, restated): no path may restore a backup older than live data (the May-25 backup vs ~2.5 weeks of live Norway data).

SCOPING QUESTION CLOSED (architect, 2026-06-12, verified in-repo — engineer standby not needed): HEAD's resume ALREADY recreates the full service set including proxy. step11RestartServices = {app, worker, rest, proxy} (service.go:119); TestVersionTrackedAlignedWithUpgradePipeline (containers_invariants_test.go) exists specifically because of this rune bug — its comment names 'the Bug 2 symptom that bit rune.statbus.org: proxy was in versionTrackedServices but missing from step 11' — and guards both drift directions. (rest is step11-but-not-versionTracked by design: upstream-pinned image, running-state-only check.) The step-11 comment at service.go:4000 ('proxy already running from step 2') is DRIFTED PROSE predating the Bug-2 fix — repair it in whatever commit lands here. rune's id=187 wedge is therefore specific to its OLD binary (51670d9e, pre-Bug-2-fix).

WHAT THIS LEAVES AS 039's ACTUAL DESIGN SURFACE (the principled layer — none of it shipped): (1) GROUND-TRUTH-FIRST ordering: at-or-past-target (binary==row.commit_sha + migrations≥target, verifyUpgradeGroundTruth already computes it) must decide direction BEFORE the Resuming latch can route to rollback — on HEAD today, a single failed resume attempt stamps Resuming and the NEXT recovery latches into rollback → restore of the May-25 backup: one failure, no second chance, data-loss behind it. (2) STALE-BACKUP GUARD at the rollback() chokepoint — and it is a PRECONDITION of the 031 watchdog cover, not an extension: on this exhibit, HEAD-as-is kills the uncovered restore mid-rsync (corrupted volume), while 031's ticker ALONE would let the May-25 restore COMPLETE (confident 2.5-week data loss with a green rolled_back row). 031 must not land without the guard. (3) SAFE TAKEOVER in the install ladder: today flag+flock-held → StateLiveUpgrade refuse (state.go:7/:123), and during the ~30s RestartSec windows install races into StateCrashedUpgrade instead; the takeover must quiesce the looping OLD service SIGKILL-class — NEVER SIGTERM (the old binary's handler cancels ctx → rollback → the trap; the unit's TimeoutStopSec=15min comment cites a prior rune stop→rollback→pg_restore incident) — then the new binary owns recovery. (4) PROOF on wedged-rune per AC#3/#4.

Walk-through of HEAD's install on wedged-rune AS-IS (why the principled layer is still required even with Bug-2 fixed): install wins the flock race → crashed-upgrade → resumePostSwap → canary fails on stale proxy → stamps Resuming → applyPostSwap re-run WOULD converge (step 11 now recreates proxy) IF every step succeeds first try — but any single failure (health blip, conn error) routes postSwapFailure → rollback → May-25 restore. The system converges only if nothing goes wrong once, with a data-loss gun behind every failure path. Forward-only-for-at-target removes the gun.

FINAL DESIGN (architect, 2026-06-12; the transactional model applied — supersedes the earlier open design surface in these notes; ratified by the King in-session, who directed immediate implementation):

(a) GROUND-TRUTH-FIRST ROUTING. Direction is decided by ground truth BEFORE anything destructive, in every flag-driven recovery path. The verdict is tri-state (verifyUpgradeGroundTruthEx): AT-TARGET (binary at-or-descendant of the row's commit AND DB migrations at-or-past the on-disk max) → FORWARD, always — resume/retry, loudly, non-terminally; a died attempt is not impossibility. POSITIVELY-BEHIND (binary mismatch, or migrations missing with a reachable DB) → backward, one-shot, to regain a runnable state. UNKNOWN (DB unreachable mid-check) → never destroy state under uncertainty: retry forward; the next pass re-checks. Wired into: the Resuming-flag branch of recoverFromFlag (pre-039 it rolled back unconditionally — one transient failure latched the next recovery into a restore), postSwapFailure (the single failure chokepoint for all applyPostSwap steps), and completeInProgressUpgrade (flagless recovery). At-target failures stamp the row's error column non-terminally (legal on in_progress per chk_upgrade_state_attributes) so the admin UI shows WHY between retries; every completion UPDATE clears error (the CHECK forbids it on completed).

(b) IDENTITY-KEYED RESTORE. A restore may consume ONLY the snapshot the recovered upgrade recorded for itself — flag.BackupPath (stamped by updateFlagPostSwap after the snapshot's atomic commit-rename) or the row's backup_path. Empty identity (a PreSwap kill — no snapshot ever finalised, volume never mutated) → refuse to touch the volume, clean rolled_back. Identity recorded but missing on disk → fail LOUD as degraded `failed`; never restore any other backup. The recency selector (pickLatestBackup) is DELETED: its legacy fallback was a verified silent-loss path — every backup opens by consuming the active snapshot (aside-rename, exec.go prepareBackupSnapshotDir), so a kill in that window plus the legacy per-stamp dirs every migrated box keeps forever (pruneBackups keep=3) made the restore grab ANOTHER upgrade's months-old backup and rsync --delete it over an untouched live volume, green rolled_back row, silent. That loss path completed silently under ./sb install (no watchdog) TODAY — this, not wedge-accumulated data (the King refuted that: a wedged box locks browser users out via the app's upgrade guard, rune accumulated zero domain writes in 18 days), is the real justification for coupling the identity fix with the STATBUS-031 watchdog cover: 031's ticker must never extend a wrong restore to silent completion on the service path too.

(c) SAFE TAKEOVER — SIGKILL-CLASS ONLY. Two changes in the install entrypoint. FIRST, the quiesce primitive (stopRestartUpgradeUnit, cli/cmd/install_upgrade.go) is hardened: capture is-enabled → systemctl mask --runtime (a masked unit cannot respawn, so there is NO race between kill and stop; runtime scope self-clears on reboot — a crashed takeover can never permanently disable the upgrade service) → systemctl kill --signal=SIGKILL (whole control group, no handlers run, the kernel releases the flock on fd teardown) → poll MainPID==0 → stop (nothing alive to signal; only cancels the pending auto-restart) → reset-failed → unmask; the restart closure fires only after successful recovery and only if the unit was enabled. This REPLACES a pre-existing hazard found during implementation: the old body ran a bare `systemctl stop` — SIGTERM — which, if the looping unit had respawned between state-detection and the stop, lands on a live resuming process → context cancel → rollback → the exact restore trap THE TRAP paragraph above describes. SECOND, the install ladder gains a takeover arm: StateLiveUpgrade (flock held) + a crash-looping unit (NRestarts ≥ 3 via systemctl show — a healthy upgrade restarts once by design, the exit-42 binary-swap handoff; rune sat at 10,229) is reclassified as crashed-upgrade and recovered through the quiesce; a genuinely progressing upgrade (low restart count) keeps today's refusal, and ANY probe failure conservatively falls back to the refusal. This removes the 30s-RestartSec timing lottery: the operator's ./sb install takes over deterministically.

(d) TRUTH REPAIRS IN PROSE. The drifted step-11 comment ("proxy already running from step 2" — pre-Bug-2 prose), the PreSwap branch's data-safety claim (now true BY IDENTITY, not by luck on legacy-free boxes), the FlagPhaseResuming/ErrResumeDied docs (one-shot-latch wording → ground-truth routing), the backup_path-UPDATE not-fatal reasoning (the flag carries the restore identity), and the dead headSHA-reconcile/self-heal segment in recoverFromFlag (service.go, ~200 lines, unreachable for every producible flag phase since FlagPhasePreSwap=="" intercepts everything) — DELETED outright per the clean-break discipline, replaced by a FLAG_PHASE_UNKNOWN fail-loud arm.

IMPLEMENTED AND COMMITTED as 5eacd6305 (2026-06-12, architect-coded on the King's direct order; engineer + foreman review — inverted from the usual direction). Final shape: 9 files, +1092/−581: cli/internal/upgrade/{service.go, exec.go, backup_test.go, persistent_rsync_test.go, postswap_test.go, ground_truth_test.go}, cli/cmd/{install.go, install_upgrade.go, upgrade.go}. Build + vet + FULL go test suite GREEN; byte-anchored (shasums) between final review and commit. Beyond the (a)-(d) design, the review cycle hardened four more things into the same commit: F1 — verifyBinaryGroundTruth made tri-state (git merge-base exit-1 is the ONLY Behind verdict; unresolvable commits / shallow clones are Unknown → never restore on clone-state evidence; an old test had PINNED the conflation and was rewritten); F2 — the unit's restart counter resets at every upgrade dispatch so the install takeover's crash-loop gate (NRestarts≥3) counts only the current upgrade; F3 (engineer-confirmed corruption) — the destructive restore is serialized on the upgrade flock at the top of recoveryRollback (loser yields touching nothing; in-process mis-wiring fails fast; rollback() stays acquire-free), closing the concurrent rsync-restore race between install-driven recovery and a respawned service; F4 — the whole mutex lifecycle made atomic (every flag-file unlink happens WHILE HOLDING its flock — removeUpgradeFlag both branches + ReleaseInstallFlag — eliminating µs split-brain windows). Tests: the seven recency-selection tests rewritten as identity-contract tests — including a reconstruction of the exact aside-rename-window hazard (legacy dirs + syncing partial + absent active → empty identity must no-op and touch nothing) — plus structural guards pinning every load-bearing ordering (ground-truth-before-rollback in the Resuming branch and postSwapFailure; flock-gate-before-destructive-work; no-recency-scan-may-regrow; mutex unlink dispositions).

VERIFICATION PLAN: (1) engineer review of the diff (hard look at: postSwapFailure's at-target exit semantics — error return, flag stays Resuming, crash-only forward retry across process restarts; the error=NULL additions on all three completion UPDATEs; quiesce race-freedom; dead-segment deletion completeness). (2) VM scenario for the fabricated rune-shape wedge (in_progress post_swap row + stale proxy + crash-looping unit) — may run AFTER the rune recovery per the King's explicit call (Norway outage outweighs battery-first; rune taking an RC early is its prerelease-canary role; battery still gates the stable release). (3) The rune proof itself = AC#3/#4: newest ./sb install on wedged-rune converges id=187 to completed — no commands, no rollback, no data loss — then rune takes the campaign RC. Expected operator-visible trace on rune: install detects live-upgrade + NRestarts≥10k → takeover (mask/SIGKILL/verify/unmask) → crashed-upgrade recovery → resume → step 11 recreates ALL services incl. proxy at 51670d9e → health → completion write on a fresh connection → row completed, flag removed → the app's upgrade guard releases → https://no.statbus.org serves again.

NO-DEPLOYMENT RUNBOOK (AC#3/#4 execution — the King runs this; expected trace + verification, so every observation has a named expectation):

COMMAND (from a local checkout at HEAD ≥ f5b697928 so standalone.sh has no pre-stop): `./standalone.sh install no` (channel prerelease resolves to the rc.02 tag) — ONE command, nothing else.

EXPECTED TRACE, in order:
1. Local: release-artifact check passes; install.sh curls to rune; new sb binary lands via sb.tmp+mv (atomic; the kill-loop self-migrates to the rc.02 binary within one ~150s cycle regardless).
2. rune ./sb install: Detect → live-upgrade (flock held by the loop) → crash-loop probe NRestarts≈10000 ≥ 3 → TAKEOVER: mask --runtime → kill -s SIGKILL → MainPID==0 → stop → reset-failed → unmask. NO SIGTERM anywhere. (If install lands in a dead window instead: straight to crashed-upgrade — same destination.)
3. runCrashRecovery: config generate → DB reachable → boot-migrate (applies rc.02's pending delta — the checkout is already at rc.02) → RecoverFromFlag: flag id=187 Phase=post_swap → resumePostSwap → container canary fails on the stale proxy (673b650f) → rc.02 binary descends 51670d9e → continue → Phase=Resuming → applyPostSwap → step 11 recreates app/worker/rest/PROXY → health → completion write on a fresh conn → row 187 state=completed, error=NULL, flag removed. NO restore ran (verify: no 'Restoring database' line; the May-25 backup dir untouched mtime).
4. If any step hiccups: ground truth says at-target → forward retry next pass (row stays in_progress with the reason in error) — re-run the same command. The May-25 restore is unreachable (rule 1); if a restore were ever legitimately reached it consumes flag.BackupPath = 187's OWN backup (verified present on rune).
5. re-Detect → step-table as the rc.02 install (idempotent) → unit reinstalled + restarted on the rc.02 binary.

POST-INSTALL VERIFICATION (all read-only):
- https://no.statbus.org/ serves the app (the upgrade-maintenance guard released — row no longer in_progress). THE 18-day user-facing outage ends here.
- psql: SELECT id,state,completed_at,error FROM public.upgrade WHERE id=187 → completed, error NULL.
- docker ps: db/app/worker/proxy all at the rc.02 tag (proxy no longer 673b650f); rest running.
- systemctl --user status statbus-upgrade@statbus → active, NRestarts low/zero; journal shows the takeover narrative.
- flag file absent: tmp/upgrade-in-progress.json gone.
- Backups dir: pre-upgrade-20260525T061058Z untouched; later upgrades create the CHANGE-2 active snapshot.
THEN AC#4: rune resumes prerelease-canary duty (subsequent upgrades via the normal scheduled path); the deferred battery (STATBUS-044) runs before the stable gate.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
DONE — code shipped 5eacd6305 (2026-06-12), validated LIVE on rune 2026-06-13, foreman re-confirmed read-only 2026-06-15. Status had been stale at In Progress (last touched 06-12, before the 06-13 recovery proved AC#3/#4).

AC#1/#2 (design) — committed 5eacd6305 (9 files, +1092/-581; build/vet/full go test green): ground-truth-first FORWARD routing (at-target never rolls back; tri-state verdict wired into the Resuming branch, postSwapFailure, completeInProgressUpgrade), identity-keyed restore (consumes ONLY flag.BackupPath/row.backup_path; pickLatestBackup recency selector DELETED as a silent-loss path), SIGKILL-class safe takeover (mask --runtime → kill SIGKILL → verify MainPID==0 → stop → unmask; NEVER SIGTERM), + truth-repairs. Plus review-hardenings F1-F4.

AC#3 (self-heal on wedged-rune) — PROVEN: rune's crash-loop (NRestarts≈10784) was taken over SIGKILL-class (no SIGTERM), rolled FORWARD (no rollback), id=187 self-healed to completed. Live re-verify 2026-06-15 (read-only ./sb psql): row 187 state=completed, error NULL; in_progress_count=0; May-25 backup untouched. Zero operator commands beyond ./sb install; zero data loss; the 18-day user-facing outage ended.

AC#4 (rune on the campaign RC, canary duty) — PROVEN: row 196 = 2026.06.0-rc.02, completed 2026-06-13 08:27; live re-verify confirms it is the newest completed (running) version. rune resumed prerelease-canary duty.

The remaining "fabricated rune-shape wedge VM scenario" battery is tracked separately as STATBUS-044 (not a 039 AC). Closed on live evidence 2026-06-15.
<!-- SECTION:FINAL_SUMMARY:END -->
