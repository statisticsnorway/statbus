---
id: doc-012
title: >-
  STATBUS-071 build-spec: real-upgrade-arc framework (branch fixtures +
  upgrade-arc-harness.yaml + clean-slate fingerprint)
type: specification
created_date: '2026-06-18 15:07'
updated_date: '2026-06-18 18:29'
tags:
  - upgrade
  - install-recovery
  - test-fidelity
  - architect-plan
  - phase-2
---
# STATBUS-071 build-spec — real-upgrade-arc framework

**Audience:** engineer (build), foreman (review). **Status:** implementable; §7 topology=Option 1; §2 image-trigger Q1=explicit dispatch; §5 install-A=install_statbus_at_sha; §4/§6 (c)+(d) settled. **Depends on:** STATBUS-086 (register+schedule driver — DONE), STATBUS-056 (image-wait), STATBUS-057 (image cleanup), STATBUS-072 (amend/re-stamp — DONE), STATBUS-067 (canary through this framework).

## 0. North Star
Stop FABRICATING crash states. Make the REAL system produce them via a real arc: **install A → upgrade to a defective B (fails) → service rolls back → upgrade to a fixed C (works)**. CENTERPIECE = **clean-slate-after-rollback**: B's rollback leaves the DB byte-identical to A so C applies clean — the one property no fabrication can prove. **Albania fidelity:** drive every upgrade through the `public.upgrade` scheduling row (the web-UI mechanism), assert the box applies+recovers **autonomously** — no SSH rescue.

## 1. The test driver = STATBUS-086 (NOT fabrication)
Every ARC schedules the real way: on the VM, `git fetch` the target commit, then `./sb upgrade register <commit>` (resolve + upsert state='available'; service prepares — image pull + verifyArtifacts→ready, service.go:1101+) → `./sb upgrade schedule <commit>` (promote to 'scheduled' → DB trigger fires NOTIFY upgrade_apply, service.go:3408 → service runs `executeScheduled`, service.go:3487). NEVER a deploy-branch pointer, NEVER `./sb install` for the upgrade STEPS. (register+schedule require a POST-086 baseline — incl. A itself; see §5 install-A. The legacy v2026.05.2-baseline kill scenarios keep `fabricate_scheduled_upgrade_row` until 071 reshapes them — see §8.)

## 2. (a) Per-commit images for test/* branches — EXPLICIT DISPATCH (Q1 RESOLVED)
**THE TRIGGER PROBLEM (Q1):** a GITHUB_TOKEN push does NOT trigger downstream workflows (GitHub loop-prevention) → a `test/**` PUSH trigger on images.yaml would NOT fire for the CI arc.
**SOLUTION (no PAT):** JOB-1 EXPLICITLY dispatches images.yaml per branch: `gh workflow run images.yaml --ref <branch>` (with a ~5×/5s RETRY — ref propagation is eventually-consistent, so a just-pushed ref can transiently 404). images.yaml is UNCHANGED — `workflow_dispatch` (:24), `describe` computes `commit_short` from the dispatched ref (:49), build/manifest/seed tag all images by it (:104/:133/:173).
**PERMISSIONS:** JOB-1 `contents: write` + `actions: write` (workflow-dispatch API). GITHUB_TOKEN suffices — NO PAT.

## 3. (b) Branch fixtures — exact names + what each commit carries
Flat sibling scheme (git-valid). `A` = the SHA-under-test (its images built on master push):
```
test/base                  = A itself
test/working-migration         → test/working-fixed-migration   (V SUCCEEDS, then amended → re-stamp arc; (c))
test/failing-migration         → test/failing-fixed-migration   (V crashes, then fixed → fail→rollback→fresh arc; (d))
```
- **B (`test/<scenario>-migration`)** off A, adds ONE real migration `V` (`migrations/<ts>_<desc>.up.sql` + `.down.sql`). The DEFECT lives in V (§4).
- **C (`test/<scenario>-fixed-migration`)** off B, applies the FIX (§7 Option-1: edit V in place).
- Concurrency: branch names suffixed with the run id (`…-<run_id>`); images content-unique by commit_short. The run-id suffix de-collides branch names across overlapping runs.

