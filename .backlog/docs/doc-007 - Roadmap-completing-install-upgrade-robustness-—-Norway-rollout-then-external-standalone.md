---
id: doc-007
title: >-
  Roadmap: completing install/upgrade robustness — Norway rollout, then external
  standalone
type: specification
created_date: '2026-06-11 15:43'
tags:
  - install-recovery
  - upgrade
  - recovery
  - roadmap
  - architect-plan
  - release
  - norway
---
# Roadmap: completing install/upgrade robustness — Norway rollout, then external standalone

**Architect (Fable), 2026-06-11. The forward plan from "two wedges proven fixed, RC cutting" to "Norway runs unattended upgrades on the stable channel, external standalone opens after."** Every claim below is code-traced (file:line) or run-evidenced; the one new product finding (Track A) was traced to ground for this roadmap.

---

## North Star and where we stand

**North Star:** unattended install/upgrade. The operator's sole action is the installer; every failure either self-recovers or terminates in a clean, actionable state. Norway (rune, 32 GB production data) rolls out on the stable channel; once a full RC→stable→deploy cycle is proven, external standalone deployments open.

**Where we are (proven, not hoped):**
- The two product wedges are closed with RED→GREEN proof on real VMs: recovery fall-through (017, awaiting only ratification ceremony) and boot-migrate watchdog cover (012, RED @ 78ab02598 delta=1 watchdog → GREEN @ 7c2511087 delta=0 completed, one commit apart).
- The campaign's verdict stands: **zero confirmed product recovery bugs beyond those two** across ~30 scenarios and ~15 weeks-equivalent of harness iteration. The recovery code held under every other injected fault.
- Latest comprehensive suite run: 24/28 green (run 27306718138); the 4 reds are all harness-layer (STATBUS-026..029).
- **RC cut: v2026.06.0-rc.01 tagged + pushed** (2026-06-11). Its tag-push harness run will hit the 6 h ceiling — expected; that run is the live exhibit of the 025 problem, not a regression signal. Prerelease does not gate on the harness; only stable does.
- **King decision (2026-06-11, at the cut): 031 gates the STABLE/Norway promotion, not the prerelease.** The wedge-fix list for that gate is known-bounded — 017 ✓, 012 ✓, 031 last (the sweep below).

**What remains is three tracks plus one sequence.** The tracks: (A) close the last product wedge-class, (B) make the validation suite able to say "green" to the stable gate, (C) walk the rollout path. None of it is exploratory — every item below has a known mechanism and a proven fix pattern.

---

## Track A — Product completeness: make the safety net itself unkillable

### A1 — The rollback-restore watchdog gap (STATBUS-031) — CONFIRMED, the last known wedge-class

The 012 fix established the invariant: *every DB-size-scaled step in the active phase runs under an explicit, bounded, always-ping watchdog cover.* This roadmap's code sweep (doc-005's flagged follow-up, 031's scope item 1) found **exactly one remaining violation, and it sits on the rollback path — the mechanism that fires precisely when an upgrade has already failed.**

Trace (current HEAD):
- `restoreDatabase` (exec.go:695-714) restores the DB volume via a docker-run **rsync of the entire volume** — DB-size-scaled — with `onAdvance=nil` and output to `progress.File()`, which bypasses `ProgressLog.Write`'s heartbeat. The last WATCHDOG=1 ping is the single `progress.Write` at exec.go:703, *before* the rsync starts.
- **Startup path — zero cover:** `Run()` → `recoverFromFlag` (service.go:1720) → `recoveryRollback` (:2135) → `rollback` (:4649) → `restoreDatabase` (:4777). No ticker exists here: boot-migrate's always-ping ticker was already cancelled (:1674), the main-loop heartbeat ticker doesn't exist yet (:1767). The watchdog armed at READY=1 (:1621) sees silence ~120 s into the rsync → SIGABRT mid-restore.
- **Execute path — gated cover that closes:** `applyPostSwap` failures route through `postSwapFailure` (:3675) → `rollback` *inside* applyPostSwap, so the progress-gated ticker (:3785-3792, defer-cancelled) is still alive — but it is **gated**: a silent rsync stops bumping, the gate closes at `applyPostSwapStallThreshold` = 3 min (watchdog.go:134), pings stop, the watchdog fires. Restores longer than ~3 min die on this path too.
- **The loop:** the flag is removed only at the terminal write *after* the restore completes — so a mid-restore kill leaves the flag in place → next boot → `recoverFromFlag` → restore **from scratch** → killed again. Indefinite restore loop, the rune-wedge shape, on the path whose whole job is to recover from failure. On Norway's 32 GB a restore >120 s is essentially guaranteed.
- **Secondary, same lesson as 012:** the rsync timeout is fixed at **10 min** (exec.go:704) — undersized against the 30-min philosophy at both migrate sites (`MigrateUpTimeout`, watchdog.go:154). Even with the watchdog covered, a 12-min restore manufactures `ErrRollbackDBRestore` → `failed`/degraded on a system that needed 2 more minutes.

