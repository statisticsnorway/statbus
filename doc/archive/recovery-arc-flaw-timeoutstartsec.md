# The recovery arc missed the start phase — why NO is wedged, and the correct fix

**Status: HISTORICAL RECORD (archived 2026-07-12, STATBUS-043).** This is the 2026-05 diagnosis of the Norway/rune start-phase wedge, kept as incident analysis — past tense throughout. **Nothing operational in this file is current**: the §4b recovery sequence is the superseded stop-first footgun (see its banner); §4a's A-alone decision was reversed (B1 shipped — the resume runs active-phase); and the recovery model has since moved to classify-then-act with the park regime and the read-only window (STATBUS-039/046/110/145/154/159/160). For the shipped system read `doc/upgrade-recovery-model.md`, `doc/upgrade-timeline.md`, and `doc/recovery/upgrade-resume-structural-whole.md` (the design that superseded this diagnosis's fix).

*Original status (2026-05-26):* diagnosis + recommended fix (architect). PARAMOUNT (Norway production is wedged). Belongs to the recovery-injection arc. NOT the UX plan.

**Evidence base:** dev journal upgrade id=183511; foreman SSH-confirmed NO ground truth (id=187); operator archaeology `tmp/operator-recovery-arc-archaeology.md`; operator unit/timeout reconcile `tmp/operator-timeoutstartsec-reconcile.md`; my direct reads of `service.go`, `exec.go`, `watchdog.go`, `ops/statbus-upgrade.service`; recovery-sequence mechanics `tmp/operator-no-recovery-sequence.md` (in flight — recovery section flagged where pending). All line numbers verified.

---

## TL;DR

NO (Norway, `rune.statbus.org`, 32 GB DB) has been **looping every ~2.5 min for ~40 h** on the rc.01 upgrade (id 187), stuck in systemd `activating (start)`, never reaching `READY=1`. Each cycle: `archiveBackup` (a 32 GB `tar`) runs in the systemd **start** phase under `TimeoutStartSec=120`, can't finish in 120 s, gets SIGTERM'd ("start operation timed out"), the row stays `in_progress`, and `Restart=always` re-enters the identical doomed tar.

The 134-commit recovery arc built three defenses against "a long step gets killed by a systemd timeout" — but **all three target the wrong systemd phase or the wrong layer**, and the one fix that *did* address the start phase was **deleted on a misread of the control flow**. The recovery arc cannot help NO for two compounding reasons: (1) NO is on a *pre-fix* binary (rc.01 predates the merge) and loops before it can advance to a fixed one; (2) even the fixed binary would still bound a DB-size-scaled backup to a fixed 120 s budget, fatal at 32 GB.

**Correct fix:** emit `READY=1` *before* the recovery/resume work, so the resume runs in the **active** phase under the existing `WATCHDOG=1` ticker (which already keeps long active-phase steps alive) — plus reorder `archiveBackup` after the completion UPDATE as defense-in-depth. Add a RED scenario that runs a resume's `archiveBackup` past `TimeoutStartSec`. Recover NO via the sanctioned stop → land-fixed-binary → `./sb install` → restart sequence.

---

## 1. Archaeology — what each prior fix assumed

The arc correctly identified the failure *class* ("a long-running step during an upgrade gets SIGTERM'd by a systemd timeout") and shipped three defenses plus a budget alignment. Each rests on the assumption that `applyPostSwap` runs in the **active** phase (post-`READY=1`, governed by `WatchdogSec`):

| Commit | Date | What it did | What it assumed |
|---|---|---|---|
| **b7ee2a0ca** | 05-25 | Widened the `WATCHDOG=1` ticker (`service.go:3646–3665`) to cover the whole `applyPostSwap` remainder (migrate, build, archiveBackup). | `applyPostSwap` runs **active-phase**; `WATCHDOG=1` resets `WatchdogSec` and keeps it alive. *(Correct — for the active-phase entry only.)* |
| **26d79f8ac** | 05-25 | Raised the **in_progress budget** 180 s → 600 s (`IN_PROGRESS_BUDGET_S`, set in `writeUpgradeFlag` ~`service.go:361`). | A DB/flag-side staleness budget governs long destructive work. *(Wrong layer — this is orthogonal to systemd `TimeoutStartSec`; raising it does nothing for a 120 s start-phase kill.)* |
| **e6df084b7** | 05-23 | **Deleted** `sdNotifyExtendTimeout` (the `EXTEND_TIMEOUT_USEC` start-phase timeout extender). | "`applyPostSwap` is already active-phase by the time `archiveBackup` runs, so the start-phase extender is a no-op." *(Wrong — based on a control-flow misread; see §2.)* |
| **f43b2bfd1** | 05-23 | Set `TimeoutStartSec=120` (`ops/statbus-upgrade.service:75`, was system default 90 s) to match `WatchdogSec=120`. | "One limit to reason about"; both phases get 120 s. *(Cemented a fixed 120 s ceiling on the start phase — fatal once a large-DB step lands there.)* |

