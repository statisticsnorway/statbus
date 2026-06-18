---
id: doc-012
title: >-
  STATBUS-071 build-spec: real-upgrade-arc framework (branch fixtures +
  upgrade-arc-harness.yaml + clean-slate fingerprint)
type: specification
created_date: '2026-06-18 15:07'
updated_date: '2026-06-18 15:22'
tags:
  - upgrade
  - install-recovery
  - test-fidelity
  - architect-plan
  - phase-2
---
# STATBUS-071 build-spec — real-upgrade-arc framework

**Audience:** engineer (build), foreman (review). **Status:** implementable; the §7 topology decision is RESOLVED = Option 1 (amend-in-place). **Depends on:** STATBUS-086 (the register+schedule test driver), STATBUS-056 (image-wait), STATBUS-057 (image cleanup), STATBUS-072 (amend/re-stamp = behaviour under test), STATBUS-067 (canary built through this framework).

## 0. North Star
Stop FABRICATING crash states. Make the REAL system produce them via a real arc: **install A → upgrade to a defective B (fails) → service rolls back → upgrade to a fixed C (works)**. CENTERPIECE = **clean-slate-after-rollback**: B's rollback leaves the DB byte-identical to A so C applies clean — the one property no fabrication can prove. **Albania fidelity:** drive every upgrade through the `public.upgrade` scheduling row (the web-UI mechanism), assert the box applies+recovers **autonomously** — no SSH rescue.

## 1. The test driver = STATBUS-086 (NOT fabrication)
Every arc schedules the real way: on the VM, `git fetch` the target commit, then `./sb upgrade register <commit>` (resolve + upsert state='available'; service prepares — image pull + verifyArtifacts→ready, service.go:1101+) → `./sb upgrade schedule <commit>` (promote to 'scheduled' → DB trigger `upgrade_notify_daemon_trigger` fires NOTIFY upgrade_apply, service.go:3408 → service runs `executeScheduled`, service.go:3487). NEVER `fabricate_scheduled_upgrade_row` (deleted in 086), NEVER a deploy-branch pointer, NEVER `./sb install`.

## 2. (a) images.yaml `test/**` push-trigger — ONE LINE
`.github/workflows/images.yaml`, push trigger:
```yaml
branches: [master]              # BEFORE
branches: [master, 'test/**']   # AFTER
```
Effect: pushing any `test/*` branch builds the per-commit images (`statbus-{app,worker,db,proxy}:<commit_short>`) tagged by `git rev-parse --short=8` — content-unique, so throwaway commits CANNOT collide with master's images. GUARD: `test/**` images are commit_short-tagged only (no `v*` release tags — images.yaml has no tag trigger), so they never enter the release path; image-cleanup GC + the explicit teardown (§5) remove them. Verify with one throwaway push before building anything else.

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
- **working** (re-stamp / Albania, the FIRST scenario = STATBUS-072): B's `V` is a trivial migration that **SUCCEEDS** (e.g. `ALTER TABLE … ADD COLUMN`), recorded in `db.migration` with content-hash `H_B`. C amends V → bytes change → hash `H_C ≠ H_B`, SAME version V. The arc forces the re-stamp path: a box at B (V applied, H_B recorded) upgrades to C where on-disk hash H_C ≠ recorded H_B → STATBUS-072's content-hash sweep must re-record/re-stamp **autonomously** without crashing (and self-recover if it does). This is a B-succeeds-then-C-amends arc (re-stamp, the MANY) — NOT a fail→rollback arc, so it does NOT carry the clean-slate assertion.
- **hanging** (the canonical Shape-1 fail→rollback arc + clean-slate centerpiece): B's `V` FAILS every apply — two sub-variants: (i) **crash/error** — V raises (e.g. a deterministic `RAISE EXCEPTION` or a constraint violation) → rollback every time; (ii) **too-long/OOM** — V is data-size dependent (works-for-most): runs fast on small demo data, exceeds the 60-min ceiling (migrate.go:420) or OOMs on large data. RUN this variant at BOTH data sizes to manufacture the works-for-most split (small=succeeds, large=fails) naturally. C fixes V so it completes (the FEW re-run the now-correct/fast V).

