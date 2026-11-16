---
id: doc-012
title: >-
  STATBUS-071 build-spec: real-upgrade-arc framework (branch fixtures +
  upgrade-arc-harness.yaml + clean-slate fingerprint)
type: specification
created_date: '2026-06-18 15:07'
updated_date: '2026-06-18 18:52'
tags:
  - upgrade
  - install-recovery
  - test-fidelity
  - architect-plan
  - phase-2
---
# STATBUS-071 build-spec — real-upgrade-arc framework

**Audience:** engineer (build), foreman (review). **Status:** implementable; §7 topology=Option 1; §2 Q1=explicit dispatch; §5 install-A=install_statbus_at_sha; §5 commit-signing=ephemeral-key sign+trust; §4/§6 (c)+(d) settled. **Depends on:** STATBUS-086 (register+schedule — DONE), STATBUS-056 (image-wait), STATBUS-057 (image cleanup), STATBUS-072 (amend/re-stamp — DONE), STATBUS-067 (canary).

## 0. North Star
Stop FABRICATING crash states. Make the REAL system produce them via a real arc: **install A → upgrade to a defective B (fails) → service rolls back → upgrade to a fixed C (works)**. CENTERPIECE = **clean-slate-after-rollback**: B's rollback leaves the DB byte-identical to A so C applies clean — the property no fabrication can prove. **Albania fidelity:** drive every upgrade through the `public.upgrade` row (the web-UI mechanism), assert the box applies+recovers **autonomously** — no SSH rescue.

## 1. The test driver = STATBUS-086 (NOT fabrication)
Every ARC schedules the real way: on the VM, `git fetch` the target commit, then `./sb upgrade register <commit>` (resolve + upsert state='available'; service prepares — image pull + verifyArtifacts→ready, service.go:1101+) → `./sb upgrade schedule <commit>` (promote to 'scheduled' → DB trigger fires NOTIFY upgrade_apply, service.go:3408 → service runs `executeScheduled`, service.go:3487). NEVER a deploy-branch pointer, NEVER `./sb install` for the upgrade STEPS. (register+schedule require a POST-086 baseline — incl. A; see §5 install-A. The legacy v2026.05.2-baseline kill scenarios keep `fabricate_scheduled_upgrade_row` until 071 reshapes them — see §8.)

## 2. (a) Per-commit images for test/* branches — EXPLICIT DISPATCH (Q1 RESOLVED)
**Q1 problem:** a GITHUB_TOKEN push does NOT trigger downstream workflows → a `test/**` PUSH trigger wouldn't fire for the CI arc.
**Solution (no PAT):** JOB-1 dispatches images.yaml per branch — `gh workflow run images.yaml --ref <branch>` (with a ~5×/5s RETRY — ref propagation is eventually-consistent, a just-pushed ref can transiently 404). images.yaml UNCHANGED (`workflow_dispatch` :24; `describe` computes commit_short from the dispatched ref :49; build/manifest/seed tag by it :104/:133/:173). Perms: `contents: write` + `actions: write`. NO PAT.

## 3. (b) Branch fixtures — exact names + what each commit carries
Flat sibling scheme. `A` = the SHA-under-test:
```
test/base                  = A itself
test/working-migration         → test/working-fixed-migration   (V SUCCEEDS, then amended → re-stamp; (c))
test/failing-migration         → test/failing-fixed-migration   (V crashes, then fixed → fail→rollback→fresh; (d))
```
- **B** off A: adds ONE real migration `V` (.up + .down). The DEFECT lives in V (§4).
- **C** off B: applies the FIX (§7 Option-1: edit V in place).
- Branch names suffixed with the run id; images content-unique by commit_short.

## 4. (c)/(d) The migration fixtures each branch carries
- **working** (re-stamp / Albania, STATBUS-072 — (c)): B's V SUCCEEDS (CREATE TABLE + INSERT; H_B). C amends V IN PLACE (bytes→H_C≠H_B, RESULT identical) + declares V in `migrations/amendments.tsv` → B→C RE-STAMPS autonomously (the MANY). No clean-slate assertion (not a rollback arc).
- **failing** (crash/error fail→rollback→fix + clean-slate centerpiece — (d)): B's V = deterministic error (`DO $$ BEGIN RAISE EXCEPTION '…' END $$;`, `.down`=no-op) → migrate up fails → postSwapFailure → recoveryRollback → 'rolled_back'. C edits V in place → the working migration → V applies **FRESH** (V_fail rolled back → unrecorded → NO amendments.tsv, NO re-stamp). The FEW. Carries the fingerprint (§6).
- **hanging** (too-long/watchdog — LATER, §9): data-size-dependent V (works-for-most); run at BOTH data sizes. (Naming: **failing**=crash/error (d); **hanging**=too-long/watchdog.)

## 5. (b cont.) upgrade-arc-harness.yaml — the four jobs
NEW `.github/workflows/upgrade-arc-harness.yaml`. TRIGGER: `workflow_dispatch` (inputs: `base_sha`, `scenario` [working|failing]). Single serializer; concurrency cancel-in-progress:false.