`scenario 26` ("archivebackup-watchdog") tests `archiveBackup` under `WatchdogSec` in the **active** phase (and passes — the ticker works there). `scenario 18` (C11) tests a *generic* startup stall before `READY=1` under `TimeoutStartSec` (right phase, but a trivial injected site). **Neither exercises a resume's `archiveBackup` in the start phase.**

---

## 2. The flaw — a phase-attribution error, and a deleted-the-right-fix keystone

**There are two distinct entries into `applyPostSwap`:**
- **Scheduled upgrade** — dispatched by the main loop *after* `sdNotify("READY=1")` (`service.go:1574`). Runs **active-phase**; the `WATCHDOG=1` ticker protects it. This is the path the arc considered.
- **Exit-42 resume** — `recoverFromFlag` runs at `service.go:1517`, *before* `READY=1` (1574), inside `Service.Run`'s init. `resumePostSwap` → `applyPostSwap` → `archiveBackup` (`service.go:3782`) → completed-UPDATE (`service.go:3806`) all run **before** control returns to reach `READY=1`. So the resume runs entirely in the **start** phase under `TimeoutStartSec`.

**The keystone (empirically verified — a factual error in a committed comment):** commit e6df084b7's message and the `watchdog.go` historical note (lines 158–179) claim *"the first health check clears mid-`applyPostSwap` → `Service.Run` sends `READY=1` (line 1574) → the service transitions to active → the remaining `applyPostSwap` work (`archiveBackup`) runs under `WatchdogSec`."* This is false on the control flow:
- `rg 'sdNotify("READY=1")'` → **exactly one call site**, `service.go:1574`. None in `exec.go`. No health-triggered `READY=1` goroutine anywhere.
- `healthCheck` is called *inside* `applyPostSwap` (`service.go:3769`) and returns an `error` to `applyPostSwap`'s own control flow — it does **not** signal `Service.Run` to emit `READY=1`.
- `READY=1` (1574) is reached **only after `recoverFromFlag` (1517) returns** — i.e. after the entire resume, including `archiveBackup`, has finished.

So on the resume path `archiveBackup` is unambiguously **pre-`READY=1` = start phase = `TimeoutStartSec`** — exactly matching NO's journal ("start operation timed out"). The `watchdog.go` note even contradicts itself (line 79 "after `READY=1`" vs lines 14–15 "pre-`READY=1`"), conflating the two paths.