**The sweep is COMPLETE (2026-06-11, this roadmap): restoreDatabase/rollback is the LAST uncovered DB-size-scaled step reachable in Run() startup.** Every step from process start to the first main-loop heartbeat was traced and classified (full ledger in the architect's sweep report). Two sharpenings beyond the filed task:
- **FOUR startup entries funnel into the uncovered rollback chain, not one:** (1) the Resuming/PreSwap latch (service.go:762/:829), (2) recoverFromFlag's ground-truth-failure branches (:889/:908/:922/:1042), (3) `completeInProgressUpgrade`'s ground-truth failure (:2271), (4) `resumePostSwap`'s stale-flag binary-skew branch. All four converge on `recoveryRollback` (:2135) → `rollback` (:4649) — one chokepoint covers everything.
- **The cover must wrap ALL of `rollback()`, not just restoreDatabase:** the tail's `rollback-docker-up` (`docker compose up`, 5-min bound, `onAdvance=nil`) is image-scaled and equally silent; restoreDatabase is the only DB-size-scaled member but not the only >120 s-capable member of the chain.

**Fix = the proven 012 pattern, applied at the chokepoint:** an always-ping ticker (nil progress) wrapping the body of `rollback()` (covers all four entries and every silent sub-step; `sdNotify` no-ops without NOTIFY_SOCKET so it is inert inline), the 10-min rsync timeout raised to a shared generous constant, comments repaired in the same commit, and a structural source-order guard test (the `TestBootMigrateWatchdogCover_SourceOrder` style). **Proof = the 012 protocol:** a scenario that stalls/slows the restore during startup recovery, RED on current code → fix → GREEN. ~2 VM-hours, ~€0.015.

This is King-gated product/recovery code: audit findings → King ratifies fix design → RED → fix → GREEN, same as 012.

### A2 — Startup-tail clearance: DONE (this roadmap's sweep)

Every other step between READY=1 (:1621) and the first heartbeat tick (:1779) is cleared with line evidence: boot-migrate **covered** (012 ticker, :1669-1675); applyPostSwap resume **covered** (gated ticker at its top, :3785-3792); all remaining steps **small/bounded** — recoverFromFlag pre-dispatch (git rev-parse/merge-base 2-min caps, row queries), resumePostSwap pre-ticker probes (docker ps / merge-base, 2-min caps), completeInProgressUpgrade (30 s health wait, bounded UPDATE retries, 30 s callback), markCurrentVersionCompleted, syncConfigToSystemInfo, cleanStaleMaintenance, checkMissedUpgrades (one COUNT — confirms 009: informational only), startListenLoop (goroutine spawn), initial discover (git fetch, 5-min cap). Pre-READY steps run under the TimeoutStartSec contract (documented at ops/statbus-upgrade.service:111-114, C11/1-boot-startup-timeout covers the class; the DB container progresses independently across service restarts, so WAL replay converges).

Three residual **LOW liveness nits** — named for honesty, NOT wedge-class (environmental, self-healing, no destructive re-work per cycle): (N1) a network-blackhole during the initial `discover` can sit silent up to its 5-min cap → watchdog kill-retry until the network returns; (N2) a wedged dockerd during the resume probes (≤2-min caps vs the 120 s budget); (N3) `pruneBackups`' RemoveAll on the rare belt path is filesystem-scaled. Each converges or lands in the documented `failed`-with-actionable-journal contract. Fold their one-line clearances into 031's task notes; no separate work.

**With A1 landed, the invariant holds across the entire startup+upgrade+recovery surface: the wedge CLASS is closed, not instances of it. The stable-gate wedge-fix list is known-bounded: 017 ✓, 012 ✓, 031 = the last.**

### A3 — Seed restore on a populated DB (STATBUS-018, direction c)

Fix the gate so the Seed step is **correctly skipped, quietly,** on a populated DB (`checkSeedRestored`/R5; verify whether 50fd4325f regressed it — AC#4). Why direction (c): the African-operator reality — the sole operator action is the installer, and "follow install instructions" means run it again — makes a scary-but-tolerated `pg_restore` ERROR on every routine refresh an operator-UX defect, not a cosmetic one. (c) removes the error *and* the silent slow-fallback in one move, with no pg_restore/sql_saga surgery. Likely clears STATBUS-029 with it.

### A4 — Non-gating product odds-and-ends (bundle opportunistically)

- 014's audit-trail wrinkle: `markCurrentVersionCompleted` flips `rolled_back` → `completed`, erasing the rollback from the row history. Decide preserve-vs-accept (recommend preserve — append, don't overwrite, the trail; cheap).
- 009 (`checkMissedUpgrades` semantics), 010 (stale validator message), 023 (fixture-fidelity design — architect owes the clean mechanism), 024 (see B6).

---

## Track B — Validation: a suite that can say GREEN to the stable gate

### B1 — Matrix split of the harness workflow (STATBUS-025) — the structural unblock, first in line

The stable gate (release.go:989 → `CheckWorkflowAtCommit`, workflow_check.go:81) requires the install-recovery-harness **workflow conclusion == success at the RC commit**. The current single serial job (~28 scenarios × ~13 min) hits GitHub's 360-min job ceiling → `cancelled`, which is never `success` — **an all-green suite still cannot pass the gate.** More green = slower = more cancelled: the gate is structurally unsatisfiable today.

Design (grounded in the current yaml, which already anticipates this at install-recovery-harness.yaml:23):
- **Discover job**: enumerate `scenarios/*.sh` → JSON; build the `sb` binary ONCE, upload as artifact (today every scenario reuses one build; keep that property — don't rebuild per job).
- **Matrix job per scenario**: download binary artifact, provision its VM, run ONE scenario, upload its log artifact. `max-parallel: ~8` to respect the Hetzner project server quota (design checklist: confirm quota ≥ max-parallel + any production VMs in the project). Per-job `timeout-minutes: ~45`.
- **Reap correctness — the one trap:** the current always() reap step deletes **every** `statbus-recovery-*` VM (yaml:219-227). Inside a parallel matrix that murders sibling jobs' live VMs. Per-job reap must be scoped to the job's own VM name; the global sweep moves to a final `needs: [matrix]` + `if: always()` cleanup job.
- **Stamps**: run.sh's all-scenarios stamp (run.sh:174-178) never fires under per-scenario selectors. CI needs no stamp (the gate reads the workflow conclusion — unchanged, zero release.go edits); local full runs keep the stamp. Fold in the agreed per-scenario stamp design (composable local OR CI, gate against the RC tag's commit) so the local pre-push observe-evidence hook stays meaningful.
- Wall-clock ≈ ceil(30/8) × ~15 min ≈ **~60 min** (vs 6 h+); cost unchanged (~€0.22/run — each scenario already bills a 1-hour VM minimum today); bonus: per-scenario logs and per-scenario re-run via the existing `scenarios` input.

### B2 — The four reds (STATBUS-026..029) — required for the gate, not optional polish

A matrix run with red jobs is still `conclusion: failure`. These are all harness-layer, diagnosed, and mostly share roots:
- **026 + 028** share the `restoreGitState`-on-VM root (working tree not restored to OLD; rc=75 abort) — diagnose once, fix both.
- **027**: inline-path upgrade-row state assertion after the mid-tx kill — align the assertion with the actual post-recovery contract.
- **029**: falls out of A3/018 (seed restore on populated) + the over-strict zombie assertion.

### B3 — Close the vacuity findings (the sweep is DONE — do not re-sweep)

The systematic vacuity question is already answered: doc-006 Part C swept **all 30 scenarios** (kill-nets exemplary; weakness concentrated in the stall/watchdog family; C15 the one shipped weak net) and Part D found the deeper procurement-staging vector. A new sweep would re-buy known information. What remains is **closing the found items, consolidated into one harness-hardening task**:
1. STATBUS-030: C15 stall-fired confirmation (the pgrep pattern its sibling archivebackup-watchdog already uses) — doubly needed since Part D showed C15's green has plausibly never exercised its stall.
2. `stage_head_binary` standardization (doc-006 rec 5) so no service-dispatch scenario can silently roll back at procurement and pass.
3. Reconcile the three Part-D "needs check" rows (archivebackup-watchdog, archivebackup-resume, resume-died-rollback) against the procurement-rollback mechanism.
4. The `wait_for_inject_stall_ready` quoting blindness → the scp'd-probe pattern (the 012 run-6 fix is the template; affects all callers).

### B4 — Scenario rewrites with decisions already made or one decision pending

- **013 (migrate-killed-after-commit)**: King decided Option A (service dispatch) 2026-06-08; the env-loss question is answered (service.go:3624 passes os.Environ() verbatim — test-only artifact). Remaining: the rewrite (AC#3) + diagram-loop closure. The 012 scenario rewrite is the exact template.
- **015 (container-restart-kill)**: needs the King's call. **Recommend Option 1 (confirm the contract):** the Resuming one-shot latch is intentional anti-infinite-loop design ("any non-planned restart while in_progress ⇒ rollback"), the product is correct, the scenario's premise is wrong. Option 2 (latch refinement) buys re-resume of an idempotent window at the price of recovery-semantics risk — the wrong trade during a hardening campaign.
- **014 (archivebackup-resume)**: **recommend Option A (redesign to genuinely reach + stall archiveBackup)** — otherwise watchdog-during-tar coverage rests on a single scenario (archivebackup-watchdog) and 014 stays a convergence test wearing a watchdog title.

### B5 — Tag→tag procurement scenario (pending the King's word — recommend YES, now filable)

Every current service-dispatch scenario pre-stages the binary, short-circuiting procurement — so **`replaceBinaryOnDisk` manifest-download, the path every real Norway upgrade takes, has zero scenario coverage** (the Part-D mechanism is exactly this blind spot's harness shadow). With real RC tags existing, an RC(n-1)→RC(n) scenario becomes possible: install at the previous tag, schedule the new tag, real manifest download + signature verify + swap + migrate. Note honestly: the rune canary deploy (C2) exercises this path for real before stable — B5's value is the *regression net for every future upgrade*, not the first proof. File now, build right after the gate work.

### B6 — `go test` in CI (STATBUS-024)

No workflow runs `go test`; the campaign keeps adding Go-layer guards (source-order pins, inject tests, 023's round-trip contract) whose teeth depend on it. Add `cd cli && go test ./...` to the fast lane; triage whatever rotted. Cheap, in-runner, immediate.

### B7 — Harness quality (parallel, non-gating)

STATBUS-023 (fixture fidelity — architect owes the clean design), 016 (logging-accuracy completion), 021 (named VM-script transport), 020 (restrict-agent realign).

---

## Track C — Rollout: the path to Norway, then outward

**Structural fact that shapes everything here:** rune/Norway is a **hardcoded canary slot for `./sb release stable`** (release_canary.go:43-46 — dev/niue + no/rune). The stable preflight requires a completed upgrade row for the RC commit on rune *before the stable tag can exist*. So "deploy to Norway" is not a step after stable — **Norway go-live and the stable gate are the same motion**, by design (production-scale fixture catching scale-dependent regressions pre-tag).

The walk:
1. **C1 — RC cut: DONE — v2026.06.0-rc.01.** Its tag-push triggered the harness suite on the pre-matrix workflow; that run will cancel at 6 h — **expected, not a failure signal** (harness reds/cancels don't gate prerelease; only stable gates on it). It is the live exhibit of the 025 problem.
2. **C2 — Gate-capable RC**: the tag-push harness run uses the workflow file *at the tag*, so the stable-gating RC is the **first RC cut after B1+B2+A1 land on master** (rc.02+). RCs are cheap; cut when the gate work is in.
3. **C3 — Canary deploys**: RC → dev (niue) and RC → rune-no. The rune deploy on 32 GB real data is simultaneously the de-facto scale-proof of the 012/031 covers (real boot-migrate, real restore sizes, real WatchdogSec — the thing no CX23 fixture can fake).
4. **C4 — `./sb release stable`**: all workflow gates green at the RC commit + both canaries completed → stable tag. Norway is then live on the stable channel; production-to-all / other SSB slots follow per doc/CLOUD.md.
5. **C5 — External standalone (the horizon, shaped now, tasked later):** (i) one full RC→stable→deploy cycle proven (= the above); (ii) operator-UX clean on routine paths — A3/018 is the standing offender; every failure actionable in installer terms (re-run the installer must always be a safe answer); (iii) the tag→tag procurement net green (B5 — external boxes *only* ever use manifest download); (iv) standalone install/upgrade docs hardened for non-SSB hosts (doc/DEPLOYMENT.md); (v) release-channel policy (who gets stable when). Add: external boxes have no SSB SSH access — the diagnostic bundle + callback notification path becomes the only eye we have; review it for the unattended-external case before opening.

---

## Sequencing — the critical path, what runs in parallel, what gates what

```
NOW ──────────────────────────────────────────────────────────────────▶
RC cut ✓ v2026.06.0-rc.01 (its tag-run cancels at 6h — expected, the 025 exhibit)
   │
   ├─ CRITICAL PATH (serial gates, parallel work inside each):
   │   1. Land the gate-makers on master  ──  B1 matrix split (engineer)
   │   2. (parallel with 1)               ──  B2 four reds: 026/028 one root; 027; 029←A3
   │   3. (parallel with 1)               ──  A1 031 fix: King ratifies→RED→fix→GREEN
   │   4. Cut rc.N+1 (carries B1+B2+A1)
   │   5. Tag-push harness run → GREEN (matrix, ~60 min)
   │   6. Canary deploys: RC → dev, RC → rune-no (= Norway scale-proof)
   │   7. ./sb release stable → tag → NORWAY LIVE on stable
   │
   └─ PARALLEL LANES (never block the path):
       B3 vacuity closure (030 + stage_head_binary + Part-D checks + probe quoting)
       B4 scenario rewrites (013 Option-A, 015 after King's call, 014 Option-A)
       B5 tag→tag procurement scenario (file now; build post-gate)
       B6 go-test CI lane          B7 fidelity/logging/transport
       A2 ✓ done (this roadmap)    A3 018 direction-c (feeds B2/029)
       A4 odds-and-ends            017 ratification ceremony → Done
```

**Why A1 (031) is ON the critical path — King-settled at the rc.01 cut:** 031 gates the **stable/Norway promotion** (not the prerelease). Shipping Norway while the rollback path has a known kill-loop would mean the *first failed upgrade on real data* could wedge the box mid-restore — the exact class this campaign was run to extinguish, on the path whose job is to un-fail failures. The 012 precedent applies with equal force to its sibling, and the fix is small because the pattern, the primitive, and the proof protocol all exist. The fix list behind that gate is known-bounded (the A1 sweep): 017 ✓, 012 ✓, 031 last. Estimated: B1 ~1 engineer-day; B2 ~1-2 days across two roots; A1 ~1-2 days including VM proof. **The gate-capable RC is days away, not weeks.**

**Explicit gates:** (G1) matrix workflow green at the RC commit ← B1+B2+A1 landed before that RC; (G2) canary completed on rune ← G1's RC deployed; (G3) stable preflight all-green ← G1+G2 → tag → Norway live. External standalone opens only after G3 has survived one real cycle.

---

## Open questions for the King (each with its decision criterion)

1. ~~Does A1/031 gate the release?~~ **SETTLED at the rc.01 cut: 031 gates the stable/Norway promotion, not the prerelease.** The critical path above reflects it.
2. **015: Option 1 (confirm the Resuming-latch contract, fix the scenario) vs Option 2 (refine the latch)?** Criterion: is re-resume of the idempotent step-11/12 window worth touching recovery semantics mid-campaign? Recommend **Option 1**.
3. **014: Option A (redesign to genuinely reach archiveBackup) vs B (accept as convergence test)?** Criterion: should watchdog-during-tar coverage rest on one scenario or two? Recommend **A**.
4. **B5 tag→tag procurement scenario** — proposed earlier, awaiting your word. Recommend **file now, build after the gate work**; it is the regression net for every future Norway upgrade. (rc.01's existence makes the rc(n-1)→rc(n) shape concrete.)

## Critical files (for the implementers)

- A1: cli/internal/upgrade/exec.go:695-714 (restoreDatabase), service.go:1720/2135/4649/4777 (startup chain), :3675/:3785-3792 (execute chain + gated ticker), watchdog.go:134/:154 (threshold, the 30-min const to share), cli/internal/upgrade/resume_start_phase_test.go (guard-test style)
- B1: .github/workflows/install-recovery-harness.yaml (esp. :219-227 reap), test/install-recovery/run.sh:12-27/:174-178 (stamp), cli/internal/release/workflow_check.go:81 (gate semantics — unchanged)
- B2: test/install-recovery/scenarios/2-preswap-checkout-kill.sh:154, 4-rollback-kill.sh:153/:201, lib/vm-bootstrap.sh:575 (restoreGitState root), 3-postswap-mid-tx-kill assertions.sh:50
- C: cli/cmd/release.go:887-1076 (stable preflight), cli/cmd/release_canary.go:31-46 (canary slots), doc/CLOUD.md, doc/DEPLOYMENT.md

## Verification (how we know the roadmap is done)

The roadmap is complete when: (1) `./sb release stable` exits green with zero SKIP_* bypasses, (2) the stable tag's upgrade completes unattended on rune with the journal showing zero watchdog kills and zero manual interventions, (3) a deliberately failed upgrade on a Norway-size DB rolls back to completion under the watchdog (the A1 GREEN, re-proven at scale by any real rollback), and (4) the next RC cycle repeats all of the above without a human touching anything but `./sb release` commands.
