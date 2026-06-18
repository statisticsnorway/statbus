---
id: doc-012
title: >-
  STATBUS-071 build-spec: real-upgrade-arc framework (branch fixtures +
  upgrade-arc-harness.yaml + clean-slate fingerprint)
type: specification
created_date: '2026-06-18 15:07'
updated_date: '2026-06-18 17:16'
tags:
  - upgrade
  - install-recovery
  - test-fidelity
  - architect-plan
  - phase-2
---
# STATBUS-071 build-spec — real-upgrade-arc framework

**Audience:** engineer (build), foreman (review). **Status:** implementable; §7 topology RESOLVED = Option 1; §2 image-trigger Q1 RESOLVED = explicit dispatch. **Depends on:** STATBUS-086 (the register+schedule test driver — DONE), STATBUS-056 (image-wait), STATBUS-057 (image cleanup), STATBUS-072 (amend/re-stamp = behaviour under test — DONE), STATBUS-067 (canary built through this framework).

## 0. North Star
Stop FABRICATING crash states. Make the REAL system produce them via a real arc: **install A → upgrade to a defective B (fails) → service rolls back → upgrade to a fixed C (works)**. CENTERPIECE = **clean-slate-after-rollback**: B's rollback leaves the DB byte-identical to A so C applies clean — the one property no fabrication can prove. **Albania fidelity:** drive every upgrade through the `public.upgrade` scheduling row (the web-UI mechanism), assert the box applies+recovers **autonomously** — no SSH rescue.

## 1. The test driver = STATBUS-086 (NOT fabrication)
Every ARC schedules the real way: on the VM, `git fetch` the target commit, then `./sb upgrade register <commit>` (resolve + upsert state='available'; service prepares — image pull + verifyArtifacts→ready, service.go:1101+) → `./sb upgrade schedule <commit>` (promote to 'scheduled' → DB trigger `upgrade_notify_daemon_trigger` fires NOTIFY upgrade_apply, service.go:3408 → service runs `executeScheduled`, service.go:3487). NEVER a deploy-branch pointer, NEVER `./sb install` for the ARCs. (register+schedule require a POST-086 baseline; the legacy v2026.05.2-baseline kill scenarios keep `fabricate_scheduled_upgrade_row` until 071 reshapes them onto post-086 baselines — see §8.)