**Fair verdict (the user's "were the fixes incorrect, and HOW"):** the fixes were *correct for the path they considered* (scheduled, active-phase) but **incomplete** — they missed that the recovery/resume path re-enters the same code in a different systemd phase where their protection does not apply. e6df084b7 then *deleted the one mechanism* (`EXTEND_TIMEOUT_USEC`) that protected the start-phase resume — the author observed a `WatchdogSec` kill in one field run (which happens on the *scheduled* path, genuinely active-phase) and over-generalised to "always active-phase, so the extender is dead code." For NO's exact failure mode it was not dead code; it was the only start-phase protection. Three fixes, three layers, all anchored to the same active-phase misattribution; the one fix that addressed the start phase was removed.

---

## 3. Why NO still hangs (confirmed)

- NO upgrade id=187 (rc.01); `systemctl status` = **`activating (start)`**; never reaches `READY=1`; looping **~2.5 min for ~40 h**. Journal repeats: "start operation timed out. Terminating" → "archive backup failed: signal: terminated" → "Failed with result 'timeout'".
- **NO DB = 32 GB**; a 32 GB `tar` cannot finish in `TimeoutStartSec=120`.
- Mechanism: resume runs `archiveBackup` (`service.go:3782`) in the start phase → `TimeoutStartSec` SIGTERMs it mid-tar, *before* the completed-UPDATE (`service.go:3806`) → row stays `in_progress`, flag stays on disk → `Restart=always`/`RestartSec=30` re-enters the identical resume → identical 32 GB tar → killed again → loop. **Convergence is impossible** while `archiveBackup` > 120 s in the start phase.

**Phase confirmed empirically (operator `tmp/operator-no-timer-resolution.md`):** across cycles, **no "Upgrade service started" / `READY=1` line appears before the kill** (pid 713390: start 22:58:20 → kill 23:00:21 = 120.8 s; pid 715474: 123.2 s). So the kill is unambiguously **pre-`READY=1` = start phase = `TimeoutStartSec`**. My reading holds.

**Deployed-vs-repo unit divergence (important):** the *deployed* rune unit has **`WatchdogUSec=infinity` (watchdog DISABLED)** and `TimeoutStartUSec=90 s` — it predates *both* the repo's `WatchdogSec=120` and the f43b2bfd1 `TimeoutStartSec=120` change. (Observed kill ~120 s vs configured 90 s: a residual gap the operator didn't fully resolve; immaterial to the verdict — the kill is firmly start-phase.) The fix must work for **both** the old deployed shape (90 s start, no watchdog) and the current repo shape (120/120).

**Three compounding reasons the arc can't help NO:**
1. **It doesn't reach NO.** rc.01 (51670d9e, 05-24) is an *ancestor* of the recovery merge ca4696c27 (05-26). NO is on a *pre-fix* binary and loops in the start phase before it can advance to a fixed one — the fixes literally never execute there.
2. **The ticker is active-phase-only AND the watchdog is off.** Even the fixed binary's `WATCHDOG=1` ticker (b7ee2a0ca) is useless on NO twice over: NO's `archiveBackup` is start-phase (where `WATCHDOG=1` is a no-op), *and* `WatchdogUSec=infinity` means there's no watchdog to keep alive at all. The arc built watchdog protection for a unit with the watchdog disabled.
3. **The in_progress budget is the wrong phase.** 26d79f8ac's 600 s `IN_PROGRESS_BUDGET_S` governs the DB-down window, not the start-phase `archiveBackup`. Inert here.

### Second flaw — the StartLimit doesn't catch a slow loop

`StartLimitIntervalSec=600` / `StartLimitBurst=10`. NO loops every ~2.5 min (120 s timeout + 30 s `RestartSec`) ≈ **4 restarts per 600 s window — under the burst threshold** — so the start-limit cap *never trips*; NO loops indefinitely (40 h), reporting `activating`, missed by every health-check. This is the **exact failure mode** the cap was added (plan-rc.66, "Item L", `ops/statbus-upgrade.service` comment) to prevent — that comment cites `statbus_jo` doing 11000+ restarts over 91 h "reporting `activating` instead of `failed`, missed by every standard health-check." The cap catches *fast* loops but a *slow* timeout-loop stays under burst=10/600 s. **Item L's mitigation is insufficient against a slow loop.**

---

## 4. The correct fix (recommended)

### 4a. Code fix — two complementary changes

The NO per-cycle journal (914 cycles, pid 711407) sharpens exactly *what* fails: resume → migrations → services healthy → "Verifying health" passes → "maintenance OFF" → **[~2 min silent `archiveBackup` of 32 GB]** → systemd "start operation timed out. Terminating." → "archive backup failed: signal: terminated" → the process **logs "Upgrade … completed successfully"** → "Connection stale on state=completed UPDATE (id=187, err=timeout: **context already done: context canceled**), reconnecting…" → "INVARIANT RECONNECT_ON_STALE_CONN_SUCCEEDS violated … `service.go:3570`" → exit 1. **The SIGTERM cancels the DB context**: `archiveBackup` is *already non-fatal* (the code proceeds), but the completed-UPDATE (`service.go:3806`) then can't persist (canceled context) and the reconnect-retry also fails (`service.go:3570`) → row 187 never reaches `completed` → loop. So the failure is **ordering**: the slow, kill-prone `archiveBackup` runs *before* the fast completed-UPDATE.

