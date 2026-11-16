---
id: doc-006
title: Diagram↔reality sync audit 2026-06-11
type: specification
created_date: '2026-06-11 11:48'
tags:
  - install-recovery
  - upgrade
  - audit
  - diagram
  - test-coverage
  - STATBUS-012
  - STATBUS-013
---
# Diagram↔reality sync audit — 2026-06-11

**Author:** engineer (opus). **Directive (King, via architect):** "check that our diagrams and our reality, the tests, are still synchronized." Read-only audit. Triggered by the STATBUS-012 finding (boot-migrate consumes every upgrade's migration delta with no watchdog cover) + the discovery that two regression nets (C12-old, C15) are vacuous/weak.

**Verdict:** The upgrade-timeline diagram + doc are **out of sync with the verified post-swap migration reality** in two structural ways (boot-migrate is invisible on the post-swap boot; the applyPostSwap migrate is drawn as the executor when it is a no-op). The diagram also **asserts watchdog coverage that does not exist** (migration-timeout) and **lists a deferred scenario as coverage** (worker-ddl-deadlock). The scenario suite's **kill nets are exemplary** (explicit "✓ RED confirmed" site-proofs); vacuity is **concentrated in the stall/watchdog family** — C12-old (now rewritten, RED unproven), C15 (blind sleep), C13 (deferred + green-vacuous).

Severity legend: **HIGH** = a false guarantee or a net that hid/can hide a real product gap; **MEDIUM** = misleading but not currently masking a live bug; **LOW** = imprecision/cosmetic.

---

## Part A — diagram + timeline doc vs verified STATBUS-012 reality

Verified reality (doc-005, code-confirmed): on **every** service-path upgrade, Step 6b always hands off (`os.Exit(42)` under `d.runningAsService`, service.go:3616-3618). The fresh post-swap process re-runs the **entire** `Service.Run` startup: `READY=1` (service.go:1621) → **boot-migrate `sb migrate up`** (service.go:1644) → `recoverFromFlag` (service.go:1689). Boot-migrate therefore **consumes the whole migration delta** before recovery; the elaborately-protected `applyPostSwap` migrate (service.go:3953) then runs against an already-migrated schema — a **structural no-op for migrations in the normal flow**.

| # | Artifact | Claim (as drawn/written) | Reality | Evidence | Severity |
|---|----------|--------------------------|---------|----------|----------|
| A1 | `upgrade-timeline.plantuml` post-swap band | Post-swap restart goes **straight** to `recoverFromFlag` → `resumePostSwap` → `applyPostSwap` (lines 106-119). boot-migrate on the post-swap boot is **not shown**. | The fresh process runs the full Service-boot sequence — `READY=1` → **boot-migrate** → `recoverFromFlag` — so the migration delta is consumed at boot-migrate **before** recovery is even consulted. | plantuml:106-119 omit it; service.go:1621→1644→1689; resume_start_phase_test.go pins this order | **HIGH** (the exact site where every upgrade's migrations run, and the 012 watchdog gap, is invisible) |
| A2 | `upgrade-timeline.plantuml` line 119 + `upgrade-timeline.md` line 119 | `./sb migrate up` inside `applyPostSwap` is **"apply pending migrations"** — drawn/written as the migration executor. | In the normal flow boot-migrate already applied them; the applyPostSwap migrate is a **no-op**. Migrations effectively run at boot-migrate, not here. | plantuml:119; timeline.md:119 ("11. `./sb migrate up --verbose` — apply pending migrations"); doc-005 §severity | **HIGH** (puts migrations where they don't run; the protection narrative attaches to the wrong site) |
| A3 | `plantuml` line 44 + `timeline.md` lines 65,68 | boot-migrate labeled **"schema-skew guard"** / "boot `migrate up` schema-skew guard". | It is the **de-facto migration executor for every upgrade**, not a narrow rc.63 column-rename guard. It also carries genuine-skew deltas (install.sh, manual pulls). | plantuml:44; timeline.md:65,68; doc-005 §severity | **MEDIUM** (undersells the load-bearing step) |
| A4 | `upgrade-timeline.md` "Service boot" lines 60-66 | "Before the main loop ticks, the service runs `recoverFromFlag` once… **It then emits** `sd_notify READY=1`." → implies recoverFromFlag precedes READY=1. | Verified order is `READY=1` (1621) → boot-migrate (1644) → `recoverFromFlag` (1689). The doc **inverts** recoverFromFlag vs READY=1 and never states boot-migrate runs between them. | timeline.md:60-66 vs service.go:1621/1644/1689; resume_start_phase_test.go | **MEDIUM** (muddles the exact ordering 012 hinges on) |
| A5 | `plantuml` TEST note line 173-174 | "TEST **3-postswap-migration-timeout** … a slow … migration stays **BOUNDED** (heartbeat/…)" — asserted as proven coverage. | (a) That scenario was **vacuous** until commit 908191f0c (inline dispatch → no watchdog in flow; wrong site). (b) The real boot-migrate site has **no watchdog cover** — the 012 gap, still unfixed. The diagram asserts a guarantee that does not hold. | plantuml:173-174; doc-005 §"suite blind spot"; STATBUS-012 | **HIGH** (a green-looking guarantee over the campaign's top product gap) |
| A6 | `plantuml` TEST note line 173 | Lists "TEST **3-postswap-worker-ddl-deadlock**: a … worker-locked migration stays BOUNDED" as coverage. | That scenario is **deferred — it does not run on CI** ("does NOT run on Hetzner until the architectural fix lands"); it is a known-RED documentation net. | plantuml:173; scenario header lines 38-66 | **MEDIUM** (lists non-running scenario as coverage) |

---

## Part B — STATBUS-013 next-step: migrate-killed-after-commit on the SERVICE-dispatch path

King's 013 next-step: the diagram must show the migrate-killed-after-commit spec (kill in the commit↔record window → re-run → "relation already exists" → restore-from-snapshot → rolled_back) on the **service-dispatch** path.

**Status: PARTIALLY MET (prose only, wrong site attribution).**

- The diagram **does** describe it: the commit↔record cells (plantuml:142-172) name cell (2) `migrate-killed-after-commit`, the GREEN reproducer `3-postswap-migrate-killed-after-commit`, the "relation already exists" → restore → `rolled_back` path, and explicitly cites **both** entrypoints — service boot service.go:1644 **and** `./sb install` install_upgrade.go:198 (plantuml:153-159). So the substance and the service path are present.
- **Gap B1 (MEDIUM):** the cells live in a **note attached to the applyPostSwap/PostSwap-resume region**, and speak of "the migration's tx" generically. Given A1/A2, the kill+commit actually happens at **boot-migrate** (pre-`recoverFromFlag`), not at the applyPostSwap migrate the note sits under. The site attribution is fuzzy — a reader places the event at the wrong migrate. The fix is the same as A1: surface boot-migrate on the post-swap boot, and anchor the commit↔record cells to it.
- **Gap B2 (LOW):** this is sequence-note prose, not sequence arrows. Acceptable (the cells are inherently a state-table), but the service-dispatch path itself is never an arrow.

---

## Part C — scenario vacuity sweep

Question per scenario: **does the load-bearing assertion verify the injected failure actually fired, or can it pass on a sleep-and-hope?** Reviewed all 30 scenarios; classified the fault-injection ones.

### C.1 — WEAK / VACUOUS (load-bearing assertion can pass without the injection firing)

| Scenario | Claimed injection | Why it can pass vacuously | Evidence | Severity |
|----------|-------------------|---------------------------|----------|----------|
| **3-postswap-watchdog-reconnect (C15)** | Stall the post-swap DB reconnect past WatchdogSec; prove the gated ticker keeps the unit alive. | **Blind `sleep STALL_HOLD_S`** with **no** `wait_for_inject_stall_ready` and **no** pgrep of the parked reconnect. Load-bearing assertion is `NRestarts delta == 0` (line 321) — satisfied whenever **nothing** kills the unit, including when the stall **never fired** (env not applied, or reconnect completed before parking). Accepts any terminal state. | scenario lines 190-191 (arm), 272 (blind sleep), 321 (delta); contrast the sibling below | **HIGH** |
| **3-postswap-migration-timeout (C12)** | Stall boot-migrate past WatchdogSec; prove boot-migrate's watchdog cover. | **Was** vacuous (inline dispatch → no watchdog in flow; stalled at the wrong site). **Rewritten** 908191f0c to service dispatch with strong assertions (`wait_for_inject_stall_ready` + `flag==post_swap` site-proof + `delta==0 ∧ Result≠watchdog`). **But RED is unproven**: run-1 (tmp/012-red-run-1.log) showed the stall never fired (likely pre-swap rollback / procurement-at-HEAD, or no pending migration) — the rewrite's verification is sound in principle but **not yet validated on a VM**. | doc-005 §"suite blind spot"; commit 908191f0c; run-1 result | was **HIGH**, now **rewritten-pending-proof** |
| **3-postswap-worker-ddl-deadlock (C13)** | Worker holds AccessShareLock; an upgrade DDL contends for AccessExclusiveLock → bounded vs wedge. | (a) **Deferred** — does not run on CI. (b) Green direction asserts only "terminal within budget" + data intact; it **never asserts a lock contention actually occurred**, so if the v2026.05.2→HEAD delta has no DDL on a worker-touched table, it passes with no deadlock exercised. | scenario header lines 38-66; assertion lines 207-237 (no contention check) | **MEDIUM** |
| **5-install-seed-on-populated (R5)** | Seed restore onto a populated DB. | Documented known-RED ("VM to confirm the bug — which we already know exists"). Has a real load-bearing assertion (line 145) but is a documentation/known-RED net like C13 — flagged for parity, not a live false-green. | scenario lines 55, 145 | **LOW** |

### C.2 — STRONG (verify the injected failure fired before asserting recovery) — the bar the suite mostly meets

- **One-shot-kill marker-absence proof (STATBUS-022):** `3-postswap-mid-migration-kill` (lines 181-183), `3-postswap-between-migrations-kill` (205-207) — assert the arm marker is **gone** ("the injected kill never fired" if present) + `db.migration max_version advanced`. The kill is *proven* to have fired.
- **Explicit "✓ RED confirmed" site-proofs:** `2-preswap-backup-kill` (line 207: flag=PreSwap + .tmp backup + binary unswapped), `2-preswap-checkout-kill` (203), `2-preswap-binary-swap-kill` (163), `3-postswap-container-restart-kill` (168: flag pinned Resuming + row in_progress), `3-postswap-resume-died-rollback` (172 + no-loop proof 287-293), `4-rollback-kill` (168: exit 137 expected). These are model nets — they fail loud if the kill lands at the wrong site.
- **Stall confirmed before assertion:** `3-postswap-archivebackup-watchdog` **pgreps the tar** (lines 304-312, `TAR_COUNT`) before asserting `NRestarts delta≤1` — **this is the correct pattern C15 lacks**. `3-postswap-mid-tx-kill` and `1-boot-concurrent-install` use `wait_for_inject_stall_ready`. `3-postswap-archivebackup-resume` verifies the kill (flag present) and its RED/GREEN both depend on the stall.
- **Install-state injections verify the condition:** `5-install-stage-a-killed-migrate` (pgrep psql + zombie reaped), `-stage-b-pool-exhaustion` (verifies app-user psql blocked, line 56), `-stage-c-systemd-failed` (verifies failed state, line 47), `-stage-d-advisory-zombie` (zombie present→reaped, lines 54/90), `-stage-e-worker-busy` (worker connections preserved, line 78).
- **Boot/state scenarios** (`1-boot-advisory-too-early`, `1-boot-startup-timeout`, `1-boot-flag-stale-handoff`, `0-happy-*`, `5-install-bool-text-regression`, `5-install-drifted-unit-reconciled`) verify observable state/journal transitions; not in the stall/kill vacuity-risk class.

### C.3 — the pattern

The suite's **kill** nets are rigorous (site-proofs everywhere). Vacuity lives in the **stall/watchdog** family, because a stall produces no terminal-state change to assert on — so a weak net falls back to a blind sleep + a counter that is *also* satisfied by "nothing happened." The gold-standard fix already exists in-tree: **confirm the stall parked** (pgrep the stalled process, as `archivebackup-watchdog` does; or `wait_for_inject_stall_ready`, as C12-new does) **before** the NRestarts/Result assertion. C15 is the one shipped watchdog net that still lacks it.

---

## Recommendations (for the architect/foreman to task; not done here — read-only audit)

1. **Diagram + doc fix (pairs with the 012 product fix):** surface boot-migrate on the post-swap boot (A1), redraw the applyPostSwap migrate as a normal-flow no-op / skew-only (A2), relabel boot-migrate as the delta executor (A3), fix the md ordering (A4), and re-anchor the 013 commit↔record cells to boot-migrate (B1). Do it in the same commit that lands the 012 ticker so diagram and reality move together.
2. **A5/A6 coverage honesty:** the migration-timeout TEST note must not claim "bounded" until C12-new proves RED→GREEN on a VM; mark worker-ddl-deadlock as **deferred (not in CI)**, not coverage.
3. **C15 hardening (HIGH):** add a stall-fired confirmation (pgrep the parked reconnect/migrate child or `wait_for_inject_stall_ready`) before the `delta==0` assertion — mirror `archivebackup-watchdog`. Until then C15's green proves nothing about the reconnect watchdog.
4. **C13 green-direction:** when it is eventually run, assert the migration actually **blocked** on a lock (e.g. `pg_locks` shows the AccessExclusiveLock waiting) before accepting "terminal in budget."

## Critical files
- `doc/diagrams/upgrade-timeline.plantuml` (post-swap band 104-127; TEST notes 134-186; cells 142-172)
- `doc/upgrade-timeline.md` (Service boot 58-73; Binary-swap restart+resume 106-131)
- `cli/internal/upgrade/service.go` :1621 (READY=1) / :1644 (boot-migrate) / :1689 (recoverFromFlag) / :3616-3618 (exit-42) / :3953 (applyPostSwap migrate)
- `test/install-recovery/scenarios/3-postswap-watchdog-reconnect.sh` (C15, weak), `3-postswap-migration-timeout.sh` (C12 rewrite), `3-postswap-worker-ddl-deadlock.sh` (C13 deferred), `3-postswap-archivebackup-watchdog.sh` (the strong pattern)

---

## Part D — procurement-staging vacuity (added 2026-06-11, after STATBUS-012 run-1)

**A second, deeper vacuity vector than Part C's "weak assertion": a service-dispatch post-swap scenario that does not stage `./sb` at HEAD rolls back AT PROCUREMENT and never reaches its post-swap injection site at all.** Surfaced empirically: STATBUS-012 run-1 produced "stall never fired, flag gone, terminal <300s" — H-A confirmed (architect, static + run-2).

**Confirmed mechanism (code + harness):**
1. `upload_sb_to_vm` (vm-bootstrap.sh) reassembles the HEAD binary at **`/tmp/sb`** on the VM (`cat /tmp/sb-upload-chunk-* > /tmp/sb`) — **NOT** at `~/statbus/sb`. The initial install left `~/statbus/sb` at INSTALL_VERSION (v2026.05.2).
2. On dispatch, Step 6b procurement runs `buildBinaryOnDisk` → `sbAlreadyAtCommit` parses `~/statbus/sb --version` (service.go:5123-5126). v2026.05.2 ≠ HEAD → no skip → `os.Rename sb→sb.old` → **`make -C cli build`**.
3. The harness VM has **no Go toolchain** (zero `golang` refs in bootstrap/hardening libs) → build fails in seconds → `sb.old` restored → `d.rollback` **pre-swap** → row=`rolled_back`, flag removed, **no exit-42, no post-swap boot, no injection**.

So any service-dispatch post-swap scenario that schedules an upgrade to HEAD **without first** `cp /tmp/sb ~/statbus/sb` silently rolls back at procurement. (`H-2` — synthetic migration not seen — is dead: no `git clean` in the flow; migrate enumerates `migrations/*.up.sql` via `filepath.Glob`, migrate.go:452, so untracked files count.)

**Why some scenarios are immune and others silently green — the payoff of the Part C strong/weak split:** the procurement bug bites strong and weak nets **equally**, but **strong nets fail loud, weak nets pass silently**:
- `3-postswap-archivebackup-watchdog` **pgreps the tar** (lines 304-312) — a procurement rollback means the tar never runs → "✗ archiveBackup tar not observed" → **scenario FAILS**. The bug cannot hide.
- `3-postswap-watchdog-reconnect (C15)` **blind-sleeps** then asserts `NRestarts delta==0` (line 321) **and accepts `rolled_back` as terminal** — a procurement rollback satisfies both → **passes vacuously**. Its stall site has **plausibly never fired on a VM**.

This makes C15 **doubly vacuous** (procurement rollback + blind-sleep that accepts it) and **escalates it from "weak verification" (Part C) to "the injected failure has likely never occurred in any green run."** Same root the architect flagged.

**Binary-staging status (static; service-dispatch post-swap scenarios):**

| Scenario | Stages `~/statbus/sb`=HEAD before dispatch? | Verification strength | Net status |
|----------|---------------------------------------------|-----------------------|------------|
| 3-postswap-migration-timeout (C12) | YES — `cp /tmp/sb ~/statbus/sb` (line 182, **architect patch post-run-1**) | strong (wait_for_inject_stall_ready + flag site-proof) | fixed, RED pending |
| 3-postswap-container-restart-kill | YES — `cp /tmp/sb ./sb` (line 126) | strong (RED-confirmed) | sound |
| 3-postswap-between-migrations-kill | YES — `cp /tmp/sb ./sb` (line 155) | strong (marker-absence) | sound |
| **3-postswap-watchdog-reconnect (C15)** | **NO** | **weak (blind sleep, accepts rolled_back)** | **CONFIRMED vacuous — procurement rollback passes** |
| 3-postswap-archivebackup-watchdog | NO explicit `cp` | strong (pgrep tar) | **needs check** — if it has been green, it is NOT rolling back (the pgrep would fail); confirm it stages the binary another way or the green is stale |
| 3-postswap-archivebackup-resume | NO explicit `cp` | medium (RED/GREEN both depend on the stall) | **needs check** — header claims "VERIFIED runs 27107825797/27109134019"; reconcile against the rollback mechanism |
| 3-postswap-resume-died-rollback | NO explicit `cp` | strong (RED-confirmed + no-loop proof) | **needs check** — its kill needs the post-swap site; a strong check would catch a rollback |

Inline-dispatch scenarios (mid-migration-kill, mid-tx-kill, migrate-killed-after-commit, migration-deterministic-error) reach Step 6b through `./sb install`, whose install script does its own `cp /tmp/sb ./sb` (referenced at migration-timeout.sh:179) — they get HEAD staging for free, and their strong marker-absence checks would catch a rollback regardless.

**Severity: HIGH for C15 (confirmed silently-vacuous on a latent harness bug); the three "needs check" rows are MEDIUM pending the architect's run-artifact reconciliation — flagged, not asserted, to avoid over-claiming without a VM (the same discipline run-1 taught).**

**Added recommendation (5):** standardize HEAD binary-staging for service-dispatch post-swap scenarios — a single `stage_head_binary` helper (`cp /tmp/sb ~/statbus/sb && chmod +x`) called right after `upload_sb_to_vm`, so no scenario can silently roll back at procurement. Then the only way to be green is to actually reach the post-swap site. Pairs naturally with recommendation 3 (C15 stall-fired confirmation) — both are needed: staging gets you to the site, the confirmation proves you stayed there.
