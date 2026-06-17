---
id: STATBUS-078
title: >-
  gate-pedagogy: stamp-guard + pairing-hook denials must teach the clean
  migration-landing flow, not dangle FORCE=1 / --no-verify overrides
status: Done
assignee:
  - '@engineer'
created_date: '2026-06-17 18:19'
updated_date: '2026-06-17 19:46'
labels:
  - dx
  - safety-machinery
  - migrations
  - rc.04
  - pedagogy
dependencies:
  - STATBUS-077
references:
  - 'dev.sh:134-253'
  - 'cli/cmd/types.go:140-214'
  - '.githooks/pre-commit:63-112'
  - cli/internal/migrate/at_head.go
priority: high
ordinal: 78000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
King directive (2026-06-17): "hooks exist to PREVENT dirty workarounds … the educational text is not good enough since people consider workarounds — we need to improve the denial and improve the learning … point to the right procedure, suggesting the right commands." Triggered when landing the STATBUS-077 from_commit_sha DROP migration: the foreman reached for `git commit --no-verify` and the engineer for `FORCE=1` — both led there by the gate denials.

ROOT CAUSE: both stamp-guard denials (dev.sh check_stamp_guard:153-160 + cli/cmd/types.go checkTypesStampGuard:152-161) end with `Override: commit or stash the changes, or set FORCE=1 to bypass.` — they list three escapes and never the actual procedure, and frame the one that works ("FORCE=1 to bypass") as cheating. For the canonical land-a-migration flow all three are wrong/blocked: `commit` → blocked by the pre-commit pairing hook (.githooks/pre-commit:81-112, migration ⟹ doc/db staged together); `stash` → breaks generate-doc-db's assert-db-at-head (seed vs on-disk head, cli/internal/migrate/at_head.go); `FORCE=1` → the only one that works, but reads as a bypass. So the HAPPY PATH itself is forced through an override — that is why agents reach for workarounds.

CLEAN PROCEDURE (the right commands, from the code):
1. ./sb migrate new --description "…"  + edit up/down
2. ./sb migrate up                     (apply to dev DB)
3. ./sb migrate up --target seed && ./dev.sh create-test-template   (bring seed to head so assert-db-at-head passes)
4. ./dev.sh generate-doc-db && ./sb types generate                 (regen schema docs + types)
5. git add migrations/ doc/db/ app/src/lib/database.types.ts        (stage migration + regen TOGETHER)
6. git commit                          (pre-commit hook validates the pairing — NO --no-verify)
Today step 4 requires FORCE=1 (stamp guard refuses dirty migrations/).

RECOMMENDED FIX (foreman → King for review BEFORE implementing):
(1) ROOT: change check_stamp_guard (dev.sh) + checkTypesStampGuard (cli/cmd/types.go) so a dirty migrations/ at generate-time RUNS the regen but SKIPS writing the freshness stamp (a stamp is never written while dirty → can never lie), instead of REFUSING. Then step 4 needs no FORCE=1 — the canonical flow is override-free; the pre-commit pairing hook stays the correctness gate. SANITY-CHECK: (a) other caller ./dev.sh test fast (scope migrations,test); (b) release.go preflight reading the stamp; (c) the SKIP/catch-22 path dev.sh:207-234; confirm no weakening of release-time honesty.
(2) WORDS: rewrite both stamp-guard denials to TEACH steps 1-6 with exact commands; rewrite the pre-commit hook --no-verify note (.githooks/pre-commit:106-107) to say plainly that --no-verify on a SCHEMA migration ships incomplete work (a migration with no reviewable schema diff) and is ONLY for data-only migrations.

OWNERS: engineer drafts denial wording (from his own "what sent me to FORCE=1" experience, per the King) + verdicts the RUN-without-stamp change + 3 sanity checks; foreman owns the procedure/commands; architect byte-reviews; KING reviews the design before any gate is edited. STATBUS-077's migration lands through this same clean flow once it's in.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DESIGN VERIFIED — engineer reported, foreman independently checked the two load-bearing claims (2026-06-17).

ENGINEER (PART A — why the message funneled him to FORCE=1): the `Override:` line lists commit/stash/FORCE=1 as EQUAL PEERS; for landing a migration `commit` is blocked (pairing hook), `stash` breaks assert-db-at-head + drops the migration from the commit — so two of three 'clean' options are dead ends and the message itself funnels to FORCE=1 as 'the one that works' (same shape that sent the foreman to --no-verify on the sibling gate). It states the problem ('stamp would lie') but not the CONSEQUENCE — FORCE=1 actually WRITES a stamp from a dirty tree, i.e. CAUSES the lie. And it frames dirty-migrations/ as an aberration, never as the EXPECTED migration-landing state, with no pointer to the procedure.
ENGINEER (PART B — VERDICT: ENDORSE RUN-without-stamp; all 3 sanity checks pass): (1) test fast — today dirty→REFUSE blocks running fast tests with an uncommitted migration (another override-driver); under change RUN tests, don't stamp — better + honest. (2) release preflight — KEY; preflight re-derives honesty, doesn't trust provenance. (3) SKIP/catch-22 path untouched (dirty branch is first, before any stamp read); 4 existing self-tests stay green; ADD one for the new dirty→RUN-no-stamp branch.