## 4. (c)/(d) The migration fixtures each branch carries
- **working** (re-stamp / Albania, STATBUS-072 — increment (c)): B's V SUCCEEDS (CREATE TABLE + INSERT; content-hash H_B). C amends V IN PLACE (bytes→H_C≠H_B, RESULT identical) + declares V in `migrations/amendments.tsv` → the B→C upgrade RE-STAMPS autonomously (the MANY who already succeeded). NOT a fail→rollback arc → no clean-slate assertion.
- **failing** (crash/error fail→rollback→fix + the clean-slate centerpiece — increment (d)): B's V is a DETERMINISTIC error (`DO $$ BEGIN RAISE EXCEPTION '…' END $$;`, `.down`=no-op) → `./sb migrate up` fails → postSwapFailure → recoveryRollback → row='rolled_back'. C edits V in place → the working migration → V applies **FRESH** (V_fail rolled back → unrecorded in db.migration → NO amendments.tsv, NO re-stamp). The FEW who failed. Carries the clean-slate fingerprint (§6).
- **hanging** (too-long/watchdog fail→rollback — LATER, §9 shape catalogue): V is data-size-dependent (works-for-most): fast on small data, exceeds the 60-min ceiling (migrate.go:420) / OOM on large data. Run at BOTH data sizes to manufacture the works-for-most split. (Naming: **failing**=crash/error (d); **hanging**=too-long/watchdog — distinct mechanisms; supersedes doc's earlier conflated 'hanging'.)

## 5. (b cont.) upgrade-arc-harness.yaml — the four jobs
NEW `.github/workflows/upgrade-arc-harness.yaml`, sibling to `install-recovery-harness.yaml`. TRIGGER: `workflow_dispatch` (inputs: `base_sha`, `scenario` [working|failing]). Single serializer; concurrency cancel-in-progress:false (avoid orphan-on-cancel).

- **JOB 1 — construct** (`contents: write` + `actions: write`): create B + C off A; push `test/<scenario>-migration[-run_id]` + `…-fixed-migration[-run_id]` via GITHUB_TOKEN; **then `gh workflow run images.yaml --ref <branch>` per branch (with the §2 retry)**. Emit `base_short`, `b_short`/`c_short`, `b_full`/`c_full`, `v_version`. C's fix = edit V in place (§7).
- **JOB 2 — image-wait** (REUSE STATBUS-056): poll ghcr until ALL images — `app worker db proxy sb` — exist at base_short AND b_short AND c_short. (`sb` is needed: install_statbus_at_sha + the daemon's buildBinaryOnDisk→ProcureShort pull it; base_short gates the install-A race.) ≈40m budget, fail loud.
- **JOB 3 — run-arc** (Hetzner VM; mirror harness bootstrap + EXIT-trap teardown; **set `HCLOUD_NAME_PREFIX=statbus-arc-` in this job's env** — the shared `_check_name_safety` guard defaults to `statbus-recovery-` and rejects the arc's `statbus-arc-*` names otherwise). Drive via register+schedule (§1):
  1. **Install A=base_sha via `install_statbus_at_sha <vm> <base_sha>`** — edge-install PINNED to base_sha (git fetch+checkout <sha> → toolchain-free procure statbus-sb:<base_short> via docker pull/create/cp → cp env-config/users → `./sb install`). DETERMINISTIC + post-086, DISJOINT from `install_statbus_in_vm` (which CAN'T install an arbitrary post-086 SHA — empty=master-HEAD drifts, release-tags pre-086). Fresh install → rc=0 (rc=75 is the upgrade-rollback path, not taken). Precondition: A's images (4 services + sb) at base_short. Health-check.
  2. `populate_with_demo_data` → capture A-FINGERPRINT (§6).
  3. Upgrade → B (register+schedule, daemon-autonomous). Per scenario: **failing** → assert terminal='rolled_back' + box auto-recovered (no SSH rescue); **working** → 'completed' (V applied).
  4. CENTERPIECE (failing only): re-capture fingerprint, assert == A-FINGERPRINT byte-identical (§6).
  5. Upgrade → C (register+schedule). **failing:** V unrecorded → C's V(fixed) applies FRESH. **working:** C amends an applied V → re-stamp (amendments.tsv).
  6. Assert: C completes, DB at C, schema reflects V(fixed), data intact, healthy — all autonomous.
- **JOB 4 — teardown** (`if: always()`; `contents: write`): delete the two `test/*` branches (RECOMPUTE names from scenario+run_id so it works even on partial construct failure; ls-remote-guarded, best-effort, exit 0). image-delete DEFERRED to the weekly image-GC (Q2). VM EXIT-trap (+ an if:always() net hcloud-delete) reaps the instance.

## 6. (d) Clean-slate-after-rollback fingerprint (the centerpiece)
Capture after install-A+populate, re-capture after B's rollback; assert byte-identical, EACH dim reported separately. **DETERMINISM is make-or-break — a false mismatch on a CLEAN rollback = a flaky red:**
1. **SCHEMA**: `pg_dump --schema-only --no-owner --no-privileges` (docker exec the db container) → strip the volatile preamble (`-- Dumped …` + version-comment lines) + normalize blank-line/trailing-WS → sha256. Byte-stable for two captures on the SAME box (SET preamble + object ordering are deterministic; the snapshot restore makes the schema identical). pg_dump (NOT an information_schema digest) is the gold standard — catches function/trigger/policy residue.
2. **LEDGER**: `SELECT version, content_hash FROM db.migration ORDER BY version` → sha256. (version+content_hash ONLY — exclude duration_ms/applied_at.) Post-rollback == post-A (V_fail unrecorded).
3. **DATA**: per-table `md5(coalesce(string_agg(t::text,'|' ORDER BY t::text),''))` → sha256, scoped to the demo **BASE** tables (legal_unit, establishment) — NOT a full-DB digest. CRITICAL: EXCLUDE infra tables (public.upgrade gets a 'rolled_back' B-row post-rollback; worker.*; db.migration; auth.*) that legitimately differ. **v1 = NON-DERIVED base tables only** — the DERIVED tables (statistical_unit, statistical_history) are worker-COMPUTED and match post-rollback only if derivation is quiescent at snapshot time AND no re-derivation runs before the re-capture; base suffices (derived = f(base)). Adding derived + a worker-quiescence-wait before BOTH captures is a later enhancement.
Build on `snapshot_demo_data_counts` + `assert_db_migration_max_version` — ELEVATE to full fingerprints. The property no fabrication can prove (a synthetic "rollback" can't show it restored EXACTLY A; a real B-rollback must).

## 7. (b cont.) `*-fixed` topology — RESOLVED = Option 1 (edit V in place + re-stamp)
**RESOLVED** (foreman per STATBUS-091, 2026-06-18): **Option 1 — C EDITS V's `.up.sql` in place** (working arc: same version, corrected bytes → H_C≠H_B). It is the King-ratified STATBUS-072 mechanism (amendments.tsv conveyance, SHIPPED); Option 2 (forward V+k) cannot rescue the FEW-who-failed without collapsing to Option 1 or a new supersede-skip mechanism. (In the **failing** arc, C edits V_fail → the working migration; since V_fail rolled back unrecorded, that's a FRESH apply, no amendments.tsv — §4.)

## 8. (f) The kill scenarios — fabricate STAYS, retired in 071 (086 is the ENABLER)
086's `RunSchedule` is a lock-free CLI one-shot that SETS a 'scheduled' row WITHOUT running it → a persistent **daemon-DOWN 'scheduled' row** — exactly what the kill scenarios consume (`./sb install` inline-dispatch + `STATBUS_INJECT_AT`) and what `fabricate_scheduled_upgrade_row` fakes today. v2026.05.2 has no such verb (its schedule-write is daemon-side + self-running — verified at the tag: daemon runs handleNotification→executeScheduled synchronously, service.go @ tag ~1574). So **086 IS THE ENABLER**; fabricate's retirement is gated on it. 071 reshapes the kill scenarios onto post-086 baselines (install_statbus_at_sha → register → schedule daemon-down → `./sb install` injects), then DELETES fabricate. Inject sites (migrate.go): `:388` during-migration, `:436-438` mid-tx, `:911` between, `:420` 60-min ceiling.

## 9. (e) Build order + dependencies
1. **(a) skeleton** [DONE/fired]: construct (push + dispatch w/ retry) → image-wait → no-op arc → teardown. Prove no orphans.
2. **(c) working arc** [fired — run 27779945098 hit the HCLOUD_NAME_PREFIX guard pre-VM (zero €/orphans); re-fire with the prefix env]: working→working-fixed (re-stamp/Albania) — exercises STATBUS-072.
3. **(d) failing arc + the fingerprint**: failing→failing-fixed (crash/error fail→rollback→fresh) — the clean-slate centerpiece (base-tables-only data-dim v1). Refactor: lift `arc_to` + the psql readers into data-helpers.sh (shared by working+failing arcs); re-confirm (c) green after the lift.
4. **Shape catalogue:** hanging (too-long/watchdog, both data sizes), recovery-of-recovery (kill during B's rollback, §8), canary-through-framework; reshape the legacy kill scenarios onto post-086 baselines + delete fabricate; (later) add derived tables + worker-quiescence to the fingerprint.
5. **(future)** silent-wrong-data.

DEPENDENCIES: STATBUS-056 (image-wait); STATBUS-057 (teardown branch-delete now; image-GC weekly, Q2); STATBUS-072 (re-stamp — SHIPPED); STATBUS-067 (canary THROUGH this framework — drive recovery via the systemd upgrade-service restart, not `./sb install` crashed-recovery which rolls back before the canary).

## 10. Risks / decisions for the engineer
- **Token (Q1, no PAT):** JOB-1 `contents: write`+`actions: write`; JOB-4 `contents: write`; image-delete→weekly GC. Dispatch needs the §2 retry.
- **VM name prefix:** run-arc must set `HCLOUD_NAME_PREFIX=statbus-arc-` (the shared `_check_name_safety` defaults to `statbus-recovery-`).
- **install-A:** `install_statbus_at_sha` (edge-install pinned to base_sha) — DETERMINISTIC + post-086 + disjoint. Requires A's images (4 services + sb) at base_short.
- **fingerprint determinism (§6):** base demo tables only for v1; exclude infra (public.upgrade/worker/db.migration/auth); strip pg_dump preamble. Derived tables + quiescence = later.
- **C-fix load-bearing (Option 1):** construct must EDIT the migration FILE (working: + amendments.tsv row; failing: no amendments.tsv) — never add a new migration.
- **Teardown `if: always()` + idempotent:** recompute names from scenario+run_id.
- **Albania fidelity:** drive upgrades via the `public.upgrade` row + the systemd service, NEVER `./sb install`/deploy-branch (except the kill scenarios' intentional `./sb install` inline-dispatch for injection — §8).
