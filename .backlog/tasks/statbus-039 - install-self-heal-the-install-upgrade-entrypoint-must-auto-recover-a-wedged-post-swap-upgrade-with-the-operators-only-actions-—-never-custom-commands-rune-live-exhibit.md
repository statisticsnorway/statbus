---
id: STATBUS-039
title: >-
  install-self-heal: the install/upgrade entrypoint must auto-recover a wedged
  post-swap upgrade with the operator's only actions — never custom commands
  (rune live exhibit)
status: To Do
assignee: []
created_date: '2026-06-12 08:54'
updated_date: '2026-06-12 08:57'
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
- [ ] #1 Architect designs the principled self-heal: the newest `./sb install` (or upgrade trigger) detects a wedged at-or-past-target in_progress post-swap upgrade and converges the row to completed automatically — no operator commands
- [ ] #2 The design guarantees no rollback ever restores a backup older than the live data (stale-backup guard); a lagging sub-artifact is reconciled forward to target, never via rollback
- [ ] #3 Proven on wedged-rune: running the newest `./sb install` self-heals id=187 to completed — no SIGTERM/stop, no rollback, no data loss, no manual commands — preserving the ~2.5 weeks of live data
- [ ] #4 After self-heal, rune upgrades to the campaign RC via the normal path and can serve as the stable-gate canary
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
<!-- SECTION:NOTES:END -->
