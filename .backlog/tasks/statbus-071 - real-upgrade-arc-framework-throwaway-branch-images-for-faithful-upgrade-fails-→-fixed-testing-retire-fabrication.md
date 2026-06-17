---
id: STATBUS-071
title: >-
  real-upgrade-arc-framework: throwaway-branch images for faithful "upgrade
  fails → fixed" testing (retire fabrication)
status: To Do
assignee: []
created_date: '2026-06-17 09:05'
updated_date: '2026-06-17 12:08'
labels:
  - install-recovery
  - upgrade
  - testing-foundation
  - architect-plan
  - doctrine
dependencies: []
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
<!-- SECTION:NOTES:END -->
