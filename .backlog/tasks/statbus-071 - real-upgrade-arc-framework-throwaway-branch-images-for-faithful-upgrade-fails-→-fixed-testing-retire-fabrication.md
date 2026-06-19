---
id: STATBUS-071
title: >-
  real-upgrade-arc-framework: throwaway-branch images for faithful "upgrade
  fails → fixed" testing (retire fabrication)
status: In Progress
assignee:
  - engineer
created_date: '2026-06-17 09:05'
updated_date: '2026-06-19 05:40'
labels:
  - install-recovery
  - upgrade
  - testing-foundation
  - architect-plan
  - doctrine
dependencies: []
documentation:
  - doc-012
priority: high
ordinal: 71000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
KING DESIGN (2026-06-17) + foreman/architect convergent modeling. The doctrine (doc/install-upgrade-testing.md) applied to the harness's own construction: stop FABRICATING crash states (the reproducer-infidelity class that broke STATBUS-067's canary test — synthetic migration stripped by the recovery checkout); instead make the REAL system produce them via a real upgrade arc.

UNIQUE VALUE (the headline): a real install-A → upgrade-B-fails → rollback → upgrade-C-works arc tests the one property NO fabrication can — that B's rollback leaves the DB byte-identical to A so C applies cleanly (CLEAN-SLATE-AFTER-ROLLBACK). That is recovery-correctness end-to-end. Make it THE centerpiece assertion.

FEASIBILITY (verified): images.yaml builds per-commit images on push:[master], tagged by commit_short; the harness pulls by commit_short (branch-agnostic). So building images for THROWAWAY BRANCHES = add a branch pattern to images.yaml's trigger. Migrations are read from the TREE at runtime (throwaway commit supplies migration files; image supplies the binary — both needed, both from pushing the branch).

