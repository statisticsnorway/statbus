---
id: doc-027
title: >-
  The migration timeline — install → upgrade dispatch → boot-migrate, every step
  with its gate (STATBUS-044/096, for the King)
type: specification
created_date: '2026-07-07 08:46'
tags:
  - upgrade
  - recovery
  - boot-migrate
  - walkthrough
  - STATBUS-044
  - STATBUS-096
---
# The migration timeline — from install to the boot-migrate window

**Question answered** (King, 2026-07-07): *"why do we, at startup, apply migrations blindly? I need a sequence of events here to dig deeper."*

**Short answer first.** Because every upgrade must swap the `./sb` binary, and a Go process cannot hot-swap itself: the upgrade pipeline always ends by exiting so a NEW process — the new binary — takes over (`service.go:4953` `os.Exit(42)` on the service path, `:4959` `syscall.Exec` on the inline install path). The migration delta therefore always lands in the NEXT process's startup window. That window is **gated, not blind**: a persisted flag names the exact upgrade being resumed, a budget guard counts the pass before any migration runs, parked rows skip it entirely, and the only migrations that can be "pending" are those of a tree someone deliberately put there. "At startup" IS the second half of the dispatched upgrade pipeline — not an independent act.

Each numbered step below is one event, with its trigger and the code that runs. Verified against master HEAD 2026-07-07.

## A. Fresh install

1. **Operator runs `install.sh` → `./sb install`.** `install.Detect` probes the 8-state ladder (`cli/internal/install/state.go`); a fresh box (no `.env.config`) routes to the step-table (`cli/cmd/install.go`).
2. **The step-table's DB steps run in order:** "Seed" — restore the published seed dump if available (`install.go:622`, runner `:1729-1753`) — then "Migrations" — `./sb migrate up --verbose` (`install.go:623`, runner `:1756-1759`). **What "pending" means:** `migrate.HasPending` compares `migrations/*.up.sql` on the working tree against the applied-versions table `db.migration` (`install.go:812-818`). On a fresh box: everything newer than the seed.
3. **Terminal:** schema at the installed tree's HEAD; every applied version recorded in `db.migration`. No flag, no `public.upgrade` row involved.

## B. Upgrade dispatch — the OLD binary's half

4. **Candidate registration:** `./sb upgrade check` fetches releases and registers rows (`service.go:4271`), or `./sb upgrade register <version>` (`:4140`).
5. **Scheduling:** `./sb upgrade schedule <version>` → `public.upgrade` row `state='scheduled'` + NOTIFY (`:4189`).
6. **Claim:** the daemon's 30s tick runs `executeScheduled` (`:4373`) — earliest due scheduled row (`:4383-4387`), the images-ready claim gate (`:4399`), then the atomic claim: `state='in_progress'` with a `state='scheduled'` guard so a racing `./sb install` cannot double-claim (`:4433-4435`). The install path dispatches through the same guarded claim (`ExecuteUpgradeInline` `:1556`; `install_upgrade.go:35-36, 57-81`).
7. **Pre-flight (Phase 0, no flag yet):** downgrade / platform / disk / signature checks inside `executeUpgrade` (`:4467`+) — reject cleanly before anything destructive.
8. **FLAG WRITE** (`:4624` `writeUpgradeFlag`): `tmp/upgrade-in-progress.json` + kernel flock. From here a crash is resumable; the flag carries the upgrade id, target commit SHA, phase, and the dying-step fields the budget reads.
9. **Pre-swap destructive steps:** warm-up image pull; read-only window ON (`:4746`); maintenance ON + app/worker/rest stopped (`:4769`+); **DB stopped** (`:4793`); volume snapshot backup (`:4826`); `git fetch` of the target's objects — **no checkout yet** (`:4835`; STATBUS-060: the old binary must never materialize the target's compose/config).
10. **BINARY SWAP:** `replaceBinaryOnDisk` (`:4915`) puts the target `./sb` on disk (old kept as `./sb.old`); flag stamped `Phase=post_swap` (`:4941`).
11. **HANDOFF:** service mode exits 42 (`:4953`; systemd `Restart=always` restarts the unit onto the new binary); inline mode `syscall.Exec`s it (`:4959`). **At this moment ZERO migrations have run**: the DB is stopped, the tree is still the old tree. The old process cannot run them — the migration SQL belongs to the new tree, and the new tree's queries need the new binary.

## C. The NEW binary's boot pass — where migrations actually land

Every step below runs on every daemon start (unit start, crash restart, reboot); the flag-gated steps engage only when a flag is present.

