---
id: doc-016
title: >-
  STATBUS-071 §9(5) implementable plan — kill-scenario reshape +
  fabricate-retirement (AC#3/AC#4)
type: specification
created_date: '2026-06-19 07:43'
updated_date: '2026-06-19 10:05'
---
# STATBUS-071 §9(5) — kill-scenario reshape + fabricate-retirement (implementable)

**Audience:** engineer (build, one-breaker-at-a-time + freeze) + foreman (review/commit/VM-prove). **Inputs:** engineer sketch tmp/engineer-071-step5-plan.md + architect reconciliation. **Status (2026-06-19):** 5a GREEN (kill-arc driver, run 27813204057); 5b GREEN (CAT-A ×5 incl. rollback-kill deterministic, run 27816903271); 5c GREEN (CAT-B stall mechanism via C15 postswap-watchdog-reconnect, run 27817729943). Remaining: 2 harder CAT-B (resume-died-rollback + archivebackup-resume) + 5d (CAT-C + shared-fixture + matrix) + 5e (matrix full-suite → delete fabricate). Both base arcs GREEN (working re-stamp + failing clean-slate AC#2).

## 0. The ONE mechanism (AC#3) — and the key correction
Every kill scenario fakes ONLY the SCHEDULING: `fabricate_scheduled_upgrade_row` (data-helpers.sh:266) hand-INSERTs a daemon-down `scheduled` public.upgrade row — needed ONLY because the legacy baseline (v2026.05.2, pre-086) had no register/schedule. **The CRASH is ALREADY REAL** — every reshape-target drives the crash through the product's real inject points via `STATBUS_INJECT_AT`.

**RESHAPE = a MECHANICAL swap:** `fabricate_scheduled_upgrade_row` → real `./sb upgrade register` + `schedule` (086 RunSchedule, daemon quiesced → the SAME persistent daemon-down `scheduled` row, for real). Baseline v2026.05.2 → base_sha (install_statbus_at_sha). The `STATBUS_INJECT_AT` crash + dispatch + recovery assertions are UNCHANGED. **PROVEN** across 5a/5b/5c.

**CORRECTION (load-bearing):** the mid-migrate inject points EXIST and CAT-C ALREADY uses them (migrate.go:388, :911, :202, :844/:845). So CAT-C is the SAME swap as CAT-A/B — NOT a "needs new inject" special case. Q5-2's "prefer self-failing migrations" is moot for mid-migrate; it applies ONLY to worker-ddl-deadlock (the one true no-inject).

## 1. Inventory (verified from the scenario files + recovery semantics confirmed on-VM)
**CAT-A — KillHere kills (daemon-DOWN + ./sb install inline-dispatch). ALL GREEN (5a/5b):**
- 2-preswap-checkout-kill (service.go:4261) — PreSwap → recoveryRollback → rolled_back. 5a driver proof.
- 2-preswap-backup-kill (exec.go:618) — PreSwap, partial-syncing-never-promoted guard.
- 2-preswap-binary-swap-kill (:4326) — PreSwap → never-completed (:945 guard).
- 3-postswap-container-restart-kill (:4779) — Resuming → recoveryRollback → UPGRADE_DIED_DURING_RESUME (C8, inline path).
- 4-rollback-kill (C9, :5646 builtin-rollback) — **DETERMINISTIC outcome-B** (run-resolved): PreSwap → recoveryRollback → d.rollback → :5646 → C9 fires → rolled_back. (The stale legacy both-outcomes was retired; see §5 recovery-path lesson.)

**CAT-B — STALL/timeout/watchdog (daemon-RUN + dropin). Mechanism GREEN (5c/C15):**
- 3-postswap-watchdog-reconnect (C15) — dropin STALL + active-phase WatchdogSec ticker → 0 kills → completed. **PROVEN** (the stall-dispatch mechanism).
- 3-postswap-archivebackup-watchdog, 3-postswap-migration-timeout (migrate.go:363), 4-rollback-restore-watchdog — ride C15's stall mechanism (structure+review).
- 3-postswap-resume-died-rollback — **4th sub-variant: daemon-RUN + dropin KILL** (reuses killed-by-system-during-container-restart, NO new site; fires at applyPostSwap during the post-exit-42 DAEMON resume → flag Resuming → recoveryRollback → rolled_back + UPGRADE_DIED_DURING_RESUME). KEY = NRestarts BOUNDED (~2, not climbing — the one-shot Resuming latch breaks the StartLimitBurst loop). VM-prove.
- 3-postswap-archivebackup-resume — **CONTRACT RESOLVED** (verified runs 27107825797+27109134019, scenario lines 72-77): the kill path leaves Phase=Resuming → the resume ROLLS BACK then reconciles to 'completed' (rollback-then-recomplete); NRestarts=1; archiveBackup NEVER reached; terminal completed. (The FIX-A "0-kills + completed-while-stalled" at lines 67-71 was the IDEALIZATION the verified runs DISPROVED — and my own tmp/architect-archivebackup-resume-diagnosis.md already had "archiveBackup never ran this run".) (e)-gate INVERTS to ANTI-VACUOUS: assert NRestarts∈[1,2] (≥1 proves the kill+rollback happened, NOT a vacuous 0-restart clean-complete; ≤2 bounded, not the climbing RED wedge) + completed + data intact. Carry the FIXED atomic check (ssh-rc separated from the assertion). "Reach archiveBackup" = DEFERRED open question. Rides C15's dropin-stall + the kill primitive; OUTCOME = rollback-recomplete (not C15's 0-kills). VM-prove.

**CAT-C — mid-migrate, real inject ALREADY USED (recovery semantics confirmed from headers):**
- 3-postswap-mid-migration-kill (:388, KillHere) → PostSwap → forward-recovery (017 inline migrate.Up, one-shot marker consumed) → completed. **Rides 5a's KillHere mechanism** (structure+review).
- 3-postswap-between-migrations-kill (:911, KillHere) → PostSwap → forward-recovery → completed. **Rides 5a** (structure+review).
- 3-postswap-mid-tx-kill (:202, MidTxPauseSQL→SIGKILL) → tx rolls back BEFORE commit → forward-recovery (clean re-apply) → completed. **NEW mechanism → VM-prove.**
- 3-postswap-migrate-killed-after-commit (:844/:845, stall→SIGKILL after commit) → forward-recovery NATURALLY FAILS → rollback → rolled_back (the rune shape). **NEW mechanism → VM-prove; DETERMINISM-SENSITIVE** (the legacy needed a one-off run to confirm rolled_back — same forward-fails→d.rollback path the rollback-kill comment :5637-5644 flagged as migration-set-dependent).

**DELETE (subsumed / legacy):**
- 3-postswap-migration-deterministic-error — SUBSUMED by the failing arc (real V_fail → rollback → clean-slate). DELETE.
- 2-preswap-checkout-kill-legacy — superseded by the reshaped 2-preswap-checkout-kill (post-086). DELETE.

**ASSESS (the ONE true no-inject):**
- 3-postswap-worker-ddl-deadlock — no STATBUS_INJECT_AT. Needs a self-failing/concurrent-DDL migration fixture, OR King-flag (product change, beyond charter, per Q5-2), OR documented residual. Per-scenario judgment in 5d.

## 2. Driver variants (the framework pieces) — 3 PROVEN, 1 design-passed
The reshaped scenarios live in upgrade-arc-harness.yaml (Q5-1; share install_statbus_at_sha + B-fixture + signing). FOUR driver variants by inject mechanism:
1. **daemon-DOWN + ./sb install inline-dispatch + STATBUS_INJECT_AT** (5a) — CAT-A KillHere. PROVEN. Helpers arc_schedule_daemon_down + arc_install_dispatch_with_inject.
2. **daemon-RUN + register/schedule (NOTIFY claim)** — working/failing arcs. PROVEN.
3. **daemon-RUN + dropin STALL + WatchdogSec** (5c) — CAT-B stall. PROVEN (C15). Helpers arc_install_stall_dropin (install dropin → daemon-reload → **RESTART unit** so the daemon PROCESS inherits STATBUS_INJECT_AT — load-bearing (c); the env must survive into the claimed upgrade) + arc_nrestarts + arc_wait_row_state. (e) anti-false-pass: assert the stall ACTUALLY held (row still in_progress ≥WatchdogSec) before measuring NRestarts.
4. **daemon-RUN + dropin KILL** (resume-died-rollback, 4th sub-variant) — the (c) restart-for-env extends: the dropin env must survive the exit-42 syscall.Exec re-exec into the resumed daemon, so the kill fires at the resume's applyPostSwap. Design-pass done; VM-prove pending.

## 3. Phasing (each phase → architect review → foreman commit → VM-prove → next)
- **5a** ✓ GREEN — kill-arc driver + checkout-kill.
- **5b** ✓ GREEN — CAT-A ×4 (backup/binary-swap/container-restart/rollback-kill). rollback-kill resolved to DETERMINISTIC outcome-B (alarm-reversal: VM disproved a stale-legacy both-outcomes; recoveryRollback→d.rollback→:5646 is unconditional).
- **5c** ✓ GREEN (C15) — the CAT-B stall-dispatch mechanism. + the easy CAT-B (archivebackup-watchdog / migration-timeout / rollback-restore-watchdog) ride C15 (structure+review, no per-scenario VM).
- **5c-hard** — 3 CAT-B routed to engineer (build order): rollback-restore-watchdog (ride-vs-VM call on its 2-step shape) → resume-died-rollback (dropin-KILL 4th sub-variant, VM-prove) → archivebackup-resume (rollback-recomplete/NRestarts∈[1,2]/completed contract, inverted (e)-gate, VM-prove). Easy-2 (migration-timeout + archivebackup-watchdog) COMMITTED 9f3463f87.
- **5d** — CAT-C: :388/:911 ride 5a (structure+review); :202 mid-tx + :844/:845 after-commit = 2 NEW mechanisms (VM-prove each); DELETE deterministic-error + checkout-kill-legacy; ASSESS worker-ddl-deadlock. **ALSO in 5d: the shared-fixture construct refactor + the matrix run-arc mode** (§8) — the 5e enabler.
- **5e** — run the shared-fixture MATRIX full-suite (every reshaped scenario, ONE dispatch, parallel) GREEN → then DELETE `fabricate_scheduled_upgrade_row` at zero callers (AC#4) + sweep unused synth helpers. Confirm `rg fabricate_scheduled_upgrade_row` = 0.

## 4. AC mapping + King doctrine
- **AC#3** = §0's swap (family-wide; crash stays real) + DELETE the subsumed deterministic-error.
- **AC#4** = 5e: fabricate_scheduled_upgrade_row deleted at zero callers; no synthetic crash-state remains (real inject writes the real flag/state).
- **King doctrine (NO residual):** every fake → real or DELETED. Only possible residual = worker-ddl-deadlock IF no faithful real path → King-flag or DOCUMENTED residual, never silent.

## 5. Risks / decisions / lessons (updated from the build)
- **Recovery-path is a risk axis, not just the inject mechanism (rollback-kill lesson).** A "faithful verbatim reshape" can carry a STALE model: rollback-kill copied a pre-:945-guard both-outcomes (outcome A = forward→completed) that the current code makes impossible (PreSwap → recoveryRollback unconditionally). The VM run is the oracle — it disproved the static no-C9 hypothesis; re-reading found recoveryRollback (service.go:2174) IS a wrapper around d.rollback() (:2271), which runs the FULL pipeline through :5646 unconditionally (the ":954 db not modified" is only the restoreDatabase no-op, NOT a skip). LESSON: read the CALL, not the reassuring log string; check reshapes against CURRENT recovery semantics, not just structure.
- **recoverFromFlag branches by FLAG PHASE** (service.go:766): PreSwap (default) → :945 recoveryRollback (unconditional, never self-heal); PostSwap → resumePostSwap (forward); Resuming → verifyUpgradeGroundTruth → not-behind=forward / behind=rollback. d.rollback()'s :5646 (C9) is UNCONDITIONAL within the function (after restoreDatabase, no conditional skip) → reached on EVERY rollback path.
- **Determinism-sensitive scenarios get a VM-prove + deterministic asserts.** after-commit (:844/:845) reaches d.rollback via the forward-FAILS path — the comment :5637-5644 calls this migration-set-dependent. The VM-prove reveals the real outcome; assert it DETERMINISTICALLY (no both-outcomes hedge), as done for rollback-kill.
- **(c) dropin-env-inheritance needs a RESTART, not just daemon-reload** (5c): a running daemon keeps its start-time env; the dropin env reaches executeUpgrade only after a unit restart. For the dropin-KILL resume variant, the env must further survive the exit-42 re-exec.
- **(e) anti-false-pass (vacuous-guard family):** a bounded-restarts / no-kill assertion is trivially true if the stall/kill never engaged → always assert it ACTUALLY engaged (row/NRestarts state proves it). For C15: still-in_progress after hold. For archivebackup-resume: INVERTED — NRestarts∈[1,2] (≥1 proves the kill+rollback happened, not a 0-restart clean-complete) + completed.
- **archivebackup-resume contract RESOLVED** (verified runs 27107825797+27109134019, scenario lines 72-77): rollback-then-recomplete + NRestarts=1 + archiveBackup-never-reached + completed. My initial FIX-A "0-kills" read (lines 67-71) was the IDEALIZATION the verified runs DISPROVED — and my own diagnosis.md already had "archiveBackup never ran this run". LESSON (TWICE now, with rollback-kill's :954): a design/aspiration comment describes INTENDED behavior; a later VERIFIED-runs note (or my own diagnosis) describes ACTUAL behavior — when they conflict, the verified note + the run win. Scan for "VERIFIED"/"NOTE"/"CORRECTION"/run-IDs before trusting a design comment as the contract.
- **Preserve each scenario's exact crash-shape contract** + its load-bearing guard (C3 partial-never-promoted; C5 never-completed :945; C9 :5646-deterministic; resume-died NRestarts-bounded-not-climbing). Each phase VM-proves the contract holds.
- **No new product inject sites in §9(5)** (Q5-2): worker-ddl-deadlock is the only product-change candidate → King-flag, never autonomous.

## 6. VM-prove strategy — B-REFINED (per inject MECHANISM, not per scenario)
The risk axis is the inject MECHANISM (the dispatch/recovery variant), not the per-scenario site. VM-prove ONE representative per DISTINCT mechanism; same-mechanism site-variants reshape by structure + architect review + the final matrix full-suite. Cost is trivial (~€0.01/run); the constraint is wall-clock + not re-proving a proven mechanism.
- KillHere inline-dispatch — PROVEN (5a checkout-kill). CAT-A ×4 + CAT-C :388/:911 ride it (review only).
- dropin STALL + WatchdogSec — PROVEN (5c/C15). Easy CAT-B rides it. archivebackup-resume rides the stall+kill primitives but its OUTCOME differs (rollback-recomplete/NRestarts=1, not C15's 0-kills) → VM-prove.
- dropin KILL during the post-exit-42 resume — resume-died-rollback (VM-prove pending).
- mid-tx MidTxPauseSQL→SIGKILL (:202) + after-commit stall→SIGKILL (:844/:845) — VM-prove each (5d; after-commit determinism-sensitive).
- dropin KILL (resume) — resume-died-rollback (VM-prove pending).
- mid-tx MidTxPauseSQL→SIGKILL (:202) — VM-prove (5d).
- after-commit stall→SIGKILL (:844/:845) — VM-prove (5d, determinism-sensitive).
**NON-NEGOTIABLE:** the 5e matrix full-suite runs EVERY reshaped scenario at least once before fabricate is deleted — that is "the run is the oracle" per scenario, batched. Fall back to per-scenario interim proofs only if the matrix can't run all.

## 7. Shared-fixture construct refactor + matrix 5e (the one-run full-suite enabler)
TODAY the arc-harness names V per-scenario (migrations/${v}_upgrade_arc_${SCENARIO}.up.sql) → each scenario = a distinct B/C image = ~14 image sets → one-run-all impossible. KEY: the working-V CONTENT is identical across all non-failing arcs; only the FILENAME forces distinct images.
- **(1) Shared-fixture refactor:** construct builds ONE working B/C (shared filename upgrade_arc_working) + ONE failing B/C (upgrade_arc_failing) → ~2 image sets cover all ~14. CONTRACT-SAFE: each scenario's contract is in its INJECT CLASS + ASSERTS (the arc script), NOT the B-fixture; the inject class is a per-scenario RUNTIME param. All kill arcs (CAT-A/B/C) use the working B (the kill fires at the inject point; even mid-migrate kills fire during the working V's apply); only the failing arc uses the failing B. V_VERSION stays one shared value.
- **(2) Matrix mode (mirror install-recovery STATBUS-025):** construct (shared B/C) ONCE → image-wait ONCE → discover → JSON-matrix → run-arc MATRIX (one VM per scenario, parallel, max-parallel) → cleanup. Add a `scenarios`/"all" input. 5e = ONE dispatch over all ~14 in parallel (~2 builds + ~14 VMs ≈ €0.10, ~20-40min).
- Fallback: install-recovery's existing matrix could host it, but teaching it the arc construct (B-fixture+signing) is more work than matrix-izing the arc-harness. Arc-harness matrix is the clean path. Build both into 5d so 5e fires the full-suite.