- **JOB 1 — construct** (`contents: write` + `actions: write`): create B + C off A; **SIGN both** — generate an EPHEMERAL ssh key (`ssh-keygen -t ed25519 -N '' -f /tmp/arc_signer`) and commit B + C with it (`git -c gpg.format=ssh -c user.signingkey=/tmp/arc_signer -c commit.gpgsign=true commit -S …`). CI's default `git commit` is UNSIGNED → verifyCommitSignature (service.go:2680, MANDATORY) would reject B/C; signing + trusting (JOB-3) is the security-consistent fix (NOT a skip-verification flag). Push via GITHUB_TOKEN; `gh workflow run images.yaml --ref <branch>` per branch (§2 retry). Emit `base_short`, `b_short`/`c_short`, `b_full`/`c_full`, `v_version`, AND **`arc_signer_pub`** (the ephemeral PUBLIC key; private key stays in construct, discarded). C's fix = edit V in place (§7).
- **JOB 2 — image-wait** (REUSE STATBUS-056): poll ghcr until `app worker db proxy sb` exist at base_short AND b_short AND c_short. (`sb` needed: install_statbus_at_sha + buildBinaryOnDisk→ProcureShort pull it; base_short gates the install-A race.) ≈40m, fail loud.
- **JOB 3 — run-arc** (Hetzner VM; mirror harness bootstrap + EXIT-trap teardown; **set `HCLOUD_NAME_PREFIX=statbus-arc-`** — the shared `_check_name_safety` defaults to `statbus-recovery-` and rejects `statbus-arc-*` otherwise). Drive via register+schedule (§1):
  1. **Install A=base_sha via `install_statbus_at_sha <vm> <base_sha>`** — edge-install PINNED to base_sha (git fetch+checkout <sha> → toolchain-free procure statbus-sb:<base_short> via docker pull/create/cp → cp env-config/users → `./sb install`). **TRUST the arc signer:** before `./sb install`, set `UPGRADE_TRUSTED_SIGNER_arc=<arc_signer_pub>` in .env.config (e.g. `./sb dotenv -f .env.config set`, or append to the uploaded env-config) → config-gen propagates it to .env (config.go:716) → `loadTrustedSigners` (service.go:2615) writes the allowed_signers line `arc <key>` (the value is read verbatim as a RAW key — :2643; `trust-key add`'s GitHub fetch is just one populator) → verifyCommitSignature(B/C) RUNS and PASSES. Verification stays MANDATORY (unchanged); the ephemeral key is trusted ONLY on this throwaway VM, signs ONLY B/C; production boxes never carry it. (Principal note: key-based, not committer-email-matched — proven by production: UPGRADE_TRUSTED_SIGNER_jhf verifies commits authored by jorgen@veridit.no.) DETERMINISTIC + post-086, DISJOINT from `install_statbus_in_vm`. Fresh install → rc=0 (rc=75=upgrade-rollback path, not taken). Health-check.
  2. `populate_with_demo_data` → capture A-FINGERPRINT (§6).
  3. Upgrade → B (register+schedule, daemon-autonomous). **failing** → assert 'rolled_back' + auto-recovered (no SSH rescue); **working** → 'completed'.
  4. CENTERPIECE (failing only): re-capture fingerprint, assert == A-FINGERPRINT byte-identical (§6).
  5. Upgrade → C. **failing:** V unrecorded → C's V(fixed) applies FRESH. **working:** C amends an applied V → re-stamp.
  6. Assert: C completes, DB at C, schema reflects V(fixed), data intact, healthy — autonomous.
- **JOB 4 — teardown** (`if: always()`; `contents: write`): delete the two `test/*` branches (RECOMPUTE names from scenario+run_id → works on partial construct failure; ls-remote-guarded, best-effort, exit 0). image-delete → weekly GC (Q2). VM EXIT-trap (+ if:always() net hcloud-delete) reaps the instance.

## 6. (d) Clean-slate-after-rollback fingerprint (the centerpiece)
Capture after install-A+populate, re-capture after B's rollback; assert byte-identical, EACH dim separately. **DETERMINISM is make-or-break (a false mismatch on a CLEAN rollback = a flaky red):**
1. **SCHEMA**: `pg_dump --schema-only --no-owner --no-privileges` (docker exec the db container) → strip the volatile preamble (`-- Dumped …` + version-comment lines) + normalize blank-line/trailing-WS → sha256. Byte-stable for two captures on the SAME box. pg_dump (NOT information_schema) — catches function/trigger/policy residue.
2. **LEDGER**: `SELECT version, content_hash FROM db.migration ORDER BY version` → sha256. (version+content_hash ONLY.) Post-rollback == post-A (V_fail unrecorded).
3. **DATA**: per-table `md5(coalesce(string_agg(t::text,'|' ORDER BY t::text),''))` → sha256, scoped to the demo **BASE** tables (legal_unit, establishment) — NOT a full-DB digest. EXCLUDE infra (public.upgrade's 'rolled_back' B-row; worker.*; db.migration; auth.*). **v1 = NON-DERIVED base tables only** — DERIVED tables (statistical_unit, statistical_history) are worker-COMPUTED, match post-rollback only if derivation is quiescent at snapshot + no re-derivation runs before the re-capture; base suffices (derived=f(base)). Derived + quiescence-wait = later.
Build on snapshot_demo_data_counts + assert_db_migration_max_version (ELEVATE to full fingerprints).

## 7. `*-fixed` topology — RESOLVED = Option 1 (edit V in place + re-stamp)
**Option 1 — C EDITS V's `.up.sql` in place** (working: corrected bytes → H_C≠H_B). King-ratified STATBUS-072 (amendments.tsv conveyance, SHIPPED); Option 2 (forward V+k) can't rescue the FEW without collapsing to Option 1 or a supersede-skip mechanism. (failing arc: C edits V_fail → working migration; V_fail rolled back unrecorded → FRESH apply, no amendments.tsv — §4.)

## 8. (f) The kill scenarios — fabricate STAYS, retired in 071 (086 is the ENABLER)
086's `RunSchedule` is a lock-free CLI one-shot that SETS a 'scheduled' row WITHOUT running it → a persistent **daemon-DOWN 'scheduled' row** — what the kill scenarios consume (`./sb install` inline-dispatch + `STATBUS_INJECT_AT`) and what fabricate fakes. v2026.05.2 has no such verb (daemon runs handleNotification→executeScheduled synchronously, service.go @ tag ~1574). 086 IS THE ENABLER; 071 reshapes the kill scenarios onto post-086 baselines (install_statbus_at_sha → register → schedule daemon-down → `./sb install` injects), then DELETES fabricate. Inject sites (migrate.go): `:388` during-migration, `:436-438` mid-tx, `:911` between, `:420` 60-min ceiling.

## 9. (e) Build order + dependencies
1. **(a) skeleton** [DONE/fired]: construct (push + dispatch w/ retry) → image-wait → no-op arc → teardown. No orphans.
2. **(c) working arc** [firing — earlier run hit HCLOUD_NAME_PREFIX pre-VM (zero €); now the commit-signature gate (§5 JOB-1/JOB-3 fix) — re-fire]: working→working-fixed (re-stamp/Albania) — exercises STATBUS-072 + now the real verifyCommitSignature path.
3. **(d) failing arc + fingerprint**: failing→failing-fixed (crash/error fail→rollback→fresh) — clean-slate centerpiece (base-tables-only data-dim v1). Refactor: lift `arc_to` + readers into data-helpers.sh (shared); re-confirm (c) green after.
4. **Shape catalogue:** hanging (too-long, both data sizes), recovery-of-recovery, canary-through-framework; reshape the legacy kill scenarios onto post-086 baselines + delete fabricate; (later) derived tables + quiescence in the fingerprint.
5. **(future)** silent-wrong-data.

DEPENDENCIES: STATBUS-056 (image-wait); STATBUS-057 (teardown branch-delete now; image-GC weekly, Q2); STATBUS-072 (re-stamp — SHIPPED); STATBUS-067 (canary THROUGH this framework — recovery via the systemd upgrade-service restart, not `./sb install` crashed-recovery).

## 10. Risks / decisions for the engineer
- **Token (Q1, no PAT):** JOB-1 `contents: write`+`actions: write`; JOB-4 `contents: write`; image-delete→weekly GC. Dispatch needs the §2 retry.
- **Commit signing:** CI's default commit is UNSIGNED → verifyCommitSignature (mandatory) rejects it. FIX = sign B/C with an EPHEMERAL ssh key (JOB-1) + trust it via `UPGRADE_TRUSTED_SIGNER_arc=<pubkey>` on the arc box (JOB-3, the existing raw-key path — loadTrustedSigners:2643). Verification stays MANDATORY + is now EXERCISED by the arc; ephemeral key scoped to the throwaway VM + B/C only; NO skip-verification flag; production untouched.
- **VM name prefix:** run-arc must set `HCLOUD_NAME_PREFIX=statbus-arc-` (shared `_check_name_safety` defaults to `statbus-recovery-`).
- **install-A:** `install_statbus_at_sha` — DETERMINISTIC + post-086 + disjoint. Requires A's images (4 services + sb) at base_short.
- **fingerprint determinism (§6):** base demo tables only (v1); exclude infra; strip pg_dump preamble. Derived + quiescence = later.
- **C-fix load-bearing (Option 1):** construct EDITS the migration FILE (working: + amendments.tsv; failing: no amendments.tsv) — never adds a new migration.
- **Teardown `if: always()` + idempotent:** recompute names from scenario+run_id.
- **Albania fidelity:** drive upgrades via the `public.upgrade` row + the service, NEVER `./sb install`/deploy-branch (except the kill scenarios' intentional `./sb install` inline-dispatch — §8).