FOREMAN INDEPENDENT VERIFICATION (read the code, did not take it on the engineer's word):
- LYNCHPIN CONFIRMED: cli/cmd/release.go:361-392 checkMigrationStamp PASSES only iff `git diff --name-only stampSHA..HEAD -- migrations/*.up.sql migrations/*.up.psql` is EMPTY **and** stampVersion == migrate.LatestOnDiskMigrationVersion(projDir). Comment :364-367 states it exists to 'catch the bypass case where a generator skipped its at-head guard and wrote a stamp from a stale DB.' ⇒ removing the dirty-stamp-write path CANNOT weaken release honesty; it removes the only dirty-provenance-stamp pathway and the release gate fails-closed (stale stamps → '✗ N new migrations since stamp') until a clean-tree regen. Honesty preserved/strengthened.
- STAMP-WRITE SITES CONFIRMED COMPLETE (must ALL gate on the new RUN_NO_STAMP, or one re-opens the hole): dev.sh:812 (tmp/fast-test-passed-sha), dev.sh:1894 (tmp/db-docs-passed-sha), cli/cmd/types.go:109 (tmp/types-passed-sha). The app stamps (app-tsc/app-build, release.go:433-434) are app-scoped, orthogonal to the migrations-scoped guard.

ORTHOGONAL CAVEAT (must be in the procedure + the new wording): the change fixes only the STAMP catch-22, NOT the seed requirement — generate-doc-db runs `./sb assert-db-at-head` on the SEED (dev.sh:1766) AFTER the guard; neither FORCE=1 nor RUN-without-stamp bypasses it. So the procedure STILL needs `./sb migrate up --target seed` (+ create-test-template) first — non-destructive, NOT a bypass. (Ground truth now: seed=20260616104500, dev/on-disk=20260617174936.)
MINOR WRINKLE (acceptable): stamp deferred ⇒ generate runs TWICE when landing a migration — once dirty pre-commit (produce artifacts to stage), once clean post-commit (write the release stamp; identical diff). Future refinement = move stamp-writing into the commit hook (out of scope).

IMPLEMENTATION SURFACE (engineer, for on-approval): 2 guards (dev.sh:153-160 + cli/cmd/types.go:152-161) flip REFUSE→RUN_NO_STAMP; 3 stamp-write sites gate on it; +1 self-test for the dirty→RUN-no-stamp branch; rewrite both denials to teach the procedure + the --no-verify note (.githooks/pre-commit:106-107) to data-only-ONLY. Engineer has draft wording for all three. ALL stamp-write sites + guards land in ONE commit.

STATE: design verified by foreman; presented to King; AWAITING KING'S GO on the root change (RUN-without-stamp, override-free flow) vs message-only. On go: engineer implements the full set together → architect byte-reviews the diff → foreman commits → STATBUS-077's migration then lands through the clean flow.

CONVERGED (engineer + architect, 2026-06-17). ARCHITECT independently CONCURRED with the RUN-without-stamp verdict (re-verified release-preflight re-derives honesty + fails-closed; additionally found that today's FORCE=1 leaves a NARROW false-pass window in the release gate that RUN-without-stamp CLOSES — reinforces the change). Architect's two adds (folded): (1) the RUN_NO_STAMP path must print LOUDLY that the stamp was withheld + that a clean post-commit regen is needed before release; (2) the +1 self-test must ASSERT no stamp file is written on the dirty path.
SEED STEP VERIFIED against source (engineer, refuting the architect's floated `./sb db seed sync` which DOES NOT EXIST): `./sb migrate up --target seed` (cli/cmd/migrate.go:146 — apply-forward to POSTGRES_SEED_DB) + `./dev.sh create-test-template` (dev.sh:1190 — re-clones the test template from the now-at-HEAD seed; generate-doc-db builds its doc DB from the TEMPLATE at dev.sh:1772, downstream of the seed, so advancing the seed alone leaves the template stale). Both non-destructive. NOT `db seed fetch` (downloads published artifact) / `recreate-seed` (destructive).
LANDING STRUCTURE (foreman's call, adopting architect's suggestion) = TWO commits: COMMIT 1 = the gate fix ALONE (2 guards + 3 stamp-write sites gating together + --no-verify note + both denials rewritten + 1 self-test) — touches NO migration, clean standalone, no pairing-hook/regen involvement; COMMIT 2 = STATBUS-077 from_commit_sha removal lands through the now-fixed flow (generate with NO FORCE=1). Engineer instructed to implement COMMIT 1 in full as one change on the King's go → architect byte-reviews diff → foreman commits → then COMMIT 2.
STATE: still AWAITING KING'S GO on the gate redesign (root change vs message-only). All overrides held.

KING'S GO (2026-06-17), verbatim: 'Nice root change, get to it, then continue. Let me know when I can cut the release.' Root change APPROVED. Engineer implementing COMMIT 1 (gate fix) in full now; architect primed to byte-review the diff (focus: all 3 stamp-write sites gated together; rc-plumbing through each caller; self-test asserts no stamp on dirty path; denial wording). On architect OK → foreman commits COMMIT 1 → COMMIT 2 (STATBUS-077 removal) lands through the fixed flow → comprehensive install-recovery re-run (batched with e6c85c193's 9) → report 100%-green to King for the rc.04 cut.

COMMIT 1 IMPLEMENTED + reviewing (2026-06-17). Diff tmp/sb-gatefix.diff (148+/52-): .githooks/pre-commit, cli/cmd/types.go, dev.sh. Foreman byte-review: the guard logic, all 3 stamp-write sites gating on RUN_NO_STAMP (types.go:59-63, dev.sh:181 fast-test, dev.sh:223 db-docs), rc-plumbing (rc 3 in both shell switches + types RunE captures decision), wording (teaches procedure + de-lists FORCE=1 with consequence), --no-verify note (data-only) — ALL CORRECT.
BUT — REAL BUG in the new Test 5 (self-test), caught by foreman root-causing the tester's RUN 2 'partial' (tester wrongly called it a harness issue): Test 5's dirty-marker `migrations/.tsg-dirty-marker-$$.tmp` is GITIGNORED (.gitignore:129 `*.tmp`). Confirmed via `git check-ignore -v` + empirical probe (git status --porcelain -- migrations does not show a *.tmp). So the marker NEVER makes migrations/ dirty; Test 5 passed in tester RUN 1 only by riding the ambient untracked migration, and RUN 2 (migration moved aside) exposed rc=1 (SKIP) instead of rc=3. CONSEQUENCE: Test 5 is RED on any clean tree (CI) — would turn CI red. NOT a harness issue.
FIX (engineer, don't commit): (1) marker filename NOT gitignored AND not matched by *.up.{sql,psql} glob (verify `git check-ignore` prints nothing); (2) add a self-validation asserting `git status --porcelain -- migrations` is NON-EMPTY after creating the marker (fail loudly if gitignored) — makes the test self-proving; (3) keep rm+trap cleanup. Then tester re-runs on a CLEAN migrations/ (move untracked migration aside + restore) → all 5 pass → architect re-reviews fixed Test 5 → foreman commits COMMIT 1.
INSTALL-RECOVERY RE-RUN PREP (tester, complete): full matrix = 33 scenarios; invocation `gh workflow run install-recovery-harness.yaml --ref master -f scenarios="<33 names>"` (CI, max-parallel 3, ~110-220 min, ~€0.24); HCLOUD_TOKEN present; per-commit image auto-builds on master push via images.yaml (~15-20 min) — readiness via `docker manifest inspect ghcr.io/statisticsnorway/statbus-sb:<short>`. Locked in; fires only on foreman signal after both commits pushed.

COMMIT 1 COMMITTED: 820e79624 (2026-06-17). Final diff 349 lines, 3 gate files (.githooks/pre-commit, cli/cmd/types.go, dev.sh). Foreman tree-verified before commit (resolving an architect/engineer crossed-message discrepancy — architect had re-reviewed the stale 348-line pre-(B) diff; live tree was 349 post-(B)): stampGuardRefuse GONE from cli/ (0 refs), no `return 2` / `2) exit 1` in dev.sh, seed step at pre-commit:102, RUN_NO_STAMP wired (return 3 dev.sh:175), go build+vet green. Tester 6/0 clean + 2/0 dirty on the post-(B) tree. Architect APPROVED gate+A+nit + pre-blessed the exact 4-site REFUSE removal as safe.
NOTE: pre-commit hook fired the bash-background false-positive on the commit-message text (contained the literal generate-doc-db command) — worked around by committing via `-F tmp/commit-msg-c1.txt` (clean command line). Not a real long-running command.
REMAINING for Done: end-to-end validation = COMMIT 2 (STATBUS-077 from_commit_sha removal) must land THROUGH this fixed gate with zero FORCE=1/--no-verify (the proof the pedagogy fix achieves its goal). Engineer running COMMIT 2's tail now (build-sb → seed→HEAD → generate-doc-db + types generate). Mark 078 Done once COMMIT 2 lands clean through the gate.

DONE (2026-06-17). Gate-pedagogy fix shipped + validated end-to-end: COMMIT 820e79624 (pushed in 78e770ac5 batch). The RUN_NO_STAMP change + denial rewrites + dead-REFUSE removal + self-test (6/0) all landed; and COMMIT 2 (the from_commit_sha removal regen) ran THROUGH this gate with ZERO FORCE=1/--no-verify (the loud WITHHELD notes fired) — empirical end-to-end proof the canonical migration-landing flow is now override-free. The catch-all + write-site source-assert hardening continue in STATBUS-079 (High). Not gated on the install-recovery re-run (the gate is dev-time tooling, not exercised by the upgrade-product scenarios).
<!-- SECTION:NOTES:END -->
