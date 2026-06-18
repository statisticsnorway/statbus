---
id: STATBUS-075
title: >-
  cut-rc04: the single tracker for what's left before we can cut release
  candidate rc.04
status: In Progress
assignee: []
created_date: '2026-06-17 11:04'
updated_date: '2026-06-18 01:21'
labels:
  - install-recovery
  - rc.04
  - gate
  - release
dependencies:
  - STATBUS-074
  - STATBUS-073
priority: high
ordinal: 75000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
THE one place that answers: "what are we waiting on to cut rc.04?"

WHY rc.04 MATTERS: Albania (a standalone StatBus box physically inside Albania, with no SSB remote access — upgrades happen only via a local operator through the web UI) installed v2026.05.2 and CANNOT upgrade, because the upgrade crashes. rc.04 is their first working upgrade target. Same crash that stuck Norway weeks ago.

CUT BAR (King's ruling): the install-recovery harness must reach 100% GREEN — every scenario passes, NO "known-acceptable reds" carve-out.

WHAT WE WERE WAITING ON — 3 fix classes, ALL now landed on master @78e770ac:
1. Freshness-reorder (harness staleness guard) — STATBUS-076, done (7f305f70d).
2. Masked-unit unmask (systemd) — done (e6c85c193).
3. Single-source recovery: remove from_commit_sha (the Albania crash) — STATBUS-077 + the gate-pedagogy fix STATBUS-078, done.

CURRENT STATE: the comprehensive 32-scenario install-recovery re-run (GitHub Actions run 27715901866, on 78e770ac) is LIVE. When it is 100% green → cut rc.04. Any red → triage by class, fix, re-run.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 #1 Comprehensive install-recovery run = 100% GREEN (all ~30 scenarios) on a commit containing all rc.04 code
- [ ] #2 #2 The two throwaway-build edge-case scenarios (binary-swap-kill + 4-rollback-kill) fixed and green — STATBUS-074
- [ ] #3 #3 Any VM-bootstrap infra blip cleared by a clean re-run, not masking a code red
- [ ] #4 #4 rc.04 tag cut off the green commit; the tag-push comprehensive run also green
- [ ] #5 #5 King gives the explicit cut on a fully-green run
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
RUN 27683157288 RESIDUALS FIXED + COMMITTED (foreman, 2026-06-17), both harness-only, master now e6c85c193:
1. Fabricate freshness (STATBUS-076) — fabricate ran the HEAD ./sb on the old tree -> staleness hard-fail. FIX = run fabricate with the tree-coherent binary (reorder). Committed 7f305f70d. Foreman caught + corrected a mechanic over-application (mid-tx-kill reverted, archivebackup-resume repositioned) before commit.
2. Quiesce-mask (STATBUS-073) — SIGKILL quiesce's `mask --runtime` paired with a plain `unmask` left the unit masked -> direct `systemctl start` failed (watchdog, resume-died-rollback). FIX = `unmask --runtime`. Committed e6c85c193.
HOLDING the re-run until run 27683157288 completes (batch any 3rd residual into ONE re-run on e6c85c193). PRODUCT unchanged (both fixes are test scaffolding). PATH: run completes -> characterize full residual -> (fix any 3rd) -> ONE comprehensive re-run -> if 100% green, cut rc.04 (King's bar).

RUN 27683157288 COMPLETE (3a0d6e6dd, the quiesce-only commit BEFORE my fixes): 16 PASS / 14 FAIL. Foreman classified all 14 by signature:
- FRESHNESS (7): binary-swap/backup/checkout-kill, between-migrations, container-restart, mid-migration, 4-rollback-kill → FIXED by e6c85c193 (reorder 7f305f70d).
- MASKED-UNIT (2): archivebackup-watchdog, watchdog-reconnect → FIXED by e6c85c193 (unmask --runtime).
- INFRA (1): stage-a-killed-migrate (vm-bootstrap.sh:360 SSH blip) → re-runnable.
- FLAG-ABSENT after kill (4) → GENUINELY-NEW 3rd class, NOT fixed by e6c85c193: archivebackup-resume, mid-tx-kill, resume-died-rollback, 4-rollback-restore-watchdog. All `✗ expected flag file present after kill`. Filed STATBUS-077; architect diagnosing product-vs-harness (could be ALBANIA-CRITICAL if executeUpgrade doesn't write the in-progress flag before the kill point — a no-remote-rescue box's mid-upgrade crash would be unrecoverable). This was RUN A's Cat A, MASKED by the quiesce-rollback, now unmasked.
SO: e6c85c193 fixes 9 of 14; infra re-runs clean; the 4 flag-absent need STATBUS-077's fix. RE-RUN HELD until STATBUS-077 lands, then ONE comprehensive re-run batches all (9 + 4 + infra) on the combined commit. The doctrine working: each run peels one layer.

RE-RUN FIRST RED (2026-06-17, run 27715901866): 2-preswap-backup-kill FAILED at `✗ expected flag file present after kill` (job 81988885018; artifact tmp/2pbk-artifact/). 6 scenarios green before it; 30 continue (~23 queued). LOG EVIDENCE: (1) line 4012 `Error: seed restore: pg_restore reported errors (transaction rolled back; database unchanged)` — a seed-restore failure during setup (STATBUS-018 class); (2) line 4134 upgrade row reached state=completed, has_migrations=false, summary=harness fabricate_scheduled_upgrade_row. FOREMAN PRELIMINARY HYPOTHESIS (UNCONFIRMED): the seed-restore failure cascaded — install didn't land at the older release → fabricated upgrade became a no-migration no-op → completed before the preswap-backup kill fired → flag removed → assertion fails. Would be a HARNESS/SETUP issue (STATBUS-018), NOT a from_commit_sha regression (the harness fabricate doesn't touch the dropped column). ROUTED to architect to CONFIRM product-vs-harness from the run (King: don't assume, nothing swept under the rug). If STATBUS-018/harness → separable, re-runnable. If a genuine flag-timing product red → cut-blocking. Architect verdict PENDING.

RED → PATTERN (2026-06-17): now 3 reds, ALL 2-preswap kill scenarios (backup-kill, binary-swap-kill, checkout-kill); 7 green; ~22 queued. CONFIRMED IDENTICAL across all 3 (artifacts tmp/2pbk-artifact/, tmp/2bsk-artifact/): seed-restore `pg_restore reported errors (transaction rolled back; database unchanged)` + `HEAD is now at 78e770ac5` (tree at HEAD, not the older release) + HEAD's migrations applied + upgrade row state=completed has_migrations=false (NO-OP) + `✗ expected flag file present after kill`. ⇒ the older-release install's seed-restore fails → install lands at HEAD → the upgrade is HEAD→HEAD no-op → the preswap kill never fires → flag absent. The from_commit_sha RECOVERY code is NEVER reached → this is a SETUP CASCADE, not a from_commit_sha product regression. LIKELY blocks every install-at-older-release scenario (more reds incoming) → the re-run cannot reach 100% green until the setup is fixed. ARCHITECT pinning (per King don't-assume): (1) NEW (seed regen during COMMIT 2 broke older-release install?) vs PRE-EXISTING STATBUS-018 (pg_restore --clean on populated DB); (2) WHY 0-happy-upgrade PASSES though it also installs at the older release (the discriminator); (3) scope; (4) fix shape. If foreman's seed regen introduced it, foreman owns the fix. CUT LIKELY DELAYED by this setup layer — iterate per the doctrine (the run peels one layer).

RE-RUN 27715901866 — FULL DIAGNOSIS (foreman, overnight 2026-06-17, King-authorized autonomous drive to 100% green). The 'seed-restore cascade' hypothesis ABOVE is SUPERSEDED/WRONG — verified by deeper log analysis. The seed-restore pg_restore error is a DOWNSTREAM symptom of db-unreachable→step-table, not the cause. Reds are HETEROGENEOUS — FOUR modes (9 reds confirmed; run still completing):

MODE A — early `git checkout $HEAD_LOCAL` in the install-cN heredoc (6: 2-preswap-backup-kill, 2-preswap-binary-swap-kill, 3-postswap-{between-migrations,container-restart,mid-migration,mid-tx}-kill). Checks out HEAD before `./sb install`, so HEAD's docker-compose can't reach the DB container started under v2026.05.2-compose → db-unreachable → step-table → executeUpgrade never runs → kill never fires → '✗ flag present after kill'. PROOF: 2-preswap-checkout-kill (STATBUS-060 fix) does NOT checkout early → correctly detects scheduled-upgrade + fires the kill. The 6 never got STATBUS-060 propagated. FIX (HARNESS, faithful, Albania-safe — real executeUpgrade defers checkout): replace early `git checkout` with checkout-kill.sh:115-118 no-checkout block. ENGINEER preparing; architect concur pending; foreman commits.

MODE B — image-readiness race (2-preswap-checkout-kill): kill+recovery WORK (rolled_back terminal), but final assert '✗ ./sb binary advanced after recovery (78e770ac→5efe6dfe)' fails — recovery's install.sh --channel edge procured an ANCESTOR image because 78e770ac's per-commit image was STILL BUILDING (row docker_images_status/release_builds_status=building) when the harness ran. HARNESS-ORCHESTRATION: gate the run on per-commit image readiness, or pin recovery to the target-SHA image. Architect+operator.

MODE C — recovery DB-constraint violation (3-postswap-migrate-killed-after-commit, 3-postswap-migration-deterministic-error): crash recovery applyPostSwap:completed-terminal marks resumed row 'completed' but FAILS chk_upgrade_state_attributes (23514) — log_relative_file_path IS NULL (constraint requires it for 'completed'; invariant LOG_POINTER_STAMPED). Row is harness-fabricated. LIKELY harness fabrication-fidelity (real row stamps it at start → Albania unaffected) — but architect MUST confirm from_commit_sha removal (1083c62b0, -137 lines service.go) didn't drop that stamp. Architect.

MODE D — resume-idempotency (3-postswap-resume-died-rollback): resume COMPLETED when the injected kill should have died it. Kill-timing/resume. Architect.

OWNERS: A=engineer fix (foreman commits, clear path); B=architect+operator (image gating); C=architect (confirm not a from_commit_sha regression); D=architect. 13 pending at last check — more reds may land. NEXT: land Mode A → push → re-fire; B/C/D follow per architect. Doctrine held: deep verification refuted both the seed-cascade AND my own .env-by-binary hypotheses before any wrong fix shipped.

ARCHITECT-VERIFIED DETERMINATION + GREENLIT FIX PLAN (foreman+architect, overnight 2026-06-17). All 4 modes CONFIRMED HARNESS; NONE a from_commit_sha regression; Albania SAFE on every real path (service-NOTIFY AND ./sb install operator both keep tree@OLD through state-detection per STATBUS-060). Refines the note above:

MODE A mechanism (precise, architect-verified): HEAD's docker-compose.rest.yml:45 has a MANDATORY `${REST_ADMIN_BIND_ADDRESS:?...must be set}` guard that makes `docker compose` HARD-ERROR at interpolation when the v2026.05.2-generated .env lacks that post-v2026.05.2 var (verified: v2026.05.2 compose 0 refs / config.go 0 writes; HEAD 1/1). DBReachable runs `docker compose exec db psql 'SELECT 1'` → interpolation error → false → StateDBUnreachable → step-table, executeUpgrade never runs, inject never fires. Needs BOTH tree@HEAD (the early `git checkout`) AND .env@OLD. SCOPE = 7 scenarios (added 4-rollback-kill:129). FIX = DELETE the early checkout (NOT reorder — reorder is a false-green that masks Root B). 3 CLEAN done by engineer (backup-kill, binary-swap-kill, mid-migration-kill); 4 COMPLEX need binary-staging/freshness-aware edits (between-migrations + container-restart have a Pattern-D `cp /tmp/sb ./sb` re-place; mid-tx-kill:153 is VM_EXEC; 4-rollback-kill first-install) — architect speccing.

MODE B = harness: recovery hard-codes `--channel edge` (vm-bootstrap.sh:534) = moving master tip; drifted 11 commits FORWARD to DESCENDANT 5efe6dfe (not ancestor). Real path uses pinned stable/prerelease v-tags (install.sh:164-165) → NOT exposed. FIX = recovery REUSES the already-staged target binary (upload_sb_to_vm), not edge.

MODE C = harness-fabrication: fabricate_scheduled_upgrade_row sets log_relative_file_path NULL (data-helpers.sh:315); real rows START-stamp it (service.go:3573). FIX = fabricate stamps a non-NULL path. from_commit_sha removal cleared (1083c62b0 touched 0 completed-writes). Product COALESCE-hardening of the two un-guarded completed-writes (:2405/:4494) = STATBUS-081 (non-gating).

MODE D + 3-postswap-migrate-killed-after-commit = architect triaging in parallel.

PLAN: batch ALL harness fixes (7 Mode A + Mode B + Mode C [+D/migrate if harness]) → ONE commit → push → WAIT for images.yaml (per-commit image ready, else re-inflicts Mode B) → re-fire install-recovery-harness.yaml ONCE. CAVEAT (architect): Fix C may UNMASK Root B-class issues (checkout-kill already shows `git fetch origin commitSHA` rc=128 + binary roll-forward) — that's the test finally exercising executeUpgrade for the first time, SIGNAL not failure; iterate. SEPARATE non-gating tasks: Root B audit, STATBUS-018 (seed-restore --clean on populated DB), STATBUS-081 (COALESCE).

RUN 27715901866 COMPLETE (foreman, overnight 2026-06-18): 13 reds / 19 green (the full 32-scenario tally — earlier '9 reds' was a partial mid-run view). The Mode A/B/C/D harness-fix batch (applied + architect-reviewed + bash-n clean, awaiting commit) addresses 11 of the 13. TWO MORE surfaced from the pending set, NEITHER Mode A/B/C/D:

• 4-rollback-restore-watchdog — RECOVERY-COMPLETES-FORWARD. Reached scheduled-upgrade (not db-unreachable), the postswap kill fired (rc=137), the watchdog assertion passed (NRestarts=0 flat), but the row reached 'completed' when a rollback was expected (log :4132); during recovery 'crash recovery: DB not reachable -> docker compose start db' (:4025) then completed forward. Recovery-semantics — possibly Mode-D-class self-heal or STATBUS-031 (rollback-watchdog gap). Routed to architect (harness-vs-product + foldable-vs-next-iteration).

• 5-install-stage-a-killed-migrate — HARNESS BASH SYNTAX ERROR (NOT infra, NOT seed-restore despite STATBUS-029's old note). The empty-app-name advisory-lock-zombie wedge hit `bash: -c: line 1: syntax error near unexpected token 'then'` (:3844) -> rc=2 at vm-bootstrap.sh:360; the `sudo -i -u statbus -- $quoted_args` transport collapsed a multi-line if/then (the printf-%q/newline-collapse class). Likely a quick harness transport fix. Routed to architect for wedge-owner + line.

PLAN: commit + re-fire the 11-fix batch (validates Mode A/B/C/D; the architect's 'Fix C may unmask Root-B-class issues' caveat means the re-run is a DISCOVERY run, not guaranteed green — iterate per the doctrine). Fold 5-install's wedge fix if quick + ready before commit (->12/13). 4-rollback-restore-watchdog -> next iteration unless foldable. So the cut is more than one re-run away: 13 reds, 11 fixed-pending-validation, 2 new in diagnosis, plus whatever the Mode-A unmask reveals. Commit message drafted: tmp/commit-msg-harness-batch.txt.

DISCOVERY RUN 27724641822 (on 674329816, the 11-fix batch) COMPLETE: 13→10 reds. The doctrine working — real progress + the predicted Mode-A unmask + one foreman regression.

FIXED (4): 3-postswap-between-migrations-kill + 3-postswap-mid-migration-kill (Mode A), 3-postswap-migration-deterministic-error + 3-postswap-migrate-killed-after-commit (Mode C). Mode C (data-helpers log-pointer) fully worked.

UNMASK — Mode A WORKS, reveals the NEXT layer (recovery freshness-rebuild). backup-kill (representative): now reaches scheduled-upgrade → executeUpgrade → C3 kill FIRES (rc=137) → '✓ RED confirmed: flag PreSwap, .tmp backup, binary unswapped' (the kill is perfect — the original goal). REAL failure is now the RECOVERY: the Mode-B reuse-staged HEAD binary, run on the recovery-boot-restored SOURCE tree, mismatches → freshness SELF-HEAL → 'go build ... version=2026.05.2' → 'Self-heal rebuild/exec failed: rebuild failed: exit status 2' (no Go toolchain on the VM). Likely same for binary-swap/container-restart/mid-tx/4-rollback. Architect triaging: fix = carve out freshness in the reuse-staged path OR pivot Mode B to install.sh --commit <sha> (STATBUS-082, procure not rebuild); + whether freshness-rebuild-on-recovery is a latent Albania risk (no-Go box).

MODE D (resume-died-rollback): SKIP_SEED INSUFFICIENT — kill fires but the resume still self-heals to 'completed' (service.go:4716). Needs a deeper fix; architect re-diagnosing.

Mode B (checkout-kill): kill fires + a new rc=2 at vm-bootstrap.sh:600 — same freshness-rebuild or different; architect triaging.

REGRESSION (foreman-owned): 1-boot-concurrent-install was GREEN; the completeness-fold of its checkout-removal turned it RED ('first install did not create upgrade-in-progress.json' — the checkout was load-bearing for its inject path). The 'safe to fold' analysis (mine + architect-concurred) was wrong; the re-run is the oracle. REVERTING via the engineer (restore its checkout) — goes in the next batch.

NEXT BATCH: revert 1-boot + #2 ssh-STDIN (pre-staged, approved) + the architect's recovery-unmask fixes (freshness/Mode-B + Mode D) → commit → re-fire. #1 (4-rollback-restore-watchdog) still parked for real-VM tuning. Honest: several iterations from 100% green; each run peels a layer.
<!-- SECTION:NOTES:END -->