## 5. (b cont.) upgrade-arc-harness.yaml — the four jobs
NEW `.github/workflows/upgrade-arc-harness.yaml`, sibling to `install-recovery-harness.yaml`, REUSING its image-wait + cleanup patterns. TRIGGER: `workflow_dispatch` (inputs: `base_sha` [default caller SHA], `scenario` [working|hanging|…]). The tester fires it (single serializer).

- **JOB 1 — construct** (ubuntu, `contents:write` token): resolve A=base_sha; create B + C as REAL commits in git ancestry off A (push `test/<scenario>-migration[-run_id]` then `test/<scenario>-fixed-migration[-run_id]`); emit `B_short`, `C_short` as outputs. The "fix" step in building C = edit V in place (§7 Option 1).
- **JOB 2 — image-wait** (REUSE STATBUS-056): replicate `install-recovery-harness.yaml:169-220` ghcr poll, parameterized to wait for ALL FOUR images at BOTH `B_short` AND `C_short` (bounded budget; fail loud with the same "images built only by images.yaml" diagnostic). A's images assumed present.
- **JOB 3 — run-arc** (Hetzner VM; mirror harness VM bootstrap + EXIT-trap teardown). Drive via the Albania mechanism (register+schedule, §1):
  1. Install A at base_sha (existing `bootstrap_install_test_vm` + `install_statbus_in_vm`); health-check.
  2. `populate_with_demo_data` → capture A-FINGERPRINT (§6).
  3. Upgrade → B: on the VM `git fetch B_full`; `./sb upgrade register B_full` (wait status→ready); `./sb upgrade schedule B_full`. The systemd upgrade service applies it autonomously.
  4. Wait for B's terminal row state. **hanging:** assert terminal = rolled_back/failed AND the box auto-recovered (service-only; no SSH rescue). **working:** assert B completes (V applied).
  5. CENTERPIECE (hanging only): re-capture fingerprint, assert == A-FINGERPRINT byte-identical (§6).
  6. Upgrade → C (same register+schedule, C_full). **hanging:** V unrecorded after rollback → C's V(fixed) applies fresh, no content-hash conflict. **working:** C amends an applied V → re-stamp path (STATBUS-072).
  7. Assert: C completes, DB at C, schema reflects V(fixed), data intact, box healthy — all autonomous.