## 2. (a) Per-commit images for test/* branches — EXPLICIT DISPATCH (Q1 RESOLVED)
**THE TRIGGER PROBLEM (STATBUS-071 Q1):** JOB-1 pushes test/* branches via GITHUB_TOKEN, and **a GITHUB_TOKEN push does NOT trigger downstream workflows** (GitHub loop-prevention). So adding a `test/**` PUSH trigger to images.yaml would NOT fire for the CI arc → JOB-2's image-wait would hang the whole arc.

**SOLUTION (verified, perms-minimal, NO PAT):** JOB-1 EXPLICITLY dispatches images.yaml after pushing each branch: `gh workflow run images.yaml --ref <branch>`. images.yaml is **UNCHANGED** — it already has `workflow_dispatch` (images.yaml:24, no path/tag filter), and its `describe` job checks out the dispatched ref + computes `commit_short = git rev-parse --short=8 HEAD` (images.yaml:49) → the build matrix tags all images `statbus-{app,worker,db,proxy,sb}:<commit_short>` + seed for THAT ref's commit (images.yaml:104 / manifest :133 / seed :173). VERIFIED in code: dispatch-by-ref builds the dispatched branch's commit images (the `describe`→`build`→`manifest` chain is keyed entirely on the checked-out ref's commit_short). The operator confirmed `gh workflow run --ref` dispatches to arbitrary branches with GITHUB_TOKEN.

**PERMISSIONS:** JOB-1 needs `contents: write` (push test/*) + `actions: write` (the `gh workflow run` / workflow-dispatch API requires actions:write). GITHUB_TOKEN suffices — **NO PAT** (rejected option (a): a PAT is a long-lived, broad, rotation-burdened credential; the explicit dispatch is perms-minimal and ephemeral-token-only).

**The `test/**` PUSH trigger is NOT added** — it wouldn't fire for GITHUB_TOKEN pushes (the Q1 blocker) and is unnecessary given the dispatch. (Optional, non-load-bearing: a human iterating locally can also just `gh workflow run images.yaml --ref test/<their-branch>`.) GUARD unchanged: images are commit_short-tagged only (no `v*` tags), so test images never enter the release path; teardown (§5 JOB-4) + the weekly image-GC reap them.

## 3. (b) Branch fixtures — exact names + what each commit carries
Flat sibling scheme (git-valid; the King's naming). `A` = the SHA-under-test (its image is master's / the SHA's, already built):
```
test/base                  = A itself (no separate branch; A's image already exists)
test/working-migration         → test/working-fixed-migration   (V SUCCEEDS, then amended → re-stamp arc)
test/hanging-migration         → test/hanging-fixed-migration    (V fails/hangs, then fixed → rollback→re-run arc)
```
- **B (`test/<scenario>-migration`)** branches off A, adds ONE real migration file `V` (a genuine `migrations/<ts>_<desc>.up.sql` + `.down.sql`). The DEFECT lives in V (see §4).
- **C (`test/<scenario>-fixed-migration`)** branches off B and applies the FIX. Fix topology RESOLVED = Option 1 (edit V in place + re-stamp; see §7).
- Concurrency: the tester serializes runs, but suffix branch names with the run id (`test/<scenario>-migration-<run_id>`) and multi-tag throwaway images `throwaway-<run_id>` for the orphan sweep. commit_short already makes images content-unique; the run-id suffix only de-collides branch names across overlapping runs.

## 4. (c) The migration fixtures each branch carries
- **working** (re-stamp / Albania, the FIRST scenario = STATBUS-072): B's `V` is a trivial migration that **SUCCEEDS** (e.g. `ALTER TABLE … ADD COLUMN`), recorded in `db.migration` with content-hash `H_B`. C amends V → bytes change → hash `H_C ≠ H_B`, SAME version V. The arc forces the re-stamp path: a box at B (V applied, H_B recorded) upgrades to C where on-disk hash H_C ≠ recorded H_B → STATBUS-072's content-hash sweep re-stamps **autonomously** (the amendments.tsv conveyance, shipped) without crashing. This is a B-succeeds-then-C-amends arc (re-stamp, the MANY) — NOT a fail→rollback arc, so it does NOT carry the clean-slate assertion.
- **hanging** (the canonical Shape-1 fail→rollback arc + clean-slate centerpiece): B's `V` FAILS every apply — two sub-variants: (i) **crash/error** — V raises (e.g. a deterministic `RAISE EXCEPTION` or a constraint violation) → rollback every time; (ii) **too-long/OOM** — V is data-size dependent (works-for-most): runs fast on small demo data, exceeds the 60-min ceiling (migrate.go:420) or OOMs on large data. RUN this variant at BOTH data sizes to manufacture the works-for-most split (small=succeeds, large=fails) naturally. C fixes V so it completes (the FEW re-run the now-correct/fast V).

## 5. (b cont.) upgrade-arc-harness.yaml — the four jobs
NEW `.github/workflows/upgrade-arc-harness.yaml`, sibling to `install-recovery-harness.yaml`, REUSING its image-wait + cleanup patterns. TRIGGER: `workflow_dispatch` (inputs: `base_sha` [default caller SHA], `scenario` [working|hanging|…]). The tester fires it (single serializer).

- **JOB 1 — construct** (ubuntu; permissions `contents: write` + `actions: write`): resolve A=base_sha; create B + C as REAL commits in git ancestry off A; push `test/<scenario>-migration[-run_id]` then `test/<scenario>-fixed-migration[-run_id]` via GITHUB_TOKEN; **then for EACH pushed branch `gh workflow run images.yaml --ref <branch>`** to build its per-commit images (the Q1 explicit dispatch, §2 — GITHUB_TOKEN pushes don't auto-trigger images.yaml). Emit `B_short`, `C_short` as outputs. The "fix" step in building C = edit V in place (§7 Option 1).
- **JOB 2 — image-wait** (REUSE STATBUS-056): replicate `install-recovery-harness.yaml:169-220` ghcr poll, parameterized to wait for ALL FOUR images at BOTH `B_short` AND `C_short` (bounded budget; fail loud with the same "images built only by images.yaml" diagnostic). A's images assumed present.
- **JOB 3 — run-arc** (Hetzner VM; mirror harness VM bootstrap + EXIT-trap teardown). Drive via the Albania mechanism (register+schedule, §1):
  1. Install A at base_sha (existing `bootstrap_install_test_vm` + `install_statbus_in_vm`); health-check.
  2. `populate_with_demo_data` → capture A-FINGERPRINT (§6).
  3. Upgrade → B: on the VM `git fetch B_full`; `./sb upgrade register B_full` (wait status→ready); `./sb upgrade schedule B_full`. The systemd upgrade service applies it autonomously.
  4. Wait for B's terminal row state. **hanging:** assert terminal = rolled_back/failed AND the box auto-recovered (service-only; no SSH rescue). **working:** assert B completes (V applied).
  5. CENTERPIECE (hanging only): re-capture fingerprint, assert == A-FINGERPRINT byte-identical (§6).
  6. Upgrade → C (same register+schedule, C_full). **hanging:** V unrecorded after rollback → C's V(fixed) applies fresh, no content-hash conflict. **working:** C amends an applied V → re-stamp path (STATBUS-072, amendments.tsv).
  7. Assert: C completes, DB at C, schema reflects V(fixed), data intact, box healthy — all autonomous.
- **JOB 4 — teardown** (STATBUS-057; `if: always()`; permissions `contents: write`): delete the two `test/*` branches; image-delete is DEFERRED to the weekly image-GC (Q2 approved) — commit_short uniqueness guarantees orphan test images can't touch master/release images, so the GC reaps them (no per-run image-delete permission needed). VM EXIT-trap reaps the Hetzner instance.

## 6. (d) Clean-slate-after-rollback fingerprint (the centerpiece)
A DB FINGERPRINT captured after install-A and re-captured after B's rollback; assert byte-identical, EACH dimension reported separately so a mismatch names what drifted. Run via `./sb psql`, sha256 each:
1. **SCHEMA**: `pg_dump --schema-only --no-owner --no-privileges`, normalized (strip dump-version header / volatile comments), sha256. Catches residual schema B added that rollback failed to undo.
2. **MIGRATION LEDGER**: `SELECT version, <content-hash col> FROM db.migration ORDER BY version` → sha256. Catches a residual applied/recorded V (the unrecorded-after-rollback property).
3. **DATA**: extend `snapshot_demo_data_counts` to a per-table `md5(array_agg(t.* ORDER BY pk))` over the key tables → sha256. Catches data drift / partial B writes.
Build on existing primitives: `snapshot_demo_data_counts` (counts) + `assert_db_migration_max_version` (ledger max) — ELEVATE both to full fingerprints. This is the property no fabrication can prove — a synthetic "rollback" can't show it restored EXACTLY A; a real B-rollback must.

## 7. (b cont.) `*-fixed` topology — RESOLVED = Option 1 (edit V in place + re-stamp)
**RESOLVED** (foreman per STATBUS-091 autonomy, 2026-06-18; King may revisit on return): **Option 1 — C EDITS V's `.up.sql` in place** (same version V, corrected/amended bytes → content-hash H_C ≠ H_B). JOB-1's "fix" step edits the migration FILE, not adds a new one. Rationale: it is the King-ratified STATBUS-072 mechanism (the amendments.tsv conveyance, now shipped), and Option 2 cannot rescue the FEW-who-failed without collapsing to Option 1 or building a new mechanism. Recorded in STATBUS-091 for the King's review.

Decision record (why Option 1):
- **Option 1 — EDIT V IN PLACE (chosen).** The FEW (failed at V): V unrecorded → C's V(fixed) applies fresh. The MANY (succeeded at V): recorded H_B ≠ on-disk H_C → re-stamp re-records without re-running (declared in migrations/amendments.tsv → eagerContentHashCheck re-stamps; STATBUS-072 shipped). Depth-independent, outcome-preserving. Cost: edits an already-released "immutable" migration (sanctioned via the amendments.tsv declaration).
- **Option 2 — ADD FORWARD V+k (NOT chosen).** Respects immutability but does NOT rescue the FEW (the immutable broken V re-runs → fails again) without also amending V (→ Option 1) or a new supersede-skip mechanism.

## 8. (f) The kill scenarios — fabricate STAYS in 086-era, retired in 071 (086 is the ENABLER)
**ARCHITECTURAL THROUGH-LINE:** 086's `RunSchedule` is a **lock-free CLI one-shot that SETS a 'scheduled' row WITHOUT running it** → a persistent **daemon-DOWN 'scheduled' row** — exactly what the kill scenarios consume (`./sb install` inline-dispatch + `STATBUS_INJECT_AT`), and exactly what `fabricate_scheduled_upgrade_row` fakes today. v2026.05.2 has no such verb (its schedule-write is daemon-side + self-running). So **086 IS THE ENABLER** for retiring fabricate; the retirement is gated on the capability 086 introduced, not deferred arbitrarily.

**THE KILL MECHANISM:** the process-death micro-window scenarios STAY INJECT — each needs a daemon-DOWN `public.upgrade` 'scheduled' row that `./sb install` inline-dispatches WITH `STATBUS_INJECT_AT` set (verified: `2-preswap-binary-swap-kill.sh:123-136` = `fabricate_scheduled_upgrade_row` + `./sb install`). The DAEMON must NOT run it.

**WHY fabricate can't be retired on the v2026.05.2 baseline** (verified at the tag): v2026.05.2's CLI `apply` only UPDATEs a discovered row; the insert-if-missing lives in the SERVICE's `scheduleImmediate`, and the v2026.05.2 daemon runs `handleNotification`→`executeScheduled` SYNCHRONOUSLY in one notifyCh iteration (service.go @ tag ~1574) — so daemon-up `apply` self-runs immediately (no daemon-down window, daemon is dispatcher → no injection) and daemon-down `apply` creates nothing. fabricate STAYS for the ~18 v2026.05.2 kill scenarios.

**HOW 071 retires fabricate:** on a POST-086 baseline, `git fetch` → `./sb upgrade register` → `./sb upgrade schedule` (RunSchedule, daemon down) leaves the persistent daemon-down 'scheduled' row → `./sb install` injects. 071 reshapes the kill scenarios onto post-086 baselines, then DELETES fabricate.

Inject sites unchanged (migrate.go): `:388` during-migration, `:436-438` mid-tx, `:911` between-migrations, 60-min ceiling `:420`.

## 9. (e) Build order + dependencies
1. **(a)** the Q1 explicit-dispatch wiring in JOB-1 (§2) — no images.yaml change needed. Verify with one throwaway construct→dispatch→image-wait cycle.
2. **(b) skeleton:** construct → image-wait → no-op arc → teardown. Prove the branch/image lifecycle + teardown leaves NO orphan branches BEFORE running real arcs.
3. **(c) FIRST scenario:** working→working-fixed (amend/Albania, re-stamp) end-to-end — the opener; exercises STATBUS-072 (shipped).
4. **(d) fingerprint + SECOND scenario:** hanging→hanging-fixed (fail→rollback→fix) — the clean-slate centerpiece.
5. **Shape catalogue:** too-long/OOM at both data sizes, recovery-of-recovery (kill during B's rollback, §8), canary-through-framework; reshape the legacy kill scenarios onto post-086 baselines (register+schedule) + delete fabricate.
6. **(future, separate design)** silent-wrong-data: install A → known data → corrupting B → invariant-check detects.

DEPENDENCIES: STATBUS-056 (image-wait, hard dep for JOB 2); STATBUS-057 (teardown — branch-delete now; image-GC is the weekly sweep, Q2); STATBUS-072 (re-stamp policy — SHIPPED via amendments.tsv); STATBUS-067 (canary THROUGH this framework — its Q1-reachability finding: drive recovery via the systemd upgrade-service restart, not `./sb install` crashed-recovery which rolls back before the canary).

## 10. Risks / decisions for the engineer
- **Token (Q1 RESOLVED, no PAT):** JOB-1 = `contents: write` (push test/*) + `actions: write` (`gh workflow run` to dispatch images.yaml — §2). JOB-4 = `contents: write` (delete test/* branches); image-delete DEFERRED to the weekly image-GC (Q2). No PAT anywhere.
- **C-fix is load-bearing (Option 1):** the construct job must EDIT the migration FILE + add the amendments.tsv row, not add a new migration — an additive fix-on-top re-runs V_broken → fails again.
- **Teardown must be `if: always()` + idempotent:** a failed arc must still delete its branches (orphan test images are reaped by the weekly GC — commit_short uniqueness protects master/release images).
- **Albania fidelity is the whole point:** drive the ARCs via the `public.upgrade` row + the systemd service, NEVER `./sb install` or a deploy-branch move. (The kill scenarios are the exception — they intentionally use `./sb install` inline-dispatch for precise injection; see §8.)
