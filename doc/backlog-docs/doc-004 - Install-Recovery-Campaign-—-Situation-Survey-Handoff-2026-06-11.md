---
id: doc-004
title: Install-Recovery Campaign — Situation Survey & Handoff (2026-06-11)
type: other
created_date: '2026-06-11 07:48'
---
# Install-Recovery Campaign — Situation Survey & Handoff

**As of 2026-06-11 ~03:30Z. For a fresh (smarter-model) session to survey and continue.**

## North Star
Unattended install/upgrade so **Norway (NO) can roll out**, and to open external standalone deployments. The campaign hardens install-recovery. The gating product bug is **STATBUS-017 (the "rune wedge")** — now **SOLVED + PROVEN** on real VMs.

## Headline status
- **STATBUS-017 (rune wedge): SOLVED + PROVEN.** Awaiting the King's ratification of product diff `584919285` (the only product gate of the campaign). Both its reproducers were GREEN (run 27241262390), and tonight its in-suite scenarios (`mid-migration-kill`, `between-migrations-kill`) ALSO went GREEN on real VMs — additional confirmation the fix is clean.
- **The RC is FULLY CUT-PREPPED at `cd2f5d51f`** (current master HEAD). All 5 release stamps present at that SHA, tree clean, Images green. **Every `./sb release prerelease` gate passes.** The ONLY thing holding the cut is the 017 ratification (a decision, not work).
- **Validation run 27306718138 @ cd2f5d51f: 24 PASS / 4 FAIL** (up from 19/28). 6 of 8 overnight fixes GREEN. All 4 remaining reds are **HARNESS, 0 product**.

## What landed overnight (master, HEAD=`cd2f5d51f`)
- `751bae42c` **STATBUS-019** — bundle.go `to_jsonb(u) FROM public.upgrade u` alias fix (42P01). DONE, validated (no regression).
- `f27d5fef9` **STATBUS-022** — one-shot kill inject `STATBUS_INJECT_KILL_AND_REMOVE_FILE` (atomic consume-gates-kill) + self-healing rewrite of `mid-migration-kill` + `between-migrations-kill`. DONE — **both scenarios GREEN on VMs** (one-time kill → 017 inline recovery re-runs migrate → completed).
- `cd2f5d51f` **6 mechanic harness fixes** — **4 GREEN** (drifted-unit, stage-b non-superuser pool, stage-e worker.tasks payload, worker-ddl-deadlock sibling INSERT); **2 still RED** (checkout-kill, mid-tx-kill — the mechanic's fix cleared one layer and exposed a deeper one).
- Filed STATBUS-024 (no `go test` in CI) and STATBUS-025 (6h-ceiling).

## Validation results (run 27306718138; full parse: `tmp/operator-comprehensive-27306718138.md`)
**24 PASS / 4 FAIL.** The 2 "cut-off" scenarios are the SKIP_DEFAULT 017 reproducers (never in the default suite) — **no coverage was lost**; all 28 default scenarios completed. The 4 reds (all harness, 0 product):
1. **2-preswap-checkout-kill** — `restoreGitState` path broken: working tree not restored to OLD (`cd2f5d51f` vs `50fd4325f`). The mechanic's binary-version fix landed but a deeper restoreGitState issue surfaced. → **STATBUS-026**.
2. **3-postswap-mid-tx-kill** — `assertions.sh:50` upgrade-row-state read fails (rc=1). Advanced past the new stall-detection (`wait_for_midtx_stall_ready`) to a later assertion failure. → **STATBUS-027**.
3. **4-rollback-kill** — two install timeouts + final rc=75 (restoreGitState abort). Pre-existing C9 multi-kill. → **STATBUS-028**.
4. **5-install-stage-a-killed-migrate** — seed restore `pg_restore` reported transaction rolled back (rc=1). Pre-existing; likely the same root as **STATBUS-018** (pg_restore --clean on sql_saga updatable-view triggers). → **STATBUS-029**.

Non-fatal: a recurring `WARN: freshness check failed: git diff exited 128` appears in PASSING scenarios only (data-helpers freshness check; non-blocking). Same `git diff 128` smell seen locally once — worth a glance but never fatal.

## STRUCTURAL BLOCKER for STABLE (not the cut): STATBUS-025
The serial 28-scenario suite runs ~6h, at GitHub's hard 360-min job ceiling. Run 27306718138 was CANCELLED at exactly 6h — but **during teardown, after all 28 scenarios completed** (no coverage lost this time). The problem: the WORKFLOW conclusion is `cancelled`, never `success`. The `release stable` gate (release.go:989) needs `install-recovery-harness` conclusion == `success` → **can never be met by the single-serial-job shape**. And it WORSENS as reds turn green (a passing scenario runs its full, slower convergence tail). Fix = **MATRIX** (fan scenarios across parallel jobs) or **BATCH**. Gates STABLE only; `SKIP_INSTALL_RECOVERY=1` (with the "harness/0-product" justification) is the documented bypass until the matrix lands.

## RC-readiness — the 3-stage gate model (`tmp/plans/architect-rc-readiness.md`)
- **CUT `./sb release prerelease`** = 12 gates, **ALL PASS now**: 5 coverage stamps at `cd2f5d51f` (fast-test 84/84, types, app-tsc, app-build, db-docs — all zero-diff), tree clean, on-master, up-to-date with origin, signed HEAD, `go build ./...`, migration immutability (no migrations touched), images green. **Harness reds do NOT block the cut.**
- **PROMOTE `./sb release stable`** = the 5 workflow gates incl install-recovery-harness green/SKIP — blocked by STATBUS-025 until matrix or SKIP.

## Open decisions for the King
1. **RATIFY STATBUS-017** (diff `584919285`) → then **cut the RC** (`ratify → ./sb release prerelease`). THE headline action.
2. **Review STATBUS-023 design** (`tmp/plans/architect-023-flag-fidelity-design.md`) — the clean flag-fidelity approach (Go fixture-generator on the CI runner, no production backdoor). King had rejected the earlier "hidden subcommand" idea as unclean.
3. **Decide STATBUS-025 approach** (matrix vs batch) — the path to a green install-recovery run for the stable promotion. Needs a cost nod (more concurrent CX23 VMs, each ~12min not ~6h).
4. **The 4 remaining harness reds** (026/027/028/029) — all harness, schedulable; none block the RC cut.

## Where everything is
- **Backlog tasks:** STATBUS-017 (ratify), 019/022 (Done), 023 (design review), 024 (go-test CI), 025 (6h matrix), 026/027/028/029 (the 4 reds), 021 (VM-script transport, underpins 026/028), 018 (pg_restore, underpins 029), 013/014/015 (older King scenario decisions).
- **Plans:** `tmp/plans/architect-rc-readiness.md`, `architect-023-flag-fidelity-design.md`, `architect-comprehensive-classification-27242482272.md`.
- **Validation parse:** `tmp/operator-comprehensive-27306718138.md`.
- **Run URLs:** validation **27306718138** (24/28, cancelled@6h); 017 proof GREEN **27241262390** / RED **27237385049**; prior comprehensive **27242482272** (19/28).
- **Team:** `statbus` team — foreman + architect/engineer (on-call, opus) + mechanic (sonnet) + tester/operator (haiku). All stood down or on-call.
- **Commits:** `751bae42c` (019), `f27d5fef9` (022), `cd2f5d51f` (mechanic harness) — all on master.