- **JOB 4 — teardown** (STATBUS-057; `if: always()`): delete the two `test/*` branches; delete B,C images by commit_short (ghcr delete API — operator confirms exact API/permission); VM EXIT-trap reaps the Hetzner instance; defensive periodic orphan sweep deletes `throwaway-*` tags older than N hours (commit_short uniqueness guarantees it can't touch master/release images).

## 6. (d) Clean-slate-after-rollback fingerprint (the centerpiece)
A DB FINGERPRINT captured after install-A and re-captured after B's rollback; assert byte-identical, EACH dimension reported separately so a mismatch names what drifted. Run via `./sb psql`, sha256 each:
1. **SCHEMA**: `pg_dump --schema-only --no-owner --no-privileges`, normalized (strip dump-version header / volatile comments), sha256. Catches residual schema B added that rollback failed to undo.
2. **MIGRATION LEDGER**: `SELECT version, <content-hash col> FROM db.migration ORDER BY version` → sha256. Catches a residual applied/recorded V (the unrecorded-after-rollback property).
3. **DATA**: extend `snapshot_demo_data_counts` to a per-table `md5(array_agg(t.* ORDER BY pk))` over the key tables → sha256. Catches data drift / partial B writes.
Build on existing primitives: `snapshot_demo_data_counts` (counts) + `assert_db_migration_max_version` (ledger max) — ELEVATE both to full fingerprints. This is the property no fabrication can prove — a synthetic "rollback" can't show it restored EXACTLY A; a real B-rollback must.

## 7. (b cont.) `*-fixed` topology — RESOLVED = Option 1 (edit V in place + re-stamp)
**RESOLVED** (foreman per STATBUS-091 autonomy, 2026-06-18; King may revisit on return): **Option 1 — C EDITS V's `.up.sql` in place** (same version V, corrected/amended bytes → content-hash H_C ≠ H_B). JOB-1's "fix" step edits the migration FILE, not adds a new one. Rationale: it is the King-ratified STATBUS-072 mechanism, and Option 2 cannot rescue the FEW-who-failed (see below) without collapsing to Option 1 or building a new mechanism. Recorded in STATBUS-091 for the King's review.

Decision record (why Option 1, for the engineer + the King's later review):
- **Option 1 — EDIT V IN PLACE (chosen).** The FEW (failed at V): V unrecorded → C's V(fixed) applies fresh. The MANY (succeeded at V): recorded H_B ≠ on-disk H_C → re-stamp re-records without re-running. Depth-independent, outcome-preserving, ledger stays at V (no phantom forward version). Cost: edits an already-released "immutable" migration.
- **Option 2 — ADD FORWARD V+k (NOT chosen).** C adds a NEW migration V+k; V untouched. Respects immutability / append-only ledger. **But it does NOT rescue the FEW** — an immutable broken/too-slow V stays unapplied → the runner re-runs the ORIGINAL V → fails AGAIN, unless V is ALSO amended (→ collapses to Option 1) OR a NEW "supersede-skip" mechanism lets the runner skip V because V+k supersedes it (does not exist today). It also leaves the broken V in the tree, re-failing on any fresh install. If the King later mandates Option 2, JOB-1's fix step changes from "edit V" to "add V+k" AND a supersede-skip path becomes a new prerequisite dependency.

## 8. (f) Inject-on-real-upgrade for the kill arcs
The process-death micro-window scenarios (lost-stamp, resume-death, rollback-kill, mid-migration/mid-tx/between kills) STAY INJECT — branch arcs can't reproduce a kill at an exact instruction. But they now run ON TOP of a real register+schedule arc instead of a fabricated row: drive the upgrade via §1, and fire the existing inject at the precise migrate.go window. Inject sites (migrate.go): `:388` during-migration, `:436-438` mid-tx, `:911` between-migrations, 60-min ceiling `:420`. The kill arcs (Shape catalogue, build-order step 5 — e.g. recovery-of-recovery: kill during B's rollback) layer the inject env onto JOB-3's real-arc drive; the service's `executeScheduled`→migrate path then hits the injected kill. This keeps the SCHEDULING real (no fabrication) while preserving precise kill timing.

## 9. (e) Build order + dependencies
1. **(a)** images.yaml `test/**` trigger (1 line) — unlocks throwaway images. Verify with a throwaway push.
2. **(b) skeleton:** construct → image-wait → no-op arc → teardown. Prove the branch/image lifecycle + teardown leaves NO orphan branches/images BEFORE running real arcs.
3. **(c) FIRST scenario:** working→working-fixed (amend/Albania, re-stamp) end-to-end — the opener; exercises STATBUS-072.
4. **(d) fingerprint + SECOND scenario:** hanging→hanging-fixed (fail→rollback→fix) — the clean-slate centerpiece.
5. **Shape catalogue:** too-long/OOM at both data sizes, recovery-of-recovery (kill during B's rollback, §8), canary-through-framework.
6. **(future, separate design)** silent-wrong-data: install A → known data → corrupting B → invariant-check detects.

DEPENDENCIES: STATBUS-056 (image-wait, hard dep for JOB 2); STATBUS-057 (teardown image-delete + orphan sweep; operator confirms ghcr delete API + token permission); STATBUS-072 (re-stamp policy — the FIRST scenario IS this case, behaviour under test); STATBUS-067 (build the canary THROUGH this framework — and per its Q1-reachability finding the canary MUST drive recovery via the systemd upgrade-service restart: boot-migrate-up fails → STATBUS-017 defers → resumePostSwap → canary → Q1; `./sb install` crashed-recovery rolls back at its own migrate-up BEFORE the canary, so Q1 is NOT exercised that way).

## 10. Risks / decisions for the engineer
- **Token:** JOB-1 branch push needs `contents:write` (images.yaml currently only `packages:write`); JOB-4 needs branch+image delete permission.
- **C-fix is load-bearing (Option 1):** the construct job must EDIT the migration FILE, not add a new one — an additive fix-on-top re-runs V_broken → fails again.
- **Teardown must be `if: always()` + idempotent:** a failed arc must still delete its branches + images or orphans accumulate (STATBUS-057 cleanup-trap discipline the VM harness already enforces).
- **Albania fidelity is the whole point:** drive via the `public.upgrade` row + the systemd service, NEVER `./sb install` or a deploy-branch move (those are operator/cloud paths; they'd test the wrong thing).
