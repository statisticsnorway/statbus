---
id: doc-022
title: In-process backoff-retry for recovery — detailed design (STATBUS-109)
type: specification
created_date: '2026-07-02 17:55'
tags:
  - upgrade
  - recovery
  - reliability
  - statbus-109
---
# In-process backoff-retry for recovery — detailed design (STATBUS-109)

*Companion to `doc/upgrade-recovery-model.md` (the ratified model), `doc/read-only-upgrade-window.md` (STATBUS-110, the data-safety foundation this composes with), and `doc/upgrade-vocabulary.md` §"Recovery — when a step fails" (the ratified vocabulary this implements). Ticket: STATBUS-109. All code citations verified first-hand against master HEAD 2026-07-02. Design only — engineer builds, arcs (STATBUS-071) are the only oracle.*

---

## Context

Today, when recovery cannot read its position because the **DB is transiently unreachable** (db mid-restart, resolves in seconds), the process **exits** and leans on systemd restart as its retry. King's framing (2026-06-24): *"To exit for a transient error creates noise."* The exit-restart burns the systemd StartLimit budget (10/600s) and risks a false unit-failure for a brief DB blip.

The ratified target model (`doc/upgrade-recovery-model.md`, King 2026-06-27) replaces exit-on-transient with **classify-then-act**:
- **intermittent** (recognised transient) → `backoff-retry` **in-process**; resolves → continue, exhausts → **roll back**;
- **persistent** (recognised deterministic) → roll back, zero retries;
- **unknown** (unrecognised) → **stop for a human** (stay `in_progress`, loud; the existing systemd-StartLimit backstop surfaces it).

This composes with **STATBUS-110** (read-only window, committed `3ff119b8a`): because accidental external writes are blocked across the danger phase, an **exhausted-transient rollback loses no data** — which is what lets recovery roll back autonomously instead of holding for a human. 110 makes rollback safe; 109 makes recovery retry-then-rollback instead of exit-spin. Together they dissolve the old *can't-verify → hold → human* branch.

**Safe-by-default is the invariant:** we retry only what we can *name* as transient, roll back only what we can *name* as deterministic, and **stop on anything we can't name**. No blind retry counts. The load-bearing work is curating the two lists — not the loop.

---

## The single insertion point (grounded)

The position-read that produces `GroundTruthUnknown` lives in **one** recovery branch:

- `recoverFromFlag`, **`FlagPhaseResuming` branch — `service.go:867–892`**. Today:
  - `gt, gtReason := d.verifyUpgradeGroundTruthEx(ctx, flag.CommitSHA)` (`:868`)
  - `gt != GroundTruthBehind` (i.e. **AtTarget OR Unknown**) → **forward** via `resumePostSwap` (`:869–880`) — this is the STATBUS-039 *forward-on-a-guess* conservatism.
  - `gt == GroundTruthBehind` → `recoveryRollback` (`:882–891`).

`GroundTruthUnknown` has exactly **two sub-causes**, both surfaced inside `verifyUpgradeGroundTruthEx` (`service.go:2133–2170`):
1. **db-unreachable** — the `db.migration` max-version query fails (`:2144–2153`, returns `GroundTruthUnknown`).
2. **commit-not-fetched** — `verifyBinaryGroundTruth` (`service.go:2052–2077`) fails the `git merge-base --is-ancestor` (`:2060`) and the `git cat-file -e <sha>^{commit}` probe (`:2070`) confirms the target commit is **absent from the local clone** (shallow/pruned) → `GroundTruthUnknown` (`:2071`). A *different* merge-base failure (not exit-1, commit present) → `GroundTruthUnknown` (`:2075`) is **unrecognised**.

The other recovery branches need no change: `FlagPhasePostSwap` (`:900`) resumes forward directly (its DB ops use the existing `waitForDBHealth`/`waitForRestReady` self-waits — explicitly *not* on this path per the vocabulary); `FlagPhasePreSwap` (`:952`) rolls back with no DB read; the unrecognised-phase tail (`:981–983`) is already the `unknown` human-stop.

