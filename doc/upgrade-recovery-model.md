# Recovery decision model — the complete picture

*Canonical source of truth for the upgrade/recovery **decision logic**. Lifted into `doc/` from the backlog (2026-06-29) so it sits with its siblings — `doc/upgrade-timeline.md` (when things happen), `doc/upgrade-vocabulary.md` (the names), and `doc/diagrams/` (the pictures). The glossary names these concepts, the diagrams draw them, the code implements them; this is where they reconcile.*

Status: **shipped model** (ratified as target 2026-06-27; run-proven through the install-recovery arc campaign, culminating in the health-park arc's full green, wave 10, run 29171998401). Enabled by the read-only window (read-only-upgrade-window design · STATBUS-110) + error classification (STATBUS-109). **The window formally supersedes STATBUS-039's "never restore on a guess" (STATBUS-110 AC#3, 2026-07-12)** — see the supersession statement in `doc/read-only-upgrade-window.md` §"Effect on recovery".

## Principle
*You cannot go wrong without intent; with intent you're allowed. Don't act on what you can't name.* Recovery is **autonomous in every case except two** principled human stops.

## The model, end to end

### 1. Read the recorded state (the `upgrade-in-progress` marker)
- **no marker** → nothing to recover; normal startup. [auto]
- **corrupt / unreadable marker** → discard-and-log; normal startup. [auto]
- **install-holder marker** (a crashed install, not an upgrade) → clear it; no DB work. [auto]
- **unrecognized phase value** → STOP for a human (we can't read our own recorded state). [HUMAN — "unknown"]
- **recognized phase** (pre-swap / post-swap) → continue.

### 2. Decide direction (the read-only window makes any rollback data-safe)
- **pre-swap** — never booted the new sb → roll back trivially (restart old; nothing changed). [auto]
- **post-swap, at-target** — new binary + migrations in place → continue forward (finish remaining steps). [auto]
- **post-swap, behind** — migrations didn't run / binary not at target (deterministic) → roll back. [auto]
- **post-swap, can't read position** — DB unreachable / target commit not in clone → an *intermittent* error → §3.

### 3. When a step fails — classify the error, then act (the no-spin rule)
- **Intermittent** (recognized transient) → **`backoff-retry`**, in-process + heartbeating; resolves → continue, exhausts → no longer transient → **roll back**. One strategy, two cases, parameters + failure-detection tuned per probe:
  - `db-unreachable` — probe = connect + trivial query; one try fails on a wall-clock **5s** (a quick check, never a transfer); gap 1s→2s→4s→8s→16s→30s cap; **~5 min** budget.
  - `commit-not-fetched` — probe = one `git fetch`; one try fails on a **stall** (no progress ~60s, git low-speed) — **never a deadline**, so a healthy slow transfer is never cancelled; gap 10s→30s→60s; **~15 min** overall budget.
  - Health checks (DB-health / REST-ready / health-RPC) already self-wait → rollback on exhaustion; **not** on this path. *(Values build/test-reconcilable; the shape is fixed.)*
- **Persistent** (recognized deterministic: "relation already exists", a constraint violation) → zero retries (retry can't change a deterministic outcome), then **branch on observed position** (STATBUS-046, shipped): positively **behind** the target → **roll back** (data-safe by the window); **at-or-past target, or unverifiable** → **PARK** (`recovery_parked_at` set, row stays `in_progress`, siren once, unit alive-idle — rolling back an at-target box could strand post-maintenance-off integrator writes, and retrying a deterministic failure cannot help). A parked box waits for the fix: deliberate un-park (`./sb install` / re-schedule), or **displacement-at-claim** (STATBUS-159 — a newly scheduled release's claim atomically moves the parked row to `superseded`, park reason preserved, and proceeds).
- **Unknown** (unrecognized error) → **STOP for a human.** Don't retry (might spin); don't roll back (might be wrong for an error we don't understand). Mechanically: stays in_progress + loud; the existing systemd-StartLimit exit-restart backstop surfaces it. [HUMAN — "unknown"]

**Composition with the existing backstop:** the in-process `backoff-retry` sits *in front of* the systemd-StartLimit exit-restart (today these transients exit→systemd immediately; the new in-process retry is genuinely new). A known transient that **exhausts → rolls back** here (the case-9 "stuck" spin stays dissolved); the systemd backstop remains *only* for the **unknown** stop. An exhausted *known* transient must never fall through to the old restart-until-stuck loop.

### 4. Terminals
- **completed** — forward succeeded. [auto]
- **rolled_back** — a rollback succeeded; healthy on old. [auto] *Operator forecast (tailored to cause): a **hard / persistent-error** rollback → report it (log retained) + try a **later release** when available (the same version repeats the failure — don't re-schedule it); an **exhausted-transient** rollback → retry when the environment is healthy (same version is fine).*
- **failed** — a rollback was chosen but its *restore itself* broke (rsync/disk); box can't reach runnable. [HUMAN — "restore-broke"] *Shipped (STATBUS-111, closed 2026-07-12): the install ladder re-attempts the restore — a `failed` row with a retained `backup_path` is re-attemptable, **human-gated via `./sb install`** (never the auto systemd service — restore-broke stays a human stop, no auto-thrash); the operator sees a **legend** (`./sb install` headline + state-relevant commands) + a **forecast** (detected state + planned action). Two row classes: the pair-terminal re-attempt completes; an abort-row with corrupt git refuses actionably. Arc-proof obligation tracked on STATBUS-071's coverage map (restore-broke-reattempt row).*
- **parked** — not a row terminal but a held state (`in_progress` + `recovery_parked_at`, STATBUS-046/154): a deterministic at-target failure waiting for its fix. Alive-idle, sirened once, skipped by every automatic resume; leaves only by deliberate un-park or displacement-at-claim (STATBUS-159). Every state/park write is audited in `public.upgrade_state_log` (STATBUS-154). [auto-hold — operator acts at leisure, box never crash-loops]
- (a §1/§3 "unknown" stop → row stays in_progress + loud, waiting for the human.) [HUMAN — "unknown"]

## The shape
Autonomous everywhere **except two human stops**, both principled and rare:
1. **unknown** — we can't *read* the situation (an unrecognized phase **or** an unrecognized error). One rule: don't act on what we can't name.
2. **failed** — our recovery *action* (the restore) itself broke. Hands-on regardless.

## What enables it
- **Read-only window** (read-only-upgrade-window design · STATBUS-110): blocks *accidental* external writes during the danger phase (DB-back-up-for-migrations → resolve) → a rollback can never lose data → rollback is the universal safe fallback → "never restore on a guess" (STATBUS-039) retires; the can't-verify→hold→human spin dissolves; the at-target-spin (the 18-day rune hang) is gone. Accident-guard, not a lock (deliberate override allowed — the operator's escape hatch).
- **Error classification** (STATBUS-109): two curated lists — **known-intermittent** (→ backoff-retry) and **known-persistent** (→ roll back). Everything else is **unknown by default → stop.** Safe-by-default; no blind retry counts; no spin. Retries run in-process (not exit→systemd-restart), so they don't burn the restart budget.

## Implementation status (re-verified 2026-07-12)
- **STATBUS-110** — SHIPPED: `setDatabaseReadOnly` (exec.go:341-380), ON before the snapshot, OFF at every terminal except the deliberate ABORT hold; per-session self-exemptions incl. STATBUS-154's `terminalUpdate` sessions. Current sites + the exempt-writer roster: `doc/read-only-upgrade-window.md` (Critical files). Crash-freeze rider on `postswap-mid-tx-kill-arc` (AC#2) awaits its run.
- **STATBUS-109** — SHIPPED: in-process backoff + the two curated error lists; default unknown→stop.
- **STATBUS-107** — DONE: recovery slugs locked (`doc/upgrade-vocabulary.md`); diagrams de-jargoned.
- **STATBUS-111** — SHIPPED + CLOSED: install-re-attempts-restore + operator legend/forecast; arc proof on 071's map.
- **Park machinery** — SHIPPED beyond this doc's original scope: the deterministic-failure park (046), teardown-immune terminals + parked⇒in_progress constraint + state-write audit log (154), displacement-at-claim (159), terminal non-resurrection (160). Run-proven end-to-end (health-park arc wave 10).