**FIX A — reorder `archiveBackup` after the completion UPDATE (PRIMARY; directly evidence-backed).** Move `d.archiveBackup` (`service.go:3782`) to *after* the `state='completed'` UPDATE (`:3806`) + `removeUpgradeFlag` (`:3850`). The fast UPDATE then persists *inside* the systemd budget (the work before it — migrate(no-op)/docker/health — is quick on NO; the row reaches `completed` and the flag is removed in seconds), and the multi-minute `archiveBackup` that follows can be SIGTERM'd **harmlessly** — the next start finds no flag, no-ops, and NO is done. Backup-archival is non-critical-path (it tars the *pre-upgrade* backup for forensics; `pruneBackups` already runs post-completion at `:3858`). This is the single highest-leverage change and it converges NO **regardless of which systemd timer** fires.

**FIX B1 — emit `READY=1` before `recoverFromFlag` (STRUCTURAL complement).** Move `sdNotify("READY=1")` to *after* the genuine cheap init (`EnsureDBUp` `:1475`, `boot-migrate-up` `:1491`, `connect` `:1498`, advisory lock `:1505`) but *before* `recoverFromFlag` (`:1517`). Then the whole resume runs in the **active** phase, escaping `TimeoutStartSec` entirely. It works on both unit shapes: on the *repo* unit (`WatchdogSec=120`) the existing 30 s `WATCHDOG=1` ticker (b7ee2a0ca, `service.go:3646–3665`) now actually keeps the unit alive through a long step (today that ticker *runs* during the resume but its pings are **no-ops** — `WATCHDOG=1` only resets `WatchdogSec`, which isn't armed in the `activating` phase, so the arc built a ticker that pings a watchdog that isn't listening yet); on the *deployed* NO unit (`WatchdogUSec=infinity`) the active phase simply has *no* timeout, so the resume runs to completion. B1 reuses the arc's *retained* mechanism, makes the resume consistent with the scheduled path, and does **not** resurrect the deleted `EXTEND_TIMEOUT_USEC`. Verified safe: nothing forces `READY=1` to follow recovery — its placement rested entirely on the e6df084b7 misread; `Type=notify` + `Restart=always` + advisory lock + flag still serialise a genuine crash.

> **⚠ SUPERSEDED (resolved 2026-06 — the structural whole shipped).** The 2026-05-27 "FIX A ALONE / B1 DROPPED / resume stays start-phase" decision below (and the §"NOTE" open-decision framing further down) was **REVERSED**: the King chose the fully principled structural plan — see `doc/recovery/upgrade-resume-structural-whole.md`. **B1 (now "plan piece #2") SHIPPED.** The landed code emits `sdNotify("READY=1")` at `service.go:1621` (comment: *"plan piece #2, B1 + boot-migrate-move"*) **before** `recoverFromFlag` (`:1669`) and **before** boot-migrate-up (`:1644`). **The exit-42 resume therefore runs in the ACTIVE phase, NOT the start phase** — confirmed empirically by install-recovery run `27107825797` (`3-postswap-archivebackup-resume`): `SubState=running` at t+0 (unit active) with the resume completing the row at t+43 s governed by `WatchdogSec`, never `TimeoutStartSec`. FIX A is now **defense-in-depth** (a kill during the post-completion tar is harmless), not the SOLE protection. Read the paragraphs below as the HISTORICAL 05-27 decision point; the specific claims *"keeps the resume in the start phase"* (next paragraph) and *"does NOT move `READY=1`"* (Paramount-commit paragraph) are **FALSE as-shipped**.

**Sequencing — FINAL DECISION: ship FIX A ALONE (user's call, 2026-05-27). B1 + B1-OFFSET DROPPED.** A-alone converges NO: the reorder lands the `state='completed'` UPDATE + `removeUpgradeFlag` *before* the kill-prone `archiveBackup`, so the row reaches `completed` on the first resume cycle and the subsequent start-phase `TimeoutStartSec` kill of the tar is harmless (next start finds no flag → no-op → `active`). NO converges in ~1 harmless kill cycle. A-alone keeps the resume in the **start phase** (where `TimeoutStartSec` is a natural hard bound on any *hang*), has **no readiness-semantics regression**, and **eliminates the entire B1 sub-tree** — no `READY=1`/`LISTEN` move, no B1-OFFSET, and crucially **no unit-template-reconcile hard dependency** (A-alone doesn't rely on `WatchdogSec` being armed). Smaller, safer RC. Validate on scenario 27 first, then recover prod NO via §4b.