RESOLVED DESIGN:
- EPHEMERAL per-run branch: one workflow → branch off SHA-under-test → commit B (real broken migration) + C (same migration FIXED IN PLACE) → push → images.yaml builds B,C by commit_short → wait for images (reuse STATBUS-056 discover-preflight image-wait) → run arc → teardown (delete branch + B,C images).
- B/C TOPOLOGY: C = "B with the broken migration corrected IN PLACE" (same version V, fixed) — NOT additive-fix-on-top (that re-runs V_broken → fails again). After B's rollback V is unrecorded → C applies V(fixed) fresh, no content-hash conflict.
- CLEANUP: delete B,C images by commit_short on teardown (commit_short unique to throwaway commits, can't touch master) + defensive orphan sweep: multi-tag throwaway images with throwaway-<runid> → periodic sweep of throwaway-* older than N hours (STATBUS-057 cleanup primitive; operator confirms API).
- CANARY (Shape 2) Q1 REACHABILITY: Q1 is exercised ONLY via `./sb upgrade service` recovery boot (boot-migrate-up fails → STATBUS-017 defers to recoverFromFlag → resumePostSwap → canary → HasPending=true → Q1). `./sb install` crashed-recovery rolls back at its OWN migrate-up BEFORE the canary → Q1 NOT exercised. So the canary scenario must drive recovery via the SYSTEMD UPGRADE-SERVICE restart.

SHAPE CATALOGUE:
- Shape 1 (bad→fixed): crash migration, hang migration (King's two); + code-level upgrade failures (binary-swap/container-start/health-check fail in B, fixed in C).
- Shape 2 (interrupt): canary (kill mid-migration), worker-deadlock. Real migration in B + inject; no C.
- ELEVATE: clean-slate-after-rollback property (every Shape-1 arc asserts it).
- MULTI-MIGRATION B: ≥2 real migrations, fail on 2nd → 1st applied+recorded, 2nd not → rollback undoes BOTH → C applies all clean (real "between-migrations").
- RECOVERY-OF-RECOVERY: kill DURING B's rollback → re-recover → C (nastiest; combines 4-rollback-kill with the arc).
- SILENT-WRONG-DATA (north-star future, not opener): migration succeeds but corrupts data; needs a DATA ORACLE (install A, populate known data, upgrade to corrupting B, detect via invariant check). Sub-framework.

KING DECISION PENDING (A vs B): (A) FOUNDATION-NOW — build the framework + prove the canary through it before rc.04 (most faithful, slowest, extends the loop). (B) DECOUPLE — prove the canary now via a real tactical run (STATBUS-067, honors the doctrine — it IS a real run), close rc.04, build this framework as the proper FOLLOW-UP (not an rc.04 blocker). Foreman + architect lean (B): both reach the same end state (faithful framework exists); they differ only in whether it gates rc.04, and gating rc.04 on a new test-framework build trades the North Star (break OUT of the upgrade/recovery loop) for belt-and-suspenders.

OWNER: architect (design) → engineer (CI workflow + arc scenarios) → operator (image lifecycle/cleanup API) → foreman review. Depends-on/relates: STATBUS-067 (canary), STATBUS-056 (image-wait), STATBUS-057 (image cleanup).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 WORKING arc GREEN on a real VM: install A → B applies migration V → C re-stamps V's content_hash autonomously; data intact; zero orphan branches/VMs
- [ ] #2 FAILING arc GREEN on a real VM: install A → B's V deliberately fails → box rolls back to 'rolled_back' → clean-slate fingerprint equals the post-A baseline → C applies the fix fresh; data intact
- [ ] #3 Kill-family scenarios reshaped: the FABRICATED scheduled-upgrade row replaced by a real register+schedule (086); the crash stays real (existing inject / external NOTIFY-handshake kill)
- [ ] #4 fabricate_scheduled_upgrade_row DELETED with zero callers; NO synthetic crash-state fabrication remains anywhere (King's no-residual rule)
- [ ] #5 STRETCH (product-pristine): in-migration-SQL inject hooks retired in favour of the NOTIFY-handshake + external-kill-timing where feasible; remaining hooks limited to the Go-internal windows that no SQL can reach, each justified
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
STANDALONE FIDELITY (King correction, 2026-06-17) — CORRECTS the cloud-centric framing. Albania is the FIRST REAL EXTERNAL STANDALONE: a customer box physically inside Albania, NO SSB remote access (no SSH, no deploy branch). Deploy branches (ops/*/deploy/*) are CLOUD-only (niue). Albania's ONLY upgrade path: the box discovers a new GitHub RELEASE -> a LOCAL operator schedules it via the WEB INTERFACE (writes the public.upgrade row) -> the upgrade service applies + recovers AUTONOMOUSLY; SSB CANNOT intervene if it breaks. IMPLICATION for this framework: the branches/images only SUPPLY the A/B/C test artifacts (cheap, no permanent tags); the test must DRIVE the upgrade through the SAME scheduling mechanism the web UI uses (the public.upgrade row), and assert the box applies+recovers ON ITS OWN (model the no-remote-rescue reality). branch-vs-tag is just the test's cheap proxy -- production standalone upgrades come from release TAGS, but both procure BY COMMIT so the apply+recover path the test exercises is identical. This CORRECTS STATBUS-034's 'channels = ops/*/deploy/* deploy branches' framing (cloud-only). SEPARATE CONCERN: GitHub-release DISCOVERY (the box finding new releases) is standalone-specific and tested apart from apply+recover. CONSEQUENCE: the amend-an-applied-migration arc (STATBUS-072) is THE first scenario -- a remotely-unrescuable box must auto-apply an amended-migration release without crashing and self-recover if it does = the literal Albania failure mode. Albania is live + blocked NOW (cannot upgrade because the current path crashes), so this is present urgency, not future direction.

FINALIZED BRANCH SCHEME (King-converged, 2026-06-17). NAMING = FLAT siblings under test/ (the King's 3rd option) — the only git-valid scheme: VERIFIED that `git branch test/base` then `git branch test/base/hanging-migration` FAILS with `cannot lock ref ... 'refs/heads/test/base' exists` (a ref name can't be both a file and a directory), so the nested variants (test/base/hanging-migration/...) are impossible. Branches:
  test/base
  test/hanging-migration        test/hanging-fixed-migration
  test/working-migration        test/working-fixed-migration
LINEAGE: the 'build on each other' lives in the GIT COMMIT ANCESTRY, not the branch-name path. base = base commit; *-migration = a commit on top of base adding migration V; *-fixed-migration = a commit on top of *-migration that EDITS V's file IN PLACE (same version, corrected/amended bytes — NOT an additive fix-on-top, which would re-run V_broken). Tree at *-fixed-migration therefore carries the corrected V.
TWO ARCS = the two amend-migration populations (STATBUS-072):
  - working-migration -> working-fixed-migration: V SUCCEEDED then amended -> box RE-STAMPS (the MANY). [first scenario to build — the literal Albania case]
  - hanging-migration -> hanging-fixed-migration: V hangs/fails then fixed -> box RECOVERS + re-runs (the FEW).
CI TRIGGER: add `test/**` to images.yaml's push trigger (one line); the branch-name SUFFIX selects which scenario/arc runs. 'Trigger automation from the branch name' = satisfied.
STANDALONE FIDELITY (Albania): the test DRIVES the upgrade via the SAME scheduling mechanism the web UI uses (write the public.upgrade row) and asserts the box applies+recovers AUTONOMOUSLY (no remote rescue) — NOT a deploy-branch pointer move (that's cloud). branch-vs-tag is the test's cheap proxy; production standalone upgrades come from release TAGS; both procure BY COMMIT, so the apply+recover path the test exercises is identical. (Box-discovers-a-new-release is a separate standalone concern, tested apart.)
CENTERPIECE ASSERTION: after the failing upgrade rolls back, DB == base byte-identical, then the fixed upgrade applies clean (clean-slate-after-rollback).
This supersedes the cloud-channel framing; STATBUS-034's 'channels = ops/*/deploy/* deploy branches' was cloud-only.

ARCHITECT DISPATCHED to plan (2026-06-17 ~20:20), at King's prompt — turn the captured design (resolved branch scheme + B/C topology + clean-slate-after-rollback + Albania standalone-fidelity) into an IMPLEMENTATION-READY spec the engineer can build from: (a) images.yaml `test/**` trigger; (b) throwaway-branch workflow (branch→commit B+C→image-wait STATBUS-056→run arc→teardown STATBUS-057); (c) FIRST scenario = amend-migration/Albania case (working-migration→working-fixed-migration, STATBUS-072) driven via the public.upgrade web-UI row, autonomous apply+recover; (d) clean-slate-after-rollback mechanics; (e) 056/057/067/072 deps. PARALLEL to the rc.04 re-run (design only, NON-gating). A-vs-B decision RESOLVED = B (follow-up): close rc.04 first, build this immediately after — King + foreman aligned (King: 'once rc.04 passes, we can look at the framework'). Re-run triage takes priority over this planning if a scenario goes red. Architect reports the plan to foreman for King review.

IMPLEMENTABLE BUILD-SPEC ready (architect, 2026-06-18): backlog doc-012 "STATBUS-071 build-spec: real-upgrade-arc framework". Covers (a) images.yaml test/** trigger; (b) branch fixtures test/base + test/working-migration→working-fixed + test/hanging-migration→hanging-fixed with exact commit contents; (c) the working (succeed→amend→re-stamp/Albania) + hanging (fail→rollback→fix, crash + too-long/OOM-at-both-data-sizes) migration fixtures; (d) upgrade-arc-harness.yaml 4 jobs (construct→image-wait→run-arc-via-register+schedule→always-teardown); (e) clean-slate fingerprint (schema+ledger+data sha256); (f) inject-on-real-upgrade points (migrate.go :388/:436-438/:911/:420) for the kill arcs; build order + deps (056/057/072/067). Test driver = STATBUS-086 register+schedule (NOT fabrication). §7 documents BOTH *-fixed topologies (edit-V-in-place per 072 vs add-forward-V+k) as the KING'S open decision — does NOT block the spec; foreman puts it to the King at STEP-2 start.

arc (c) GREEN — run 27784916284 SUCCESS (2026-06-18, foreman autonomous drive). FIRST real-upgrade-arc proven on a VM: install A → A→B applied real migration V autonomously (register→schedule→daemon executeUpgrade, ephemeral-signed commit trusted) → B→C re-stamped content_hash (H_B=ab549269→H_C=4f65f4eb, V's effect preserved, exactly ONE ledger row) → PASS, data intact, healthy, ZERO orphans, all 4 jobs green. Proves the 072 amend-conveyance (re-stamp / MANY-who-succeeded population) end-to-end via the autonomous Albania path.

Took 4 runs to harden the harness (each found by a run, fixed through the foundation): (1) dispatch ref-race; (2) HCLOUD_NAME_PREFIX guard → statbus-arc- (ddb6bc25d); (3) commit-signing — ephemeral ed25519 key signs B/C, arc's install trusts the pubkey (4336affb1); (4) checkSignersDone scrub — install pre-flight-1 :352 verifies allowed-signers vs HEAD=A with {arc}-only (jhf added at :358), arc can't sign A → :1638 scrub-all → FIX: inject arc POST-install (config-gen doesn't run checkSignersDone) + restart statbus-upgrade@ unit (a2d485285; diag+dotenv regression test bd437370b). dotenv layer exonerated by cli/internal/dotenv/spaced_signer_test.go. NEXT: increment (d) failing→fixed arc + base-tables-only 3-dim clean-slate fingerprint.

=== STATE + DOCTRINE + OWNERSHIP (foreman, 2026-06-18, King asleep, autonomous drive) ===

OWNERSHIP (applies to all arc work here):
- BUILD / assignee = engineer (commits nothing).
- REVIEW = architect (design + correctness) THEN foreman (diff review).
- COMMIT + VM re-fire = foreman (per CLAUDE.md: agents don't commit; foreman commits + fires the paid VM runs).
- Diagnosis / instrument / log legwork = mechanic + operator as foreman dispatches.

STATUS:
- WORKING arc (c) reached GREEN earlier (run 27784916284): install A → B applies V → C re-stamps; data intact; zero orphans.
- Increment (d) added the FAILING arc (fail→rollback→fix) + a 3-dim clean-slate fingerprint + an arc-helpers.sh refactor. Fired BOTH scenarios (working re-prove + failing prove); BOTH RED — two distinct, understood bugs:
  - BUG 1 (failing arc): the fingerprint's pg_dump returned empty → the centerpiece GUARD fired and refused a vacuous fingerprint (working as designed — NO false-green). Cause = docker-exec pg_dump AUTH (locally the admin user is 'postgres' via local-socket trust and it works — 31k lines; on the VM the admin user needs a password the exec didn't pass). FIX: pass PGPASSWORD in capture_db_fingerprint (arc-helpers.sh). [engineer → architect/foreman review → foreman commit]
  - BUG 2 (working arc): the SECOND upgrade C sat state='scheduled' for 1200s; the daemon never ran it after B completed. Architect diagnosing ROOT CAUSE: real product gap (an unattended box can miss an upgrade scheduled while the service is restarting from the prior one — a genuine Albania hole) vs arc-timing (scheduled C before the post-B daemon was ready). Engineer instrumenting + adding a wait-for-daemon-ready. [architect diagnose → engineer fix/instrument → foreman commit; if a real gap, spawns a product-fix ticket]

KING DOCTRINE (2026-06-18) — the fruition reshape (replaces the old '§9(5)' framing):
1. NO justified residual. Every fake either maps to a real failure a real upgrade can produce (→ reproduce it for real) or it describes a state that cannot occur (→ delete it). If we ever believe a failure is real but can't reproduce it, that's a framework gap to FIX or a misread — never a licence to keep faking.
2. The crashes were ALWAYS real (the migrate path has a complete inject taxonomy: :388 during-migration, :202 mid-tx, :844/:845 after-commit-before-recorded, :911 between-migrations, + stalls). The ONLY fabrication in the whole kill family is fabricate_scheduled_upgrade_row — and its only job is to make ./sb install dispatch. 086's register+schedule produces that 'scheduled' row for REAL. So the reshape is a MECHANICAL swap (fabricate → real register+schedule), family-wide, then delete fabricate. Zero new product code for the crash itself.
3. NOTIFY-HANDSHAKE (King): a test migration runs `NOTIFY chan; SELECT pg_sleep(N);` with NO BEGIN — verified the runner invokes psql without --single-transaction (migrate.go:401), so the NOTIFY autocommits and reaches a listener while the migration sleeps; the listener does a REAL external kill mid-flight. More faithful than the boundary-kill hook (:388, which fires before the migration's SQL runs). Coordination lives in the TEST artifacts → product stays pristine.
4. EXTERNAL-KILL-TIMING (unifying primitive): kill is real; TIMING is by NOTIFY while a migration runs, or by watching logs/process-state otherwise. Retires the in-migration-SQL hooks + the SLOW Go-phase hooks. Residue (small, characterised): the after-commit-before-recorded ~ms window (close via atomic apply+record — see STATBUS-097) and the sub-second Go phases like binary-swap (retry-time, or keep ≤2 minimal hooks).

PLAN (post both-arcs-green): mechanical fabricate→register/schedule swap across the kill family; adopt external-kill-timing; delete the subsumed scenario (the failing arc already covers deterministic-error); retire the in-SQL hooks where the handshake reaches; delete fabricate at zero callers (= the final success criterion). Sketch: tmp/engineer-071-step5-plan.md; the architect's reconciliation map has the per-point detail.

NEW REQUIREMENTS surfaced by the King (separate tickets): STATBUS-095 (12h migration timeout-kill), STATBUS-096 (OOM + timeout kill-recovery tests), STATBUS-097 (scope atomic apply+record to close the residue window).

WORKING ARC GREEN (no-wait, on the 098 fix) — run 27807092720 SUCCESS (2026-06-19): install A → B applied V (claimed t+69s) → C re-stamped (H_B→H_C=297fcce262) → PASS, data intact, ZERO orphans. Confirms the masking-wait removal caused NO regression (the working arc + re-stamp work without it). AC#1 met. [This run claimed via the live NOTIFY (daemon was listening, LISTEN backends=1); the DETERMINISTIC no-NOTIFY proof is the claim-without-notify scenario, firing after the failing arc.]

BUG-1 (failing-arc fingerprint empty, failed twice) ROOT-CAUSED + FIXED: not auth — raw `docker ps|grep -db|docker exec` was fragile as the VM user; replaced with the PROVEN `docker compose exec -T db pg_dump` path + self-diagnosing DIAG. Part-3 durable guards committed too: funcBody wiring test (cli/internal/upgrade/scheduled_claim_wiring_test.go, fast every-CI) + claim-without-notify-arc.sh (non-default deterministic no-NOTIFY scenario). Commit 9452f2cf0 (architect-approved). The 098 product fix is 054c371c6.

NOW: failing arc firing (run 27807756274) — the BUG-1 VM oracle + the clean-slate-after-rollback centerpiece (AC#2). Then claim-without-notify (the 098 no-NOTIFY deterministic proof). OVERNIGHT NOTE: a gh-status glitch hung a monitor ~7h (failing run actually finished 22:13); monitors are now conclusion-based + capped.
<!-- SECTION:NOTES:END -->
