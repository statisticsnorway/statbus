---
id: STATBUS-073
title: >-
  rc04-gate-residual: RUN A comprehensive gate = 18 pass / 14 fail, 5 root-cause
  categories (NOT a fix regression)
status: Done
assignee: []
created_date: '2026-06-17 10:13'
updated_date: '2026-07-06 15:58'
labels:
  - install-recovery
  - rc.04
  - gate
  - regression-triage
dependencies: []
priority: high
ordinal: 73000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
RUN A = the comprehensive gate run on the gating-set HEAD (73ea5210f), run 27675235157. Result: 18 PASS / 14 FAIL. Better than the prior run (27645059996, 19 fail) — the fixes moved ~5 scenarios green (legacy checkout-kill = origin/master fix worked; worker-ddl-deadlock; etc.) — but NOT a green gate. NOT a systematic regression of the carve-out/quiesce; the 14 reds are 5 distinct root causes:

CATEGORY C — REST_ADMIN_BIND_ADDRESS missing in fabricate `./sb psql` (6 scenarios, HIGHEST LEVERAGE, ONE root cause): archivebackup-resume(:250), archivebackup-watchdog(:193), resume-died-rollback(:165), mid-tx-kill(:159), watchdog-reconnect(:157), rollback-restore-watchdog(:188). Signature (exposed by the #5 psql-capture fix 11122f86f): `fabricate_scheduled_upgrade_row psql failed (rc=1): error while interpolating services.rest.ports.[]: required variable REST_ADMIN_BIND_ADDRESS is missing a value: REST_ADMIN_BIND_ADDRESS must be set in the generated .env`. The harness uploads HEAD's sb; the fabricate step runs `./sb psql` against an OLD install's .env (v2026.05.2, no REST_ADMIN_BIND_ADDRESS) while HEAD's docker-compose references it -> interpolation fails BEFORE any test logic. Likely fix: fabricate must `./sb config generate` (or equivalent) before `./sb psql`; OR a product robustness angle (psql on a config-drifted .env). Fixing this UNMASKS the 6 (some may then pass, some hit their own known-red). OWNER: operator (config/.env/docker-compose).

CATEGORY A — flag file ABSENT after the kill (4): 2-preswap-backup-kill, 2-preswap-binary-swap-kill, 2-preswap-checkout-kill, 3-postswap-container-restart-kill. Assertion `✗ expected flag file present after kill`. Recovery needs the in-progress flag to detect the interrupted upgrade; it's not present post-kill (flag not written early enough, OR the kill landed before the flag write). Product-vs-scenario TBD. OWNER: architect (recovery flag-write timing).

CATEGORY B — recovery ROLLED BACK instead of forward (2): 3-postswap-between-migrations-kill, 3-postswap-mid-migration-kill. `✗ single install exited 1 (want 0; 75 = rolled_back regression)`. These expect FORWARD recovery (state=completed); they rolled back. Real recovery behavior question (related STATBUS-046 recovery-escalation). OWNER: architect.

CATEGORY D — inject DID NOT FIRE (1): 4-rollback-kill. `✗ first install exited 0 (expected 137) — the C5 binary-swap kill did not fire`. The C5 setup kill didn't trigger. Scenario/inject issue (relates STATBUS-028). OWNER: mechanic.

CATEGORY E — VM bootstrap SSH failure (1): 5-install-stage-a-killed-migrate. `rc=2 at vm-bootstrap.sh:360: ssh ... root@$VM_IP`. Hetzner VM bootstrap SSH failed — infra, re-runnable (relates STATBUS-029). OWNER: operator (re-run; confirm transient).

PATH TO GREEN: fix C (highest leverage, 6) -> A (4) -> B (2) -> D (1); E is infra (re-run). Then re-run the comprehensive gate. WHEN-CAN-WE-CUT: after the gate is green OR its remaining reds are confirmed-known-and-acceptable. Full log: tmp/runA-failed.log (59810 lines).
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PROGRESS (foreman, driving): CATEGORY C FIXED + COMMITTED 9bdba03cc — operator diagnosed (HEAD docker-compose references REST_ADMIN_BIND_ADDRESS; fabricate ran `./sb psql` against the v2026.05.2 .env that predates it); fix = `./sb config generate` before `./sb psql` in fabricate_scheduled_upgrade_row (data-helpers.sh:337). Harness-only, foreman-reviewed (clean single-line diff, fail-loud, bash -n OK). Unmasks the 6 (archivebackup-resume/-watchdog, resume-died-rollback, mid-tx-kill, watchdog-reconnect, rollback-restore-watchdog) — some will pass, some surface their own residual on the re-run.
CATEGORY E CONFIRMED INFRA (operator): stage-a-killed-migrate rc=2 at vm-bootstrap.sh:360 is a Hetzner bootstrap SSH blip (before scenario logic), not code. Re-validates automatically in the comprehensive re-run (no separate run needed).
IN FLIGHT: Category A (flag-after-kill ×4) + B (rolled-back-not-forward ×2) → architect; Category D (C5 kill didn't fire, 4-rollback-kill + binary-swap-kill) → mechanic. Commit each as it lands; push the batch → one comprehensive re-run validates all + reveals the next residual.

CATEGORY D RE-DIAGNOSED (foreman caught a mis-diagnosis): mechanic first reported 'fabricate-race, already fixed by ab4a4dcad, green on re-run.' VERIFIED WRONG: RUN A ran 73ea5210f which CONTAINS ab4a4dcad (merge-base confirms), the scenario HAS quiesce before fabricate (line 131), and RUN A's log shows the quiesce RAN (`[quiesce] ✓ upgrade service quiesced`). So the service was stopped — it could NOT claim the row — the fabricate-race did NOT occur. (Mechanic likely read the PREVIOUS pre-ab4a4dcad run.)

REAL CAUSE (from the mechanic's own step 5 + RUN A log): the harness pre-stages HEAD's binary (upload_sb_to_vm) so the inject exists in the RUNNING binary — but that makes sbAlreadyAtCommit(HEAD)=true → executeUpgrade SKIPS the binary-swap (replaceBinaryOnDisk) → the KillHere('killed-by-system-during-binary-swap') site (AFTER the swap) is NEVER reached → exit 0, no kill, no flag, row completes. This is the SAME cause as binary-swap-kill in Category A (same C5 inject) — ONE cause for TWO scenarios (4-rollback-kill + 2-preswap-binary-swap-kill).

TENSION: the running binary must be HEAD for the inject to exist, but that makes sbAlreadyAtCommit=true and the swap a no-op. OPEN (architect): FIXABLE (make the swap happen + kill fire while running binary carries the inject — e.g. procure-target commit ≠ running-binary commit) OR SCENARIO LIMITATION → confirmed-known-red (product correctly skips the swap when already at target; not a product bug). Routed to architect (overlaps Cat A). LESSON: do not mark a category green on a teammate's 'already fixed' without checking the failing run actually contained the fix.

ROOT CAUSE COLLAPSES TO ONE (architect-diagnosed, foreman-verified 13/14): the #3 quiesce_upgrade_service uses `systemctl --user stop ...service` = SIGTERM. The upgrade service's Run() registers signal.NotifyContext(SIGINT, SIGTERM) (service.go:1460) -> SIGTERM cancels the upgrade context -> fires executeUpgrade's DEFERRED rollback() (restoreGitState + pg_restore + restoreBinary). So the quiesce, meant only to pause the service, ROLLS BACK and corrupts the scenario BEFORE its real test. The service was NOT idle (the #3 'idle-stop is safe' assumption) — it had auto-started its OWN discovered upgrade, so the stop hit an in-flight upgrade. FINGERPRINT verified across 13 of 14 reds: `[quiesce] ✓` -> `Previous HEAD position was 50fd4325f` (restoreGitState) -> mostly `db-unreachable` (pg_restore) -> step-table ([N/16] ladder) -> executeUpgrade NEVER dispatched -> Cat A: no flag written; Cat B: step-table exit 1 ('rolled_back regression' is actually the step-table exit, downstream). Only stage-a (Cat E, infra) is outside. So the original 5-category split COLLAPSES: A+B+D (and the Cat-C scenarios too, which also show prevHEAD) are ONE root cause.

CORRECTION: the foreman/mechanic 'binary-swap-skip (sbAlreadyAtCommit)' framing was a RED HERRING — there is no sbAlreadyAtCommit function; service.go:4009-4048 ALWAYS procures then ALWAYS hits inject.KillHere (:4048, 'no rarely-run skip-handoff branch', rc.70). binary-swap-kill's RUN-A red = the quiesce-rollback (step-table, executeUpgrade never ran), same as all A+B.

LATENT SECOND LAYER (real, only surfaces AFTER the quiesce fix): for binary-swap-kill + 4-rollback-kill, the C5 swap on an EDGE target runs buildBinaryOnDisk = `make -C cli build` (service.go:4018,4032) which FAILS toolchain-free -> procureErr -> rollback (:4036) BEFORE inject.KillHere(:4048) -> no kill. Gated behind the quiesce-rollback now. LIKELY FIXABLE (route edge-swap through image-procurement/docker-pull, or target a tagged release carrying the inject framework) — reassess from the post-quiesce re-run; do NOT pre-fix.

FIX: SIGKILL-class quiesce (architect writing exact diff): keep timer stop; `systemctl --user kill -s SIGKILL` the daemon (SIGTERM handler can't fire); prevent Restart=always(RestartSec=30) revival without delivering SIGTERM to a live process; preserve recovery re-enable (step-table `enable --now`, install.go:1806). Harness-only (wedge-helpers.sh). Plus operator's Cat-C config-generate (committed 9bdba03cc, complementary). -> ONE re-run -> true residual legible (likely just stage-a infra + the binary-swap second layer + any genuine known-reds).

FIX COMMITTED + RE-RUN LIVE (foreman): SIGKILL-class quiesce COMMITTED 3a0d6e6dd (foreman-reviewed: verified it mirrors the product's stopRestartUpgradeUnit at install_upgrade.go:316 documented 7-step sequence; old_string matched; bash -n OK; touched the stale header line). Mechanism: mask --runtime -> kill --signal=SIGKILL -> stop -> reset-failed -> unmask (race-free respawn block; no SIGTERM handler; clears 137+NRestarts; preserves recovery enable --now). PUSHED 6a0a8398e..3a0d6e6dd. Both gate fixes now on master: config-generate (9bdba03cc) + SIGKILL-quiesce (3a0d6e6dd). Only .sh changed -> sb binary/images content-identical (fast cached rebuild). COMPREHENSIVE RE-RUN LIVE: run 27683157288 on 3a0d6e6dd (blank selector = ~30 gating scenarios). Expect ~13 of 14 reds cleared; true residual to surface = stage-a infra (auto-pass) + binary-swap-kill/4-rollback-kill latent edge-swap make-fail second layer (mechanic on standby) + any genuine known-reds. Watcher beiv5v11f. ~1.5-2h.

KING RULING (2026-06-17, foreman recorded): cut bar = HOLD FOR 100% GREEN. NO acceptable-reds carve-out. SUPERSEDES the Description's 'green OR remaining reds confirmed-known-and-acceptable'. Even a residual of only {stage-a infra blip (re-run) + the two throwaway-build edge-case scenarios (binary-swap-kill + 4-rollback-kill toolchain-free make-fail second layer)} does NOT permit a cut. Those two get a REAL fix (route edge-swap through image-procurement/docker-pull OR target a tagged release carrying the inject framework); infra blip gets a clean re-run; rc.04 cuts ONLY off a fully-green comprehensive run. At least one more fix->re-run loop is now on the critical path by design.

RECORD CORRECTION (architect adversarially verified + foreman code-confirmed, 2026-06-17) — two earlier notes in this log are FALSE; superseded here:

(1) The 'CORRECTION' note claiming 'there is no sbAlreadyAtCommit function; service.go:4009-4048 ALWAYS procures then ALWAYS hits KillHere' is WRONG. TRUTH: buildBinaryOnDisk (service.go:5660) calls sbAlreadyAtCommit (5664, defined at 5763) FIRST and returns nil — skipping the image fetch — when ./sb already carries the target commit. The C5 KillHere (4048) is still reached on that skip (procureErr nil -> no rollback at 4036).

(2) The 'LATENT SECOND LAYER' note (edge-target buildBinaryOnDisk runs `make -C cli build` -> fails toolchain-free -> procureErr -> rollback before the C5 kill) is REFUTED. TRUTH: buildBinaryOnDisk uses procureSbFromImage (docker pull/create/cp, toolchain-free; service.go:5673/5691 'no host Go/make toolchain'), NOT make. `make -C cli build` survives ONLY in stale comments (4018, 1424), never in code. For binary-swap-kill + 4-rollback-kill the harness pre-stages HEAD's ./sb (upload_sb_to_vm) -> sbAlreadyAtCommit=true -> buildBinaryOnDisk nil -> C5 KillHere fires by design (os.Exit 137). NO second layer.

CONSEQUENCE: the SIGKILL-class quiesce (3a0d6e6dd) was the SOLE RUN-A blocker for these two as well. All 14 RUN-A reds except stage-a (Cat E infra) collapse to the one quiesce-rollback cause. Architect's why-I-was-wrong: truncated `grep | head -15` crowded out the 5664/5763 hits + read the 4018 stale comment instead of the function body. OPEN-Q (i) auto-restart re-claim: structurally prevented — mask --runtime is set BEFORE the SIGKILL, so the 137-exit's Restart=always cannot start a masked unit; stop cancels the pending restart -> inactive; unmask only restores startability. OPEN-Q (ii) other exit-0 fork: not expected (DB intact->DBReachable; no fabricate flag->not CrashedUpgrade; config present->not Fresh; row state='scheduled' started_at NULL + quiesced service can't claim -> StateScheduledUpgrade->executeUpgrade). ORACLE LINES for the run: 'Detected install state:'=scheduled-upgrade and 'first install exited:'=137 -> PASS.

SECOND RESIDUAL on run 27683157288 (foreman, 2026-06-17) — a SIDE-EFFECT of the SIGKILL quiesce (3a0d6e6dd), distinct from the freshness-reorder (STATBUS-076). 3-postswap-archivebackup-watchdog FAILED, but NOT on freshness: its fabricate SUCCEEDED (stage-head checks out HEAD before fabricate → binary==tree → guard silent). It died at `systemctl --user start statbus-upgrade@statbus.service returned non-zero` (vm-bootstrap.sh:902). Unit diagnostic: `Loaded: masked (Reason: Unit statbus-upgrade@statbus.service is masked.)`, Main PID exited 0/SUCCESS. ROOT HYPOTHESIS: the quiesce's `mask --runtime → kill → stop → reset-failed → unmask` leaves the unit MASKED (the unmask isn't clearing the --runtime scope, OR didn't run, OR the path re-masks) — so scenarios that DIRECTLY `systemctl start`/`vm_restart_unit` the upgrade service AFTER quiescing fail on the masked unit. The quiesce even logs '✓ unit re-enableable' but it's masked at start time. 0-happy-upgrade also vm_restart_units the upgrade service but PASSED — it doesn't quiesce. So this bites quiesce+direct-service-start scenarios (watchdog; check watchdog-reconnect, resume-died-rollback, 4-rollback-restore-watchdog as the run completes). OWNER: architect (their quiesce; diagnose from wedge-helpers.sh + the log, fix the unmask while keeping the rollback-handler protection). Blocks the gate alongside STATBUS-076. CONSEQUENCE: the path to green is NOW at least TWO fixes (freshness-reorder + quiesce-unmask) + re-run, not one.

QUIESCE-MASK FIX COMMITTED (foreman, 2026-06-17): unmask --runtime committed e6c85c193 (wedge-helpers.sh:749 — pair the runtime-scoped unmask with the mask --runtime; mirrors product install_upgrade.go:362). Architect-diagnosed (their own one-flag bug, owned), foreman applied + bash -n verified. Validates on the re-run (STATBUS-075). This was the SECOND residual of run 27683157288 (the first = STATBUS-076 freshness reorder, committed 7f305f70d).

MASKED-UNIT CLASS PROVABLY COMPLETE (architect audit, 2026-06-17): `grep -rl "systemctl.*mask"` returns ONLY test/install-recovery/lib/wedge-helpers.sh — the shared quiesce_upgrade_service helper (:745 mask --runtime ↔ :749 unmask --runtime) is the SOLE mask/unmask site in the whole harness; no scenario masks via a separate path. So e6c85c193's one-line fix covers EVERY quiescing caller — no latent masked-unit bug anywhere else. Combined with STATBUS-076's audit (all 17 active fabricating scenarios coherent at fabricate), BOTH fixed classes are now provably complete → any 'third residual' the held run 27683157288 reveals is genuinely NEW (outside these two classes), not a missed instance.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLOSE — SUPERSEDED. Its purpose was getting the rc.04 gate green. That campaign concluded: the root causes were fixed (SIGKILL quiesce 3a0d6e6dd, config-generate 9bdba03cc, unmask e6c85c193), rc.04 was cut (recorded in STATBUS-071: the folded-in STATBUS-075 "cut-rc04 campaign" closed), and the old scenario suite it gated is being retired/reshaped under STATBUS-071. The coverage question now lives in 071's living coverage map.
<!-- SECTION:FINAL_SUMMARY:END -->