**Paramount commit (A-alone):** the `archiveBackup` reorder (`service.go:3782` → after `:3806`/`:3850`, commit `4d9b1e075`) + scenario 27 + the `ops/statbus-upgrade.service` removal of the false `EXTEND_TIMEOUT_USEC` claim (correct regardless of A/B1), with the `watchdog.go` + unit-file phase-framing reconciled to the A-alone truth: *applyPostSwap runs active-phase on the scheduled path but **start-phase on the exit-42 resume path** (`recoverFromFlag`@`:1517` is pre-`READY=1`); FIX A makes the start-phase resume safe by ordering the completed-UPDATE ahead of the tar — it does NOT move `READY=1`.* **[SUPERSEDED — see banner above: B1/plan-piece-#2 SHIPPED; `READY=1` IS moved to `service.go:1621` and the resume runs ACTIVE-phase. This paragraph's "start-phase resume" framing is historical only.]**

**ATOMIC (task #8, commit `33a9efc80`, bundled into this RC) — the principled hardening of the archive site.** `archiveBackup` now tars to `<version>-pre.tar.gz.tmp` → fsync → `os.Rename(.tmp→final)` only on tar success; `pruneArchives` reaps stale `.tmp` orphans (`exec.go:706`+`:731`). This addresses the user's "code smell" objection directly: an interrupted/killed/failed tar can no longer leave a **partial at the final name** masquerading as a complete archive (the prior direct-to-final write did exactly that). It's the canonical crash-safe write pattern — robust to ANY interruption, not just the start-phase timeout — and complements FIX A (FIX A: the row completes *before* the tar; ATOMIC: the tar, if killed, doesn't masquerade as complete). Best-effort + loss-free (the archive is forensics, not the rollback artifact). Test-first: `TestArchiveBackup_FailedTarLeavesNoFinal` RED pre-ATOMIC / GREEN now; + scenario 27 `gzip -t` integrity check.

> **NOTE on the structural question (the King's "principled vs patch" concern, 2026-05-27):** FIX A + ATOMIC make the loop stop AND the killed tar clean — but the *structural* wart remains: a multi-minute DB-size-scaled tar still **runs** inside the budgeted start phase where a fixed `TimeoutStartSec` SIGTERMs it mid-write. The kill is now harmless+clean, not absent. The fully principled set that removes the wart (vs. making its symptom benign) is B1-done-right (resume → active phase, progress-fed watchdog) + DETACH the tar out of any budgeted phase + the slow-loop liveness guard (task #7). Whether to ship that principled whole as one RC vs. land FIX A+ATOMIC now (stop the bleed) + the structural completion as a deliberate committed follow-up is **the King's open decision** — see the report relayed via foreman. Patch-to-stop-the-bleed is defensible; patch-AS-the-resolution is not. **[RESOLVED 2026-06: the King chose the principled whole — B1/plan-piece-#2 (resume → active phase), the progress-gated `WATCHDOG=1` ticker, and the slow-loop liveness guard ALL shipped (`doc/recovery/upgrade-resume-structural-whole.md`). The structural wart is removed, not merely made benign; FIX A remains as defense-in-depth.]**

**B1 + B1-OFFSET — CONSIDERED AND DROPPED (kept for the record).** B1 = move `READY=1` (Option Y: + `LISTEN`) before `recoverFromFlag` so the resume runs active-phase. Its only benefit over A-alone was 0 kill cycles vs 1 (and covering a slow migrate/docker on the resume, already a known quantity on the scheduled path). Its cost: a still-running/hung recovery would report `active (running)` instead of `activating`, removing the natural start-phase hang-bound and requiring (a) the B1-OFFSET progress-gated watchdog AND (b) an armed `WatchdogSec` (NO's deployed unit had `WatchdogUSec=infinity`) — a whole dependency sub-tree for a marginal gain. The user's call: not worth it; ship A-alone. *(If B1 were ever revisited: Option Y placement + the ProgressLog-owned progress-gated ticker spec'd earlier are the correct shapes.)*

**Known residual (Finding 1, fast-follow — not in this commit): `boot-migrate-up`@`:1491` stays pre-`READY=1`.** It is genuine schema-skew init that *should* gate readiness, so it correctly was **not** moved. But it is the one pre-`READY=1` step that is both DB-size-scaled and readiness-gating: a *single* slow migration at boot on a large DB can still blow `TimeoutStartSec` and re-run each restart (the same shape as the archiveBackup bug, for a different step). Its contract today is the C11/scenario-18 one ("slow boot migration → killed → `./sb install` bypasses the unit timeout"). Fast-follow design question: give `boot-migrate-up` the same progress-gated coverage, or accept killed+`./sb install` as the right contract for a genuinely-slow boot schema migration. Flagged; not solved here.

**Fast-follow (task #7) — close the slow-loop blind spot.** NO looped 40 h because a ~2.5 min cycle (≈ kill + `RestartSec=30`) stays under `StartLimitBurst=10`/`StartLimitIntervalSec=600`, so the unit never transitions to `failed` — the *exact* "activating, not failed, missed by health-checks" failure the cap was added (Item L) to prevent. Recalibrating burst false-trips the documented legit transient (DB-restart-during-maintenance ≈3 retries, unit comment), so the clean fix is a **new mechanism**: mark the unit `failed` after cumulative `activating`/auto-restart time > N min, regardless of restart count (a small external sidecar-timer + `sb` subcommand reading `ActiveEnterTimestamp`/`SubState`, or hooking the existing `tmp/upgrade-service-heartbeat` staleness that `cloud.sh health` already reads). **Future-defense, not NO-blocking** — A-alone converges NO in 1 cycle so *this* loop never forms; the guard catches a *future* slow-loop of any cause. Own design pass (task #7).

**Optional cleanup (not required by A-alone) — unit-template drift.** NO's deployed unit carries `WatchdogUSec=infinity` / `TimeoutStartUSec=90` while the repo template sets 120/120. Under A-alone this is **not** a hard dependency (A-alone keeps the resume start-phase and doesn't rely on `WatchdogSec` being armed — that coupling only existed for the dropped B1-OFFSET). Still worth having install/upgrade reconcile the deployed unit to the repo template so hosts don't carry stale timeout config indefinitely; low priority, separable.

**Timing question — RESOLVED (operator `tmp/operator-no-timer-resolution.md`):** **no "Upgrade service started" / `READY=1` line appears before the kill in any cycle** → the kill is **pre-`READY=1`, start phase, `TimeoutStartSec`** (confirmed). The deployed unit has `WatchdogUSec=infinity`, so the ~120 s kill is *not* a watchdog kill — it's the start-timeout (the configured-90 s-vs-observed-~120 s residual is unresolved but immaterial: phase is start, killer is `TimeoutStartSec`). This is exactly why A-alone is sufficient — the start-phase kill is rendered *harmless* by reordering the completed-UPDATE ahead of `archiveBackup`.

**Rejected alternatives:** (a) revert e6df084b7 / resurrect `EXTEND_TIMEOUT_USEC` — fights a reasoned prior decision, re-couples budgets. (b) extend `TimeoutStartSec` to 300 s / any fixed wall-clock — the DB-size-scaled-vs-fixed mistake (a bigger DB re-wedges); same error as f43b2bfd1. (c) skip `archiveBackup` on resume — loses the forensic backup; FIX A (defer past completion) keeps it. (d) B1 + B1-OFFSET (progress-gated watchdog) — correct and principled, but a whole sub-tree (active-phase move + offset + armed-watchdog dependency) for a marginal 0-vs-1-kill gain; dropped per the user's A-alone call (full B1-OFFSET design preserved in `tmp/architect-recovery-arc-flaw.md` should B1 ever be revisited).

### 4b. NO-first forward-recovery (sanctioned entrypoints, NO manual DB writes)

> **[SUPERSEDED 2026-06-12 — STATBUS-039/-040/-041. Historical record; do NOT follow the
> stop-first sequence.]** The `stop_upgrade_service → install` path described below was the
> deploy-stop footgun: `systemctl stop` is SIGTERM, which an in-flight upgrade answers with
> a rollback (snapshot restore over the live DB). Both deploy scripts had the pre-stop
> REMOVED (standalone.sh in STATBUS-040/f5b697928, cloud.sh in STATBUS-041/e99c283a6).
> Post-039 (5eacd6305) the current recovery is simply `./standalone.sh install <name>` —
> `./sb install` itself takes over a crash-looping unit SIGKILL-class and refuses a
> genuinely-progressing one. See `doc/upgrade-timeline.md`.

NO is wedged on a pre-fix binary; it must land a *fixed* binary, have its loop stopped, and be re-dispatched. Sanctioned path (operator-confirmed `tmp/operator-no-recovery-sequence.md`; matches `cloud.sh`'s `stop_upgrade_service → install → ensure_service_started`, lines 365–375; NO is user-level systemd, box `statbus@rune.statbus.org`):

> **The normal CI deploy will NOT unwedge the currently-wedged NO (confirmed).** `master-to-rune-no.yaml` force-pushes master → `ops/standalone/deploy/rune-no` → `deploy-to-rune-no.yaml` runs `./sb upgrade apply-latest`, which sends a `NOTIFY upgrade_apply` to the *service*. But NO right now runs the **pre-fix** binary and loops pre-`READY=1`, where it **never establishes the listening PG connection** (that happens in the main loop, post-`READY=1`), so it **cannot receive the NOTIFY**. An operator MUST run the manual install path below. (Pushing the fixed commit to the deploy branch is still the prerequisite — it's where `install.sh` fetches from — but the NOTIFY half is inert against the wedged pre-fix service.) *Note: Option Y (§4a) fixes this going forward — it moves `LISTEN`+`READY=1` ahead of recovery, so a post-fix service buffers NOTIFYs that arrive during recovery instead of losing them. The inertness is a property of the pre-fix code NO is stuck on.*

1. **Land the fix first:** push master → `ops/standalone/deploy/rune-no` so rune's deploy branch points at a binary containing the §4a fix. *(Prerequisite — `install.sh` checks the tree out from here; without the fix, recovery re-wedges.)*
2. **Run `./standalone.sh install rune-no`** (doc/CLOUD.md:740). Operator-confirmed this wraps the full unwedge: it SSHes to rune, **stops the upgrade unit** (`systemctl --user stop`, before binary replacement — avoids text-file-busy and stops the competing resume), **then `install.sh` updates the working tree to the deploy-branch HEAD** (`git fetch` + `git checkout -B current <ref>`, install.sh ~165/224 — tree-update-before-install **confirmed YES**), then runs **`./sb install`**, then `ensure_service_started`. Idempotent — safe to re-run.
3. **What `./sb install` does on NO:** `install.Detect` = `StateCrashedUpgrade` (flag present, holder PID dead after the stop) → `RecoverFromFlag`. Here the row-187 outcome is **COMPLETED (self-healed), not failed** (operator-confirmed): `flag.CommitSHA` = rc.01 target; after the checkout, HEAD is a *descendant* of rc.01, so `recoverFromFlag`'s `merge-base --is-ancestor` (`service.go:765`) returns true → the "code advanced past target = success" branch marks row 187 **`completed`** and removes the flag. Install then re-`Detect`s; with no pending row it lands `StateNothingScheduled` and NO is simply *running the fixed binary, healthy* — the "upgrade to the fixed version" happened via the install checkout, not a scheduled-upgrade row. **NO converges.** (If a newer version is *also* scheduled, that dispatches next under the fixed binary, whose resume now runs `archiveBackup` active-phase per §4a.)

Net: one operator command (`./standalone.sh install rune-no`) after pushing the fix unwedges NO; row 187 ends `completed` (honest — the box is at-or-past rc.01); no manual DB writes.

---

## 5. The test gap + the RED scenario to add

**Why the arc missed it:** `scenario 26` exercised `archiveBackup` in the **active** phase (where the ticker works — so it passed while the production resume path was unprotected); `scenario 18` exercised a *generic* pre-`READY=1` stall (right phase, but a trivial site, not `archiveBackup`); and **no scenario used a large/slow DB**, so a backup that exceeds `TimeoutStartSec` never appeared. The combination — *`archiveBackup` + start phase + budget-exceeding duration* — fell exactly between the existing scenarios.

**RED scenario to add** (to `doc/recovery/recovery-injection-scope-a-comprehensive.md`, new class e.g. `archive-backup-exceeds-systemd-budget-on-resume`): drive a real exit-42 **resume** whose `archiveBackup` exceeds the systemd budget — point `scenario 26`'s existing archiveBackup-stall primitive at the **resume path** instead of the active phase, OR use a genuinely large/slow DB / a stalled `tar`. Assertions:
- **Without the fix (RED — reproduces NO):** the unit loops in `activating`; the journal shows the precise cascade — "archive backup failed: signal: terminated" → "completed successfully" → "state=completed UPDATE … context canceled" → `INVARIANT RECONNECT_ON_STALE_CONN_SUCCEEDS` (`service.go:3570`); **the `public.upgrade` row stays `in_progress`** (the load-bearing assertion — the completed-UPDATE never persisted); and `NRestarts` climbs *without* tripping `StartLimitBurst` at the ~2.5 min cadence (captures the slow-loop blind spot).
- **With FIX A (reorder) — GREEN, the load-bearing check:** even when `archiveBackup` is killed, **the row reaches `completed` and the flag is removed** (the UPDATE ran *before* the tar, so the kill is harmless); the next start no-ops; the unit converges. This validates A *independently of the timer*.
- **With FIX B1 (READY=1 first) — GREEN:** `READY=1` is emitted before the resume, arming `WatchdogSec`; the existing 30 s ticker now keeps the unit alive through the tar, which completes; the unit reaches `active (running)`; no kill at all.

This closes the arc: the scenario that *should* have caught NO (the missing large-DB / resume-path-`archiveBackup` case), the `in_progress`-persists assertion that pins the exact failure, and the slow-loop calibration check.

---

## 6. Proxy-image question — RESOLVED: FALSE ALARM (2026-05-27)

The earlier "rc.01's proxy image is missing" finding is **withdrawn**. Authoritative ghcr.io check (operator, `docker manifest inspect`) confirms **all four rc.01 service images exist right now**:
```
statbus-app:51670d9e    => EXISTS (multi-arch: amd64, arm64)
statbus-worker:51670d9e => EXISTS
statbus-db:51670d9e     => EXISTS
statbus-proxy:51670d9e  => EXISTS
```
rc.01's `Images` run **completed/SUCCESS on 2026-05-25T05:55:12Z** (all build + manifest jobs green), and **no `image-cleanup` ran between then and now** (last cleanup 05-24, before the run; next 05-31). The GitHub outage was 05-26 — a day *after* the successful publish, so irrelevant to rc.01's images.

**Why rune lacks the image:** the original "absent" evidence was a `docker image ls` **on rune** (rune's *locally pulled* images, not ghcr.io). The upgrade loop dies at/before `docker compose pull` (`service.go:3520`/`3745`) — the start-phase `TimeoutStartSec` kill lands before the pull completes — so rune never fetched images that exist on the registry. **This is purely the §4 timeout/phase bug; the §4a fix resolves it directly** (once the resume reaches `docker compose pull/up`, rune pulls the existing images).

**Consequences:**
- **No release-asset gap; no proxy/CI item; no release-gate work.** Struck from scope. (The "require the target's `Images` run GREEN before dispatch" idea remains a *generally sound* release-gate worth considering someday, but it is NOT needed for NO and NOT part of this fix — do not track it as a blocker.)
- **§4b recovery unchanged and simpler:** recovering NO onto a newer GREEN commit works; and even rc.01 itself would now be runnable (its images exist) — the forward path is still preferred, but the proxy is not a constraint.
- **Lesson (process):** `docker image ls` on a host answers "what did this host pull," never "what exists in the registry." Authoritative existence = `docker manifest inspect ghcr.io/...` (public, no API scope). The original conclusion inverted that.

*Non-blocking curiosity (not chased):* `docker manifest inspect statbus-proxy:673b650f` (the tag rune currently runs) returned "manifest unknown" while the image runs locally on rune — likely a per-arch-only tag or stale registry metadata. Unrelated to NO; flagged only so it isn't mistaken for a new problem.

---

## Where this lives

`doc/recovery/recovery-injection-scope-a-comprehensive.md` (correctness/recovery). The UX plan's #2/#3 surface-narration fix (`upgrade-progress-ux-hardening.md`) is the cosmetic complement — it makes a *benign* recovery read as benign; *this* plan makes the recovery actually converge. They are independent and both wanted.
