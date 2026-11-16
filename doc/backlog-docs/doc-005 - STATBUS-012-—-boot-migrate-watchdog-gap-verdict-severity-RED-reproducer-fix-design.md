---
id: doc-005
title: >-
  STATBUS-012 — boot-migrate watchdog gap: verdict, severity, RED reproducer,
  fix design
type: specification
created_date: '2026-06-11 10:42'
tags:
  - install-recovery
  - upgrade
  - recovery
  - product
  - architect-plan
---
# STATBUS-012 — boot-migrate watchdog gap: verdict, severity, RED reproducer, fix design

**Architect (Fable), 2026-06-11. Adversarial verification of the foreman's trace + design for the fix. Product code is King-gated — this is design only, no product edits.**

---

## Verdict: CONFIRMED — and severity is materially WORSE than the board states

The foreman's claim (boot-migrate at `cli/internal/upgrade/service.go:1644` runs with no WATCHDOG=1 source and is watchdog-killed past 120s) is **correct**. I tried to break it four ways; all four refutation avenues closed with code evidence:

| Refutation attempt | Result | Evidence |
|---|---|---|
| "An ambient heartbeat goroutine pings during boot-migrate" | **No.** The only production `emitHeartbeat` callers are `ProgressLog.Write` (progress.go:251) and the main-loop idle tick (service.go:1753). The idle `heartbeatTicker` is *created* at :1736 — **after** boot-migrate (:1644) — and is a select-case on the main goroutine, which is parked inside `cmd.Run()` during boot-migrate anyway. By design (watchdog.go:49-90, task #42): no background pinger exists, precisely so a hung main goroutine is caught. | service.go:1736-1753, watchdog.go:73-80 |
| "runCommandToLog / PrefixWriter pings per output line regardless of args" | **No.** PrefixWriter (prefix_writer.go:37-53) only fires `onLine` if non-nil and only writes to `dst`. At :1644 `onAdvance=nil`, `logWriter=io.Discard`. Per-line output reaches the journal (MultiWriter → os.Stdout) but no heartbeat mechanism. | exec.go:144-161, prefix_writer.go:45-47 |
| "The `sb migrate up` child pings WATCHDOG=1 itself" | **No, twice over.** (1) `cli/internal/migrate/` contains no sdNotify/NOTIFY_SOCKET code — migrate.go:789's comment describes the *parent-side* PrefixWriter in the protected applyPostSwap path. (2) Even if it pinged: no `NotifyAccess=` is set anywhere (ops/, cli/, test/), so Type=notify defaults to `NotifyAccess=main` — systemd drops datagrams from non-main PIDs. | migrate.go:784-793, ops/statbus-upgrade.service (no NotifyAccess line) |
| "The 30s idle-tick in the unit comment covers :1644" | **No.** The unit comment (ops/statbus-upgrade.service:52-57) describes the main-loop ticker — which doesn't exist yet at :1644. The watchdog **arms at READY=1** (:1621), 23 lines before boot-migrate starts. Effective budget for the entire boot-migrate: ~120s. | service.go:1621→1644→1736 ordering; resume_start_phase_test.go asserts this order |

**Comment drift confirmed:** service.go:1637-1641 claims "a long-but-advancing migration survives (it emits per-migration progress)" — the author believed per-migration output feeds the watchdog; nothing wires it. The unit file (:83-104) makes the same false assumption.

## Severity: boot-migrate is the DEFAULT migration executor for every upgrade, not a rare guard

This is the part the board undersells. Step 6b of executeUpgrade (service.go:3560-3574) **ALWAYS hands off to a new process** after binary procurement — "every upgrade exercises the path", tagged and edge alike: checkout (:3517-3522) → procure binary (:3579-3585) → stamp PostSwap flag (:3606) → `os.Exit(42)` (:3618, service) / `syscall.Exec` (:3624, inline).

So on **every** service-path upgrade, the fresh process boots with repo-at-new-version + schema-at-old, and **boot-migrate at :1644 consumes the entire migration delta** (it runs BEFORE `recoverFromFlag` at :1689 — the order is even pinned by `resume_start_phase_test.go`). The elaborately protected applyPostSwap migrate (:3949-3953: 30-min timeout, deferGating always-ping, #14 orphan-terminate, postSwapFailure rollback) then runs against an already-migrated schema — **a structural no-op for migrations in the normal flow**. STATBUS-013's diagnosis ("boot-migrate consumes the delta before the resume-migrate") already proved this empirically on the inline path; the code shows it's equally true on the service path.

**Consequence:** the production migration budget is ~120s (WatchdogSec), not the designed 30 minutes. The codebase itself concedes single migrations legitimately run "silent for minutes on one big DDL" (watchdog.go:131-133, service.go:3922-3927) — that is the admission that >120s single migrations are *expected*. On Norway's 32GB:

- **Delta of many small migrations:** each watchdog kill loses only the in-flight migration (per-migration commit + db.migration recording); the loop grinds through ~120s chunks with SIGABRT kills + 30s restarts. Converges, ugly (journal full of watchdog kills; orphaned in-container psql backends per kill — docker-exec doesn't forward the cgroup kill, and the #14 orphan-terminate at :1653 only fires on the 5-min ErrCommandTimeout, which the 120s watchdog always pre-empts).
- **Any single migration >~120s:** the kill loop can never get past it. Cycle ≈ 10s init + 120s + 30s RestartSec ≈ 160s → ~3.75 starts per 600s < StartLimitBurst=5 → **the start limit never trips; the unit loops indefinitely**. This is the rune wedge (40h loop) reborn at the boot-migrate site — 017 fixed the TimeoutStartSec edition; this is the WatchdogSec edition.

Also undersized independently of the watchdog: :1644's timeout is **5 minutes** vs the protected site's 30 — even with heartbeats fixed, a Norway-size delta would trip it. And the inline twin (`cli/cmd/install_upgrade.go:198`, the `./sb install` crash-recovery boot-migrate) runs via `runCmdDir` (install.go:2208-2214) — **no timeout at all** (unbounded foreground; no watchdog there since there's no systemd, so it's a boundedness gap, not a wedge).

## The suite's blind spot: the C12 watchdog net is vacuous

`3-postswap-migration-timeout.sh` — the suite's only ">120s migration vs watchdog" regression net (Race B) — **no longer tests the watchdog at all**:

1. It dispatches **inline** (`./sb install` in tmux; scenario line 210-217): no NOTIFY_SOCKET → `sdNotify` no-ops → no watchdog exists anywhere in the flow.
2. Its stall fires at the **inline crash-recovery boot-migrate** (install_upgrade.go:198, unbounded `runCmdDir`) — not at the applyPostSwap ticker site its header claims to validate (the 013 structural finding guarantees this: boot-migrate consumes the delta first).
3. Its load-bearing assertion (`NRestarts delta ≤ 2`) reads the counter of a systemd unit that isn't driving the install — vacuously green.

So the "24/28, all reds harness, zero product" conclusion is sound **for what the suite actually tests** — but the WatchdogSec×migration interaction on the service path is tested by nothing. One of the 24 greens is a rotted net sitting exactly on top of the campaign's top remaining product gap.

## RED reproducer (test-first; harness-only, no King gate needed)

**Rewrite `3-postswap-migration-timeout` to SERVICE dispatch** — which simultaneously (a) is 012's RED reproducer, (b) repairs the vacuous Race-B net at the site where migrations actually run, (c) follows the King's 013 Option-A doctrine (test the real production path).

Shape (reuses existing machinery: the C12 stall site migrate.go:349-363, the synthetic 2099 stall-target migration fixture, `fabricate_scheduled_upgrade_row`):

1. Install at older release (no seed) + populate demo data + plant the synthetic stall migration — unchanged from today's scenario.
2. **New harness helper:** install a systemd user drop-in for `statbus-upgrade@.service` with `Environment=STATBUS_INJECT_AT=migration-slower-than-systemd-unit-timeout` + `Environment=STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE=/tmp/stall-release-c12`; `daemon-reload`; restart the unit. Create the release file.
3. Schedule the upgrade (`fabricate_scheduled_upgrade_row` + NOTIFY wake, like watchdog-reconnect) → service executeUpgrade → checkout → swap → exit-42 → fresh boot → **boot-migrate spawns `sb migrate up`, the child hits StallHere on the first pending migration** — parked, zero WATCHDOG=1 sources.
4. `wait_for_inject_stall_ready`, **then snapshot NRestarts as the post-swap baseline** (the exit-42 handoff itself legitimately increments NRestarts once — baselining after the stall excludes it), hold 180s, remove the release file, wait for upgrade completion.
5. Assert (tightened): NRestarts delta **== 0** from the post-stall baseline, AND no watchdog signature in the journal / `systemctl show -p Result` ≠ watchdog, plus the existing terminal-state/data-intact/flag-absent checks.

**Expected RED on current code:** watchdog SIGABRT at ~READY+120s while the child stalls; restart; stall re-fires; delta ≥ 1 → RED with the exact production wedge signature. **Expected GREEN after the fix:** ticker keeps the unit alive across the 180s hold; delta == 0. Same RED→GREEN proof protocol as 017. If the RED does *not* reproduce, that falsifies my model and we stop and re-question (test-first as discovery).

Cost: ~2 VM-hours total for the pair (~€0.015). One new small harness helper (the env drop-in), which composes with — does not wait for — STATBUS-021's transport helper.

## Fix design (product, King-ratified, after the RED is observed)

**Invariant to establish:** *every DB-size-scaled subprocess the service runs in the active phase executes under an explicit, bounded, always-ping watchdog cover* — boot-migrate is today's confirmed violation.

1. **service.go:1644** — wrap boot-migrate with the existing primitive, exactly the applyPostSwap pattern (:3755-3761):
   - `runGatedWatchdogTicker(tickerCtx, nil, applyPostSwapStallThreshold, applyPostSwapWatchdogCadence, func(){ sdNotify("WATCHDOG=1") }, done)` — **nil progress = always-ping** (documented at watchdog.go:158-159), the same semantics deferGating gives the protected migrate, for the same reason (a single big DDL is legitimately silent). Cancel + join immediately after runCommandToLog returns. No new machinery; an explicit bounded defer, doctrine-consistent (watchdog.go:82-90).
   - Timeout **5m → 30m**, extracted as a shared const with :3952 (e.g. `migrateUpTimeout`) so the two sites cannot drift. The #14 orphan-terminate at :1653 stays, now firing at 30m.
   - `io.Discard`/`onAdvance=nil` can stay (journal already receives raw output via MultiWriter; boot has no ProgressLog).
2. **cli/cmd/install_upgrade.go:198** — replace unbounded `runCmdDir` with the same 30-min bound + a clear actionable timeout error (+ orphan-terminate parity if a conn is available at that point). No watchdog needed (no systemd); this closes the unboundedness gap only.
3. **Comment repairs in the same commit** (gate-output-with-intent): service.go:1637-1643 ("it emits per-migration progress" → describe the ticker), ops/statbus-upgrade.service:83-104 (boot-migrate's active-phase cover is the always-ping ticker bounded at 30m, mirroring the applyPostSwap migrate exemption).

**Deliberately NOT in this fix:** relocating delta execution off boot-migrate (e.g. skipping boot-migrate when a service-held PostSwap flag is present so the protected applyPostSwap migrate does the work). That is a real architectural question 013 surfaced — but it must be designed against the rc.63 constraint that created boot-migrate (recoverFromFlag queries public.upgrade and needs the upgrade-system schema current first), and the minimal fix is required **regardless** of where upgrade deltas run, because boot-migrate also carries genuine-skew deltas (install.sh updates, manual pulls). The two compose; executor placement can be its own task later.

**Follow-up audit (one task, cheap):** enumerate every other DB-size-scaled step reachable in `Run()` startup before any ticker arms. Confirmed covered: boot-migrate (this fix). **Needs a look: `recoverFromFlag` → `recoveryRollback` → restoreDatabase** — a Norway-size pg_restore during startup recovery runs after READY=1 with, as far as I can see, no ticker armed (rollback call sites pass `onAdvance=nil`, e.g. :4738/:4780/:4958, and `progress.File()` bypasses ProgressLog.Write's heartbeat). If confirmed, that is 012's sibling and the same primitive covers it. I have not traced it to ground — flagging, not asserting.

## Sequencing

1. Harness: rewrite the C12 scenario to service dispatch + tightened assertions → run → **observe RED** (validates the model empirically before product code moves).
2. King ratifies this design → land the product fix (small diff: one ticker wrap + one const + one timeout bound + comments).
3. Re-run scenario → **GREEN**. RED→GREEN pair on real VMs, same protocol as 017.
4. File the startup-recovery audit task (recoveryRollback coverage).

## Critical files

- `cli/internal/upgrade/service.go:1621` (READY=1), `:1644-1679` (boot-migrate + 017 fall-through), `:1689` (recoverFromFlag), `:1736-1753` (idle tick), `:3560-3633` (always-handoff + exit-42/Exec), `:3689-3761` (gated ticker arm), `:3949-3953` (protected migrate — the pattern to mirror)
- `cli/internal/upgrade/watchdog.go:109-120` (sdNotify), `:122-181` (stall threshold, cadence, runGatedWatchdogTicker — reuse as-is), `:200-216` (emitHeartbeat)
- `cli/internal/upgrade/exec.go:144-161` (runCommandToLog), `cli/internal/upgrade/prefix_writer.go`
- `cli/internal/migrate/migrate.go:349-379` (C12 stall + C6 kill sites), `:784-793` (per-migration output)
- `cli/cmd/install_upgrade.go:193-212` (inline boot-migrate), `cli/cmd/install.go:2208-2214` (runCmdDir — unbounded)
- `ops/statbus-upgrade.service` (WatchdogSec=120 :75, TimeoutStartSec :108, StartLimit :22-23, comments :52-57 + :83-104)
- `test/install-recovery/scenarios/3-postswap-migration-timeout.sh` (the rotted net to rewrite)

## Verification

- RED: rewritten scenario on a real VM shows NRestarts delta ≥ 1 from post-stall baseline + `Result=watchdog` while the stall holds; upgrade completes only after kills.
- GREEN: same scenario post-fix shows delta == 0, no watchdog signature, upgrade completes after release; data intact; flag absent.
- Unit-level: a Go test asserting the boot-migrate call site arms the ticker (same style as `resume_start_phase_test.go`'s source-order assertions) so the cover can't silently regress.