---

## Recommended approach

### 1. Type the Unknown cause (reach-for-types, not string-matching)

`verifyUpgradeGroundTruthEx` collapses both sub-causes into `GroundTruthUnknown` + a free-text `reason`. Classifying by re-parsing that string is brittle. Instead, **carry a typed cause**.

Add:

```go
type UnknownCause int
const (
    CauseNone UnknownCause = iota    // not an Unknown verdict
    CauseDBUnreachable               // known-intermittent → backoff-retry (db probe)
    CauseCommitNotFetched            // known-intermittent → backoff-retry (fetch probe)
    CauseUnrecognized                // unknown-error → stop for a human
)
```

Extend the ground-truth verdict to return it (either a third return value, or fold `GroundTruth`+`UnknownCause` into a small struct — engineer's call; a struct keeps the tri-state callers at `:2107`/`:869` clean). Set it at the three sites:
- `service.go:2151` (DB query failed) → `CauseDBUnreachable`
- `service.go:2071` (cat-file: commit absent) → `CauseCommitNotFetched`
- `service.go:2075` (merge-base failed, commit present) → `CauseUnrecognized`

`verifyUpgradeGroundTruth` (the 2-state wrapper, `:2106–2109`) and its read-only callers are unaffected — they only read `gt == GroundTruthAtTarget`.

This *is* the known-intermittent list at the position-read surface: the enum **is** the curated list. Nothing reaches `backoff-retry` unless it was explicitly classified here.

### 2. `backoffRetry` — one strategy, per-case parameters (the loop)

A single helper implements the vocabulary's loop shape; only the **probe** and the **per-try failure detection** differ per case.

```go
type retrySpec struct {
    name        string            // "db-unreachable" | "commit-not-fetched"
    gaps        []time.Duration   // backoff sequence, last value is the cap
    budget      time.Duration     // overall ceiling → roll-back on exhaust
    probe       func(ctx) error   // one attempt; returns nil on success
}

// returns nil (cleared → caller re-reads ground truth) or ErrRetryExhausted.
func (d *Service) backoffRetry(ctx context.Context, spec retrySpec) error
```

Loop, per iteration:
1. **`emitHeartbeat(d.projDir)`** (`watchdog.go:217`) — **CRITICAL**: `recoverFromFlag` runs at `service.go:1712`, *before* the main-loop heartbeat ticker starts (`:1759`). During recovery nothing else feeds systemd `WatchdogSec=120s`, so the loop must self-heartbeat every iteration or the daemon is SIGKILLed mid-wait. Gaps ≤30s and the 5s db probe stay well inside 120s; the fetch probe heartbeats continuously via `onAdvance` (below).
2. run `spec.probe(ctx)` → **success → return nil** (caller re-runs the ground-truth check and dispatches the fresh, now-resolved verdict).
3. failure → if elapsed ≥ `spec.budget` → **return `ErrRetryExhausted`**; else sleep the next gap and loop.

Per-case parameters (ratified shape; exact numbers reconcile at build against the arcs):

| case | probe | one-try failure | gaps | budget |
|---|---|---|---|---|
| `db-unreachable` | `d.reconnect(ctx)` (= connect + re-acquire the advisory lock + re-LISTEN) then a trivial `SELECT 1` | wall-clock **5s** (`context.WithTimeout`) — a quick check, never a transfer | 1s→2s→4s→8s→16s→**30s cap** | **≈5 min** (~12 tries) |
| `commit-not-fetched` | `d.fetchWithStallDetection(ctx, flag.CommitSHA)` | a **stall** — no output progress ~60s (see §3); **never** a wall-clock deadline | 10s→30s→**60s cap** | **≈15 min** |

**`retryBackoff` stays — it is NOT dead (correction 2026-07-02, verified first-hand vs HEAD).** `retryBackoff(attempt int)` at `service.go:81–95` (100ms/500ms/1s) has **6 live callers** — bounded DB-write-retry loops at `service.go:2445`, `:2546`, `:4091`, `:5038`, `:5693`, `:5708` — plus a structural test asserting its presence in `writeRollbackTerminal` (`rollback_terminal_write_test.go:89`). It keeps its existing job. The new `backoffRetry` is a **distinct, independent** helper (a full probe/budget loop, not a sleep-duration function) — build it as a sibling; do **not** touch `retryBackoff`, and the new gap sequences live as `retrySpec.gaps` data. *(An earlier draft said "zero call sites / delete" — inherited from a stale grounding note and refuted here.)*

**db-unreachable probe uses `reconnect()`, NOT bare `connect()` (correction 2026-07-02, engineer-caught + architect-confirmed first-hand).** `reconnect()` = `connect()` **plus** `acquireAdvisoryLock` (the upgrade-actor mutex) **plus** re-`LISTEN`. The old exit-restart path re-took the advisory lock + re-LISTENed on the fresh process (`Run()` → `acquireAdvisoryLock`), so the in-process retry must restore that same session invariant — bare `connect()` would leave the retry running without the actor mutex or the NOTIFY channel. On success `d.queryConn` is live, holding the lock, and write-enabled via the STATBUS-110 read-only self-exempt applied inside `connect()` (`SET default_transaction_read_only = off` for queryConn/listenConn) — so the immediate ground-truth re-read and any forward write run correctly. *(An earlier draft said "reuses connect()"; the engineer's `reconnect()` is the correct, more-complete choice.)*

### 3. `fetchWithStallDetection` — the commit-not-fetched probe (greenfield)

The forward fetch (`service.go:4362`) today is:

```go
runCommandToLog(projDir, 5*time.Minute, progress.File(), "git", nil, "git", "fetch", "origin", commitSHA)
```

— a **5-minute wall-clock deadline** with **no stall detection**. That is exactly the *"a deadline cancels a healthy slow transfer"* bug the vocabulary forbids (King's correction 2026-06-24).

`runCommandToLog` (`exec.go:147–164`) already exposes the hook we need: its `onAdvance func()` callback (currently `nil` at `:4362`) fires on **every line** of output via `NewPrefixWriter` (`:152–153`). Build the stall-detector on top:

```go
// pseudocode
func (d *Service) fetchWithStallDetection(ctx, commitSHA) error {
    ctx, cancel := context.WithCancel(ctx)          // NOT WithTimeout — no deadline
    defer cancel()
    lastProgress := atomic-now
    onAdvance := func() { lastProgress.store(now); emitHeartbeat(d.projDir) }
    go func() {                                     // stall watchdog
        for tick every 5s:
            if now - lastProgress.load() > 60s { cancel(); return }  // no-progress → abort this try
    }()
    return runCommandToLogCtx(ctx, projDir, progress.File(), "git", onAdvance,
        "git", "fetch", "origin", commitSHA)         // ctx-cancellable variant, no fixed timeout
}
```

Notes:
- A small refactor of `runCommandToLog` to accept an external `ctx` (instead of building its own `WithTimeout`) is needed; keep the existing signature as a thin wrapper for other callers.
- `onAdvance` doubles as the heartbeat feed — a transferring fetch keeps the systemd watchdog alive; a genuine stall stops both (and 60s < 120s, so the stall abort fires first).
- **The per-try abort is a stall, not a deadline** — a healthy slow transfer runs however long it legitimately takes; only *no progress for ~60s* aborts a try, and the ~15-min overall budget bounds a truly-down network.

**Companion fix (recommended, see Open Question 1):** point the forward fetch at `:4362` at the same helper. It removes the wall-clock-cancels-healthy-transfer bug on the forward path too, for a one-call-site swap.

### 4. Wire the dispatch + exhaustion handoff (`recoverFromFlag` Resuming branch)

Replace the `gt != GroundTruthBehind → forward` logic (`:869–880`) with an explicit tri-state + Unknown-classification dispatch:

```
gt, cause, reason := verifyUpgradeGroundTruthEx(ctx, flag.CommitSHA)
switch {
case gt == AtTarget:   → resumePostSwap(ctx, flag)                 // forward (unchanged)
case gt == Behind:     → recoveryRollback(...)                     // rollback (unchanged)
case gt == Unknown:
    switch cause {
    case CauseDBUnreachable:
        if backoffRetry(ctx, dbSpec) == nil { re-read + re-dispatch }   // cleared
        else recoveryRollback(...)                                       // exhausted → safe rollback (110)
    case CauseCommitNotFetched:
        if backoffRetry(ctx, fetchSpec) == nil { re-read + re-dispatch } // acquired
        else recoveryRollback(...)                                       // exhausted → safe rollback
    case CauseUnrecognized:
        return fmt.Errorf(...)   // unknown-error → :1712 exit → systemd StartLimit backstop (human stop)
    }
}
```

Key points:
- **"re-read + re-dispatch"**: after a cleared retry, re-run `verifyUpgradeGroundTruthEx` and act on the *resolved* verdict (AtTarget→forward, Behind→rollback). A tiny bounded recursion or a `for` around the switch; guard against re-entering `backoff-retry` for the *same* cause twice (one budget per recovery pass — if it cleared then re-fails, treat as exhausted → rollback).
- **Exhaustion handoff = `recoveryRollback`** (`service.go:2257`), the same rollback entry the Behind and PreSwap branches use (`:888`, `:961`). It is **data-safe by construction** now (110's read-only window). An exhausted known transient **never** falls through to the old exit→systemd restart spin — that dissolved case-9 stays dissolved.
- **`CauseUnrecognized` → the existing exit path** at `:1712–1713` (return non-nil → systemd StartLimit backstop). This is the *one* remaining human-stop mechanism, unchanged. **Behaviour change to flag:** today this unrecognised sub-case goes *forward* (STATBUS-039 conservatism); the new model makes it **stop**. See Open Question 2.
- **Composition with the backstop:** the in-process `backoff-retry` sits *in front of* systemd. Reached-systemd now means only `unknown` — never a known transient.

### 5. The known-persistent list (AC#3, the smaller half)

The position-read surface produces no *deterministic* errors (a read-only `SELECT MAX(version)` doesn't hit `"relation already exists"`). Persistent errors arise on the **forward step** — `migrate up` inside `resumePostSwap`/`applyPostSwap`. That path **already rolls back on failure** today, so the persistent list's job here is to make the classification *explicit and safe-by-default*, not to add a new action:

- Add `classifyStepError(err) → {Persistent | Unknown}` for forward-step failures: a small curated matcher over PG **SQLSTATE** classes / substrings (`already exists`, `violates ... constraint`, and the known deterministic-migration signatures). A match → `persistent-error` → roll back, zero retries (current behaviour, now named). **No match → `unknown-error`** — the default — which under this model means *do not silently forward*: surface it as the `unknown` stop rather than swallowing it.
- This keeps the two curated lists concrete and co-located: **intermittent** = the `UnknownCause` enum (§1); **persistent** = `classifyStepError`'s match set. Everything else is unknown-by-default.

Scope note: the *new machinery* (backoff loop + fetch stall-detector) is entirely in the position-read path (AC#1, AC#2, AC#4). The persistent-list wiring is a thin classification over the existing migrate-failure→rollback path. Keeping it thin is deliberate — over-building a retry story around the subprocess migrate is out of scope and unnecessary (migrate failures are deterministic).

---

## Critical files (paths + current lines)

| file:line | what | change |
|---|---|---|
| `service.go:867–892` | `recoverFromFlag` Resuming branch | the dispatch rewrite (§4) — the one insertion point |
| `service.go:2133–2170` | `verifyUpgradeGroundTruthEx` | return typed `UnknownCause` (§1); set at `:2151` |
| `service.go:2052–2077` | `verifyBinaryGroundTruth` | set `UnknownCause` at `:2071` (CommitNotFetched) / `:2075` (Unrecognized) |
| `service.go:81–95` | `retryBackoff` (LIVE — 6 callers + structural test) | leave as-is; build `backoffRetry` as a new independent sibling (§2) |
| `service.go:4362` | forward `git fetch` (5-min wall-clock) | recommend swap to `fetchWithStallDetection` (§3, OQ1) |
| `service.go:2783` | `connect()` (self-exempt `:2960` queryConn / `:2965` listenConn) | reused as the db-unreachable probe (§2) |
| `service.go:2257` | `recoveryRollback` | the exhaustion handoff (§4) |
| `service.go:1712` / `:1709` comment | `recoverFromFlag` call + StartLimit exit | the `unknown`-only backstop (§4) |
| `service.go:1759` | main-loop heartbeat ticker start | proves the loop must self-heartbeat (§2 step 1) |
| `exec.go:147–164` | `runCommandToLog` + `onAdvance` | ctx-cancellable variant + stall watchdog (§3) |
| `watchdog.go:217` | `emitHeartbeat(projDir)` | called every backoff iteration (§2) |
| new: `retrySpec` + `backoffRetry` + `fetchWithStallDetection` | the strategy | §2, §3 |

---

## Verification (install-recovery arcs, STATBUS-071 — the only oracle)

- **Arc A — db-unreachable clears:** kill the DB transiently mid-recovery (Resuming phase); DB returns within budget → recovery re-reads ground truth → forwards/rolls-back on the *true* verdict; **no process exit**; log shows `backoff-retry` on `db-unreachable`.
- **Arc B — db-unreachable exhausts:** DB never returns within ~5 min → **roll-back** (data-safe via 110), row `rolled_back`; **not** an exit→StartLimit spin.
- **Arc C — commit-not-fetched:** shallow clone missing the target commit → `fetchWithStallDetection` acquires it → forward. Plus a **stall variant** (fetch produces no progress) → exhausts → roll-back. *(Defensive edge — SSB clones are complete — but AC#2 requires it.)*
- **Arc D — unknown → stop:** an unrecognised position-read error (`CauseUnrecognized`) → row stays `in_progress`, loud → systemd StartLimit surfaces it (unchanged mechanism).
- **Watchdog:** confirm a full ~5-min db-unreachable backoff does **not** trip `WatchdogSec=120s` (heartbeat each iteration).
- **Unit tests:** `UnknownCause` set correctly at each site; `backoffRetry` gap sequence + budget math; `fetchWithStallDetection` aborts on no-progress but **not** on a healthy slow transfer; `classifyStepError` match set (persistent vs unknown default).

---

## Open questions (genuine — for the King to ratify)

1. **Fold the forward-fetch fix (`:4362`) into 109, or split it?** The forward `git fetch` has the same wall-clock-deadline-cancels-a-healthy-transfer bug and the same helper fixes it in one call-site swap. **Recommend fold** — leaving a known bug next to its fix violates "never defer known bugs," and `fetchWithStallDetection` is built here anyway. Decision criterion: does folding it demand forward-path arc coverage beyond what STATBUS-071 already exercises on the checkout step? If yes and that coverage is costly, split to a one-line follow-on ticket. I would ship the fold.

2. **`forward-on-unknown` → `stop-on-unknown` is a live behaviour flip.** The Resuming branch today goes *forward* on an unrecognised unverifiable position (the STATBUS-039 conservatism: "never restore on a guess" ⇒ prefer forward). The ratified model makes an unrecognised error a **human stop**. This is correct per `doc/upgrade-recovery-model.md` §3 and is safe *because* 110 landed — but it is safety-critical and flips a live branch, so it deserves an explicit nod rather than sliding in under "backoff-retry." (The two *recognised* transients no longer forward-on-a-guess at all — they retry then roll back.)
