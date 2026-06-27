---
id: doc-019
title: Recovery decision model — the complete picture
type: specification
created_date: '2026-06-27 06:24'
tags:
  - upgrade
  - recovery
  - model
  - statbus-107
  - statbus-109
  - statbus-110
---
# Recovery decision model — the complete picture

Status: **target model, ratified by the King 2026-06-27.** Enabled by the read-only window (doc-018 / STATBUS-110) + error classification (STATBUS-109). This is what the upgrade/recovery code, diagrams, and glossary should converge on.

## Principle
*You cannot go wrong without intent; with intent you're allowed. Don't act on what you can't name.* Recovery is **autonomous in every case except two** principled human stops.

## The model, end to end

### 1. Read the recorded state (the on-disk flag)
- **no flag** → nothing to recover; normal startup. [auto]
- **corrupt / unreadable flag** → discard-and-log; normal startup. [auto]
- **install-holder flag** (a crashed install, not an upgrade) → clear it; no DB work. [auto]
- **unrecognized phase value** → STOP for a human (we can't read our own recorded state). [HUMAN — "unknown"]
- **recognized phase** (pre-swap / post-swap) → continue.

### 2. Decide direction (the read-only window makes any rollback data-safe)
- **pre-swap** — never booted the new sb → roll back trivially (restart old; nothing changed). [auto]
- **post-swap, at-target** — new binary + migrations in place → continue forward (finish remaining steps). [auto]
- **post-swap, behind** — migrations didn't run / binary not at target (deterministic) → roll back. [auto]
- **post-swap, can't read position** — DB unreachable / target commit not in clone → an *intermittent* error → §3.

### 3. When a step fails — classify the error, then act (the no-spin rule)
- **Intermittent** (recognized transient: DB blip, connection reset, container not ready) → **retry with backoff** (1s→2s→4s→8s→16s→30s cap; ~the DB-restart window; in-process, heartbeating). Resolves → continue. Exhausts → no longer transient → **roll back**.
- **Persistent** (recognized deterministic: "relation already exists", a constraint violation) → **roll back**, zero retries (retry can't change a deterministic outcome).
- **Unknown** (unrecognized error) → **STOP for a human.** Don't retry (might spin); don't roll back (might be wrong for an error we don't understand). [HUMAN — "unknown"]

### 4. Terminals
- **completed** — forward succeeded. [auto]
- **rolled_back** — a rollback succeeded; healthy on old; operator re-schedules. [auto]
- **failed** — a rollback was chosen but its *restore itself* broke (rsync/disk); box can't reach runnable. [HUMAN — "restore-broke"]
- (a §1/§3 "unknown" stop → row stays in_progress + loud, waiting for the human.) [HUMAN — "unknown"]

## The shape
Autonomous everywhere **except two human stops**, both principled and rare:
1. **unknown** — we can't *read* the situation (an unrecognized phase **or** an unrecognized error). One rule: don't act on what we can't name.
2. **failed** — our recovery *action* (the restore) itself broke. Hands-on regardless.

## What enables it
- **Read-only window** (doc-018 / STATBUS-110): blocks *accidental* external writes during the danger phase (DB-back-up-for-migrations → resolve) → a rollback can never lose data → rollback is the universal safe fallback → "never restore on a guess" (STATBUS-039) retires; the can't-verify→hold→human spin dissolves; the at-target-spin (the 18-day rune hang) is gone. Accident-guard, not a lock (deliberate override allowed — the operator's escape hatch).
- **Error classification** (STATBUS-109): two curated lists — **known-intermittent** (→ backoff-retry) and **known-persistent** (→ roll back). Everything else is **unknown by default → stop.** Safe-by-default; no blind retry counts; no spin. Retries run in-process (not exit→systemd-restart), so they don't burn the restart budget.

## Implementation work this implies
- **STATBUS-110**: build the read-only toggle (ALTER DATABASE default_transaction_read_only; ON before the DB stop, OFF at the 4 verified terminals 4211/4227/4828/5684; upgrade session self-exempts per (re)connect). Arc-tested (STATBUS-071). doc-018.
- **STATBUS-109**: the in-process backoff + the two curated error lists; default unknown→stop.
- **STATBUS-107**: lock the recovery slugs + de-jargon the 3 diagrams (draw corrupt-flag; promote git-unknown + unrecognized-phase from prose to branches; split the single failed/human blob into "unknown" vs "restore-broke").
- **Parked (arc-gated)**: serialization/clean-restart (the unrecognized-phase cross-version case).
