---
id: doc-028
title: >-
  Unreachability proof — the fabrication carve-out's required artifact
  (STATBUS-071 AC#4, for the King)
type: specification
created_date: '2026-07-08 13:33'
tags:
  - upgrade
  - install-recovery
  - testing
  - fabrication
  - unreachability-proof
  - STATBUS-071
  - STATBUS-044
---
# Unreachability proof — the carve-out's own required artifact

**The rule being instantiated** (071 Implementation Notes, before the King): *"no fabrication where the real path can reach; construction permitted ONLY for a class with a WRITTEN unreachability proof, consumed by the real recovery reader in the run."* This document is that written proof — the rule's first instance. The King asked: *"I need to see the sequence in detail — to judge if I agree it is unrepresentable — or not."*

**The honest outcome, up front.** A fresh adversarial trace (architect, 2026-07-08, no inheritance from prior rulings) SPLITS the class the carve-out was drafted over:

- **RUNE-WEDGE class: the proof HOLDS** — structurally, not just probabilistically. The fixed product cannot compose the state at all (§3).
- **PARK/boot-migrate class: the proof FAILS today.** The arc framework reaches the same state on cue through real dispatch — every required piece is already run-proven in adjacent arcs (§2). The r12 impossibility that justified the fabrication was true of the OLD construction, and I show exactly why it does not generalize.
- **STATBUS-145, if ratified, reshapes the park subject anyway** (§4) — the honest move is one rebuild, not two.

If the King agrees, the carve-out narrows to exactly one class: **dead-producer states** (shapes whose natural producer is a bug we deliberately killed), with the rune-wedge as its only current member.

---

## §1 The constructed state, precisely

### 1a. What `fabricate_resume_state` writes (both scenarios use it — `test/install-recovery/lib/data-helpers.sh:373-501`)

**DB row** (upsert, :426-465): one `public.upgrade` row with `state='in_progress'`, `scheduled_at=now()`, `started_at=now()`, `completed_at/rolled_back_at/error` NULL (satisfying `chk_upgrade_state_attributes`' in_progress arm), `docker_images_status='ready'`, `release_builds_status='ready'`, `recovery_attempts=0`, `recovery_parked_at/reason` NULL.

**Flag file** (`tmp/upgrade-in-progress.json`, :501): `{"id":<row>, "commit_sha":<HEAD>, "pid":999999, "holder":"service", "phase":"post_swap", "trigger":"recovery", ...}` — dead PID, **no** `backup_path`, **no** `Step`/`PriorDeathStep` (a fresh flag that has never recorded a death). Nobody holds the kernel flock (fabrication writes JSON without locking), so the next boot's `acquireFlock` succeeds exactly as after a genuine death.

**Park scenario only** (`3-postswap-resume-died-parked.sh`): additionally ONE synthetic migration file (`migrations/<far-future>_park_scenario_boot_migrate_stall.up.sql`, body `SELECT pg_sleep(3600);`) as the sole pending migration after a steady-state pre-apply of the real delta.

**Rune-wedge scenario only** (`3-postswap-rune-wedge.sh`): NO synthetic migration (schema pre-applied to HEAD — "clean forward is the point"); instead the container set is left at INSTALL_VERSION's images including a **stale-but-SERVING proxy**, and the OLD release's daemon is left **alive-idle** as the takeover target.

### 1b. The "consumed by the real reader" leg — everything after construction is product code

Park: `RecoveryBudgetGuard` (service.go:5783 — flock :5800, park read :5812, increment :5826, escalation consult :5863, `StepBootMigrate` stamp :5884) → boot-migrate (:1934) → the external kills → park → un-park via `./sb install` (install_upgrade.go:238-263). Rune-wedge: the install ladder's crashed-upgrade detection → SIGKILL-class quiesce (`stopRestartUpgradeUnit`, install_upgrade.go:367) → `RecoverFromFlag` → `resumePostSwap` containers-probe (:6007) → `applyPostSwap` recreating the full set → completed. No injected code runs after t0 in either scenario; the kills are external signals.

---

## §2 The real-path attempt: the PARK state — and why the proof FAILS today

The state a park run needs at a chosen instant: an in_progress row + a service-held forward flag with a dead holder + a boot pass hung inside the boot migrate, repeatable across three consecutive boots. The real-path sequence:

1. **Construct B = A + V_sleep** off the current base — real branch, real per-commit CI images (the STATBUS-118 constructor, doc-020). Already routine: every arc does this.
2. **Install A; `./sb upgrade register` + `schedule` B** — the real operator path. The row is real; the claim gate (service.go:4399) is satisfied by genuinely published images (the image-wait job) — no status forgery.
3. **The daemon claims** (:4433) **and runs `executeUpgrade`**: flag write (:4624), read-only window, maintenance, stops, stopped-DB backup (:4826), `git fetch` (:4835 — checkout deferred, STATBUS-060), binary swap (:4915), flag `Phase=post_swap` (:4941), **exit-42 handoff** (:4953).
4. **The new binary boots**: recovery checkout of B (:1772-1796) puts V_sleep on disk as pending; guard counts attempts=1 and stamps `Step="boot-migrate"` (:5884); **boot-migrate runs V_sleep and hangs** (:1934).
5. **Kill the daemon at the confirmed midpoint** — the gate is the flag's own write-ahead `Step` stamp plus the active `pg_sleep` backend in `pg_stat_activity`. Deterministic, arbitrarily wide window. This exact confirmed-midpoint pattern is run-proven: the OOM arc used it to kill the db (run 28841893851), the mid-migration arcs to kill processes inside the real migration window (run 28837119781); the external SIGKILL gated on `flag.Step` is the park scenario's own committed mechanism.
6. **systemd restarts** → pass 2 hangs identically → kill #2 → pass 3: same-step-twice → **PARK at attempts==3**. Identical arithmetic to the fabricated r19-green run — with a MORE faithful flag (real `backup_path`, real claim, real handoff PID history).

**Why this was believed impossible — the r12 history, honestly.** r12 (STATBUS-044 comment #4) proved: *a daemon restarted onto HEAD with the delta already on disk consumes it at boot* — 9 migrations applied in 6 seconds, version marked completed, upgrade consumed before dispatch. That is a true impossibility **of that construction**: the scenario harness had HEAD's tree checked out *before* any dispatch, so boot-migrate ate the delta. On the arc path the delta belongs to B and arrives **only via the flag-gated recovery checkout after the real handoff** (STATBUS-060, :1772-1796) — the claiming daemon at A has nothing pending at its own boot. The impossibility does not transfer. The pieces that make step 5 deterministic (constructed-B + confirmed-midpoint kill) were proven three days AFTER the park scenario shipped; the fabrication was a reasonable call on 2026-07-04 and is an unnecessary one on 2026-07-08.

**"On cue", precisely.** A regression test needs the state at a chosen instant, every run. Without a synthetic hang, the real boot-migrate window is ~6s on a small DB (r12's measurement) at a probabilistic instant — not on-cue. With V_sleep constructed into B — which the arc framework does through the REAL path — the window is poll-confirmed and arbitrarily wide. Determinism no longer requires fabrication; it requires only the constructed-B lineage the framework already owns.

**Verdict §2: the park-class fabrication does not qualify for the carve-out.** It is a cost/latency convenience (single-VM scenario vs. a CI construct+image-wait arc), and the rule is written on reachability, not cost.

---

## §3 The real-path attempt: the RUNE-WEDGE state — and why the proof HOLDS

The wedge (as lived on rune for 18 days, and as fabricated): in_progress row + service-held post_swap flag with a dead holder + DB/binary/tree already AT target + the container set RUNNING but STALE (a stale-but-serving proxy) + a live upgrade unit + no restore ever run. Three independent legs make this unreachable on cue via the fixed product:

1. **The natural producers are bugs we killed.** Rune's shape was composed by (i) the Apr 24 SDNOTIFY collision aborting the parent after convergence but before the row UPDATE landed (the self-heal canary's stated reason for existing, service.go:6002-6004), and (ii) the step-11 proxy gap that never recreated the proxy on a resume (Bug-2, the drifted note at :5461-5464 — the gap that froze rune's proxy on a stale tag for 18 days). Both are fixed. Reproducing the wedge naturally requires reintroducing a fixed bug into the product under test — which is fabrication of the worst kind: shipping the lie in the binary instead of writing it to disk.
2. **The fixed product cannot COMPOSE the state on any path.** For the flag to exist, the box is mid-pipeline; but every mid-pipeline path has the app set STOPPED (pre-swap step 3, :4773) or already RECREATED AT TARGET (step 11, :5460+). "Flag present + full container set running-stale" is a contradiction on HEAD: no ordering of the shipped pipeline leaves stale containers serving while a forward flag stands. It is not a narrow window — it is an unreachable composition.
3. **Every approximation self-converges within one restart window.** Kill the daemon anywhere near step 11 (the write-ahead `markStep(StepStartServices)` stamp gives seconds of window) and systemd restarts it in RestartSec=30s; the next boot's resume recreates the containers and completes — the canary and `applyPostSwap` exist precisely to converge this shape away (:6007-6067). To make the state PERSIST for `./sb install` to take over, the test must suppress the unit (mask/stop) — which destroys the very thing under test (rune's unit was LIVE; the takeover's SIGKILL-class quiesce of a live unit is the scenario's subject) and is interference indistinguishable from fabrication, only less honest about itself.

**Why construction is the honest substitute:** the shape is REACHABLE IN NATURE (rune lived it — one live firing, STATBUS-047) but its producer is dead by our own deliberate act. A standing regression net for the recovery of a state whose producer we killed can only start from the state itself. Construction writes exactly the state; everything after t0 — detection, quiesce, flock-confirmed death, forward routing, recreation, completion, idempotence coda — is unmodified product code. This scenario is GREEN on a real VM (044 comment #12) with the row assertions (rolled_back_at NULL, completed) as the enforcing trap.

---

## §4 The boundary — what would invalidate or narrow this proof

- **§3 is invalidated if** a future product change makes "flag present + running-stale containers" composable again (e.g. removing the pre-swap stops or step 11's full-set recreation), or if the self-heal convergence is weakened. Either would reopen a natural window — and would itself be a regression against the rune fix.
- **§2 is already the narrowing:** the park-class carve-out should be withdrawn, not defended.
- **STATBUS-145 interaction (the King rules on both; they interact twice):** (i) Under minimal boot-migrate, the delta migrations run at the pipeline step — a REAL killable window reopens exactly where the r12 discovery said it had closed, and kills there are already real-path proven (run 28837119781). The park-at-boot-migrate subject itself DISSOLVES for delta migrations: a mid-delta death has `Phase=resuming` (stamped the instant resumePostSwap commits, service.go:253/6255), and the next pass's observed-state read finds the delta pending → positively Behind → one-shot rollback (145's atomicity flip) — it never accrues the same-step-twice park. The park regime survives only for floor-migrate deaths and post-delta at-target crashes. (ii) The park scenario must therefore be rebuilt when 145 ships REGARDLESS of this ruling. The economical sequence: keep the r19-green fabricated scenario as the interim regression net, and rebuild it ONCE as a real-path arc on 145's new geometry — never delete proof coverage before its replacement is proven.

## The asks

1. **Ratify the narrowed carve-out:** construction permitted only for **dead-producer states** with a written proof of this document's §3 shape (fixed-bug producer + uncomposable on the fixed product + self-converging approximations). Today's sole member: the rune-wedge scenario.
2. **Reclassify the park scenario** as real-path-reachable; schedule its arc rebuild to ride the STATBUS-145 build (one rebuild); keep the fabricated version green until that arc is proven.
3. `fabricate_resume_state` then retains exactly ONE sanctioned caller (rune-wedge) plus the park scenario's interim call, deleted with the 145 rebuild; `fabricate_scheduled_upgrade_row`'s deletion (071 5e) proceeds independently as planned.