12. **Recovery checkout:** a service-held FORWARD flag (post_swap/resuming) → `git checkout <flag.CommitSHA>` (`service.go:1772-1796`). The working tree is now the target's — its `migrations/` holds exactly the scheduled upgrade's delta. PreSwap flags are gated out (they roll back; a forward checkout would create git/schema skew).
13. **Cheap init:** `./sb config generate` unconditionally (`:1798`); `EnsureDBUp` = `docker compose up -d db` (`:1808`) — revives the DB that step 9 stopped (or a crash killed); connect (`:1812`); advisory lock (`:1819`); LISTEN (`:1844`); `READY=1` (`:1864`) so the heavy work below runs in systemd's ACTIVE phase under WatchdogSec, not the fixed start timeout.
14. **RecoveryBudgetGuard** (`:1918`, definition `:5783-5895`) — the counting gate, BEFORE any migration: engages only for a service-held forward flag with a dead holder. Takes the flock; if the row is PARKED → **skip the boot migrate** (alive-idle); else **increments `recovery_attempts`** (the pass is counted before the migrations so a death inside them self-counts), consults the escalation core — same-step-twice or 3-death budget (`recovery_escalation.go:112-132`) — a terminal verdict **PARKS** (never rolls back from this early guard; a deliberate `./sb install` un-parks into the careful routing that can still roll a genuinely-behind box back); otherwise stamps `Step=boot-migrate` on the flag and continues.
15. **BOOT-MIGRATE** (`:1934`): `./sb migrate up --verbose`, bounded by the 12h ceiling (`watchdog.go:150`, env-overridable `:173-181`, STATBUS-095), covered by an always-ping watchdog ticker (`:1923-1927`). **This is the site that consumes every upgrade's migration delta** — by the time the resume pipeline's own migrate step runs (18 below), it is a no-op.
16. **Failure routing at this site, in order** (`:1938-2018`): TIMEOUT → the orphaned in-container psql backend is reaped (`:1946-1948`), then falls into the branches below. Service-held flag present → **defer to `recoverFromFlag`**, the snapshot-restore owner (STATBUS-017, `:1972-1976`) — never refuse-and-loop on a half-applied upgrade. Flagless + deterministic exit 20 → **one loud actionable report, daemon stays alive-idle** (STATBUS-144, `:1977-2013`). Flagless + transient/unclassified → refuse + exit; systemd restarts (`:2014-2018`).
17. **`recoverFromFlag`** (`:2030`) — the routing brain. PreSwap → one-shot rollback. post_swap → `resumePostSwap` (`:1112-1120`). Resuming → observed-state tri-state (`:1040-1104`): at-target → resume forward; positively-Behind → data-safe rollback; unreadable → one bounded backoff-retry (`:1085`), recurrence after a cleared backoff → rollback (`:1071-1080`).
18. **`resumePostSwap` → `applyPostSwap`:** config-generate → pull → db up → reconnect → migrate (`:5347` — normally a no-op now) → start services → health → maintenance OFF → `state='completed'` + flag removal. Then `completeInProgressUpgrade` / `markCurrentVersionCompleted` / `cleanStaleMaintenance` (`:2036-2046`, `:3366`) reconcile row-only leftovers.

## D. Why the migrations land at boot — and why it is not blind

19. **Why THERE (necessity, not preference):** step 11 always hands off, so the delta must run in the next process. And it must run **before** `recoverFromFlag`: the new binary's ~23 `public.upgrade` queries assume the new schema — rc.63 renamed three columns, and a new binary on an old schema dies with SQLSTATE 42703 at its first recovery query (the rc.65 incident; history in the comment at `service.go:1866-1885`). Boot-migrate is the self-consistency guard: binary and schema must match before the binary can even read what state it is in.
20. **Why not "blind":** (a) "pending" at that moment is never arbitrary — it is exactly the delta of a tree a deliberate act put there: the flag's target checkout (12), install.sh's checkout, or a deploy push; migration files do not appear on their own. (b) The window is counted and bounded by the guard (14): budget, same-step-twice, parked-skip. (c) Its failures are classified by the exit-code contract (`migrate/exit_codes.go:39-44`) and routed per 16, with the snapshot-restore path owning the flagged case. (d) It is time-bounded (12h ceiling) and watchdog-covered.
21. **The one deliberately-open arm:** a FLAGLESS boot with pending migrations applies them silently when they succeed — the rc.65 self-repair, and the path a fresh `./sb install`-repaired box relies on. The alternative (require operator confirmation) contradicts the deployment doctrine: the sole operator action is install.sh, and a box that waits for confirmation is a wedged box. If the King wants an explicit-intent gate on this flagless arm, that is a rulable design change; the trade is autonomy vs. explicitness — and it is the only arm where "apply at startup" is not the direct continuation of a deliberately dispatched upgrade.
