---
id: STATBUS-035
title: >-
  seed-branch-retirement: rebaseline the harness to the current stable, then
  delete db-seed and db-snapshot
status: In Progress
assignee: []
created_date: '2026-06-12 07:57'
updated_date: '2026-09-07 19:41'
labels:
  - git-hygiene
  - not-install-upgrade
dependencies: []
references:
  - .github/workflows/
  - cli/cmd/seed.go
  - test/install-recovery/lib/vm-bootstrap.sh
ordinal: 35000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why these two tickets are one piece of work

Both change what the install-recovery harness installs on a fresh VM before it
exercises an upgrade, and both are proven by the same thing: one full paid
harness run that is green at the new shape. Doing them separately would buy
that run twice. So: 035 is the rebaseline (what the VM starts from), 339 is
the honesty of the hop (who judges the upgrade). One implementer, one review,
one paid run, two tickets closed.

## Ground truth (2026-09-06)

- Current stable is `v2026.09.0`; newest candidate `v2026.09.0-rc.14`. There
  is no `v2026.05.*` or `v2026.07.*` box anywhere in the fleet.
- `0-happy-install` and `0-happy-upgrade` already pick their baseline
  dynamically via `select_release_baseline_from_repo` in
  `test/install-recovery/lib/release-baseline.sh` (newest release below the
  target). They are NOT the problem.
- Seven scenarios still hard-pin an extinct baseline as their default:
  `1-boot-advisory-too-early`, `1-boot-flag-stale-handoff`,
  `1-boot-startup-timeout`, `5-install-drifted-unit-reconciled` (v2026.05.4);
  `1-boot-concurrent-install`, `5-install-seed-on-populated` (v2026.05.2);
  `3-postswap-worker-ddl-deadlock` (v2026.07.0-rc.05).
- `test/install-recovery/lib/wedge-helpers.sh` (~line 528) synthesises the
  crash state that v2026.05.2's `executeUpgrade` left behind. That shape is
  extinct: no released binary produces it any more.
- `test/install-recovery/lib/vm-bootstrap.sh` (~line 1160) adds the
  `origin/db-seed` refspec so a pre-retirement release binary's git-branch
  seed can find it. Only binaries older than `v2026.05.6-rc.03` fetch it.
- `0-happy-upgrade` installs the dynamic baseline, then `upload_sb_to_vm`
  COPIES HEAD's `sb` over the installed binary (line ~149) and registers
  HEAD's SHA (line ~188), so HEAD judges HEAD. The Norway rc.02 incident was
  a released binary judging a new candidate, which this never exercises.
- Every harness VM today is `CADDY_DEPLOYMENT_MODE=development` with
  `UPGRADE_CHANNEL=stable` (vm-bootstrap.sh ~703, ~736). Rune is
  standalone + prerelease; no scenario has that shape.

## Work (035 half: what the VM starts from)

### R1. Retire the seven extinct pins with a written verdict each

For each of the seven scenarios, decide and write in the scenario header:

- **rebaseline**: the scenario's wedge is about the CURRENT recovery
  machinery, not the old binary's bug; switch its default to
  `select_release_baseline_from_repo` like the two happy paths;
- **extinct**: the scenario only reproduces a crash shape no released binary
  can produce any more (the v2026.05.2 `executeUpgrade` shape in
  `wedge-helpers.sh` is the known case); delete the scenario AND the helper
  code that only it used, and say so in the commit;
- **keep pinned with reason**: only if a specific released version is the
  point (e.g. a migration-gap arc). Expected count: zero. If one appears,
  write why.

No blind `sed`. `./dev.sh test-install-recovery --list` must show no
scenario defaulting to a `v2026.05.*` or `v2026.07.*` baseline afterwards.

### R2. Remove the db-seed wiring

Once R1 leaves no scenario installing a pre-retirement release, delete the
`origin/db-seed` refspec block from `vm-bootstrap.sh` and the
`SB_INSTALL_SKIP_SEED` switch that exists only to withhold it. A fresh
install at the current stable must not mention db-seed anywhere in its log.

### R3. Delete the held branches (LAST, after the paid run is green)

`git push origin --delete db-seed db-snapshot`. Then `git ls-remote origin`
shows only master, deploy pointers, the kept-deliberately branches
(pgadmin, pg-oauth), and live PR branches. Record the ls-remote output in
this ticket.

## Acceptance (035)

1. No scenario defaults to a pre-`v2026.08` baseline; each of the seven has
   a written rebaseline/extinct verdict in its header or its deletion commit.
2. `vm-bootstrap.sh` carries no db-seed reference; `grep -rn db-seed
   test/ ops/ cli/` finds only historical comments, if any.
3. The full install-recovery harness is green at the new baselines (the
   shared paid run, see 339).
4. Both branches deleted and the ls-remote output recorded here.

## Evidence (pre-paid-run, 2026-09-07, HEAD e5d392a22)

| acceptance | evidence |
|---|---|
| 1 no pre-`v2026.08` default; seven verdicts written | Sol: "seven R1 verdicts" intact through r3 |
| 2 no db-seed reference in bootstrap | Sol: R2 removed VM seed-refspec wiring, intact through r3 |
| 3 harness green at the new baselines | PENDING: the shared paid run (owner approval required) |
| 4 both branches deleted, ls-remote recorded | PENDING: after 3 is green; `origin/db-seed` and `origin/db-snapshot` still exist at the time of writing |

## Staffing

One headless implementer does 035 R1+R2 and 339 H1..H4 together, test-first
with the harness's own local tests (`test/install-recovery/tests/`,
`--print-selected`, `--list`, `bash -n`, shellcheck). One adversarial review
of the combined diff. Then ONE paid full harness run, dispatched only after
the coordinator asks the owner. R3 only after that run is green.

## Original description (verbatim)

Origin is clean except two held branches: db-seed and db-snapshot. Only shipped binaries ≤ v2026.05.6-rc.03 fetch them, and no deployed box runs those anymore — the sole remaining consumer is our own install-recovery harness, which pins v2026.05.x as upgrade-from baselines (vm-bootstrap.sh wires the db-seed refspec at ~:876-946 exactly for those old release binaries).

Fix, KING-DIRECTED 2026-09-02: rebaseline the harness onto the current stable, then release the hold and delete both branches.
1. Move the default INSTALL_VERSION pins (4× v2026.05.4, 3× v2026.05.2, 1× v2026.07.0-rc.05) to the current stable (v2026.08.1, or the newer stable if promoted first) — more representative: no real box upgrades from v2026.05.x anymore.
2. Per-scenario judgment, not blind sed: wedge-helpers.sh synthesizes v2026.05.2's specific crash shape (:531-545), and 0-happy-upgrade's comment relies on the baseline predating sbAlreadyAtCommit (:124). Each old-pin scenario either moves to the new baseline with adjusted synthesis, or is retired as reproducing an extinct state — named verdict per scenario.
3. Remove the db-seed refspec wiring from vm-bootstrap.sh once no scenario installs a pre-retirement release.
4. Prove with a full install-recovery run at the new baselines (rides a release gate).
5. Then delete origin/db-seed and origin/db-snapshot — the last action of the branch-cleanup campaign; origin becomes: master, deploy pointers, kept-deliberately (pgadmin, pg-oauth), and live PR branches only.

Acceptance: no scenario defaults to a pre-v2026.08 baseline without a written extinct-state verdict; vm-bootstrap.sh carries no db-seed reference; full harness green at the new baselines; both branches deleted and verified absent.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 King approves the 13-branch delete list
- [x] #2 The 10 non-dependabot branches deleted via `git push origin --delete`; foreman executes
- [x] #3 The 3 Dependabot branches handled by CLOSING their PRs (not branch-delete), so Dependabot does not recreate them
- [x] #4 The 11 keep-pending branches untouched (each routed to its owner for the one open question); the 12 never-delete set untouched
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer (board sweep)
created: 2026-07-06 15:59
---
FOLDED IN from STATBUS-038 (merged 2026-07-06): same activity — one branch-hygiene sitting with the King. 035 = the 13 approved deletes; 038 = the 11 keep-pending walk. Handle in one branch session.
---

author: foreman
created: 2026-07-12 15:06
---
KING APPROVED the listed 13-branch cleanup (2026-07-12 evening). Pre-delete verification (`git ls-remote --heads origin` + `gh pr list`, run BEFORE issuing any delete) found the outcome already achieved: all 13 listed branches are GONE from origin — the 10 non-dependabot refs absent, the 3 dependabot PRs closed and their branches not recreated. Nothing was deleted in this sitting; the approval is satisfied by verified absence. The two guard sets are intact: never-delete 12 (master, 11 deploy pointers, db-seed) all present; keep-pending 11 all present and untouched.

NEW STATE not covered by this approval, surfaced by the same verification: (a) two NEW open Dependabot PRs — #309 (golang.org/x/crypto 0.52.0) and #308 (undici 7.28.0) — these are current bumps, not stale cleanup; routed to the King as a review/merge question, not a delete. (b) ~100 test/upgrade-arc-* throwaway branches from the STATBUS-071 framework plus red/031-rollback-watchdog — no retention policy exists; broken out as STATBUS-165.

Remaining on this ticket: AC #4's owner walk of the 11 keep-pending branches (the folded STATBUS-038 King sitting — hhssb, Erik Søberg, King).
---

author: foreman
created: 2026-07-13 08:15
---
DEPENDABOT PRs RESOLVED per the King's morning directive and the STATBUS-049 written procedure (bump, then run that ecosystem's gates): #309 (golang.org/x/crypto 0.51.0→0.52.0) and #308 (undici 7.25.0→7.28.0) merged LOCALLY in one merge commit (dc271478d), gates green on both ecosystems — Go: vet/build/test all packages ok; app: tsc clean, jest suites pass, production build clean — then pushed; GitHub marked both PRs MERGED at 08:13:53Z and dependabot deletes their branches. No dependabot branches remain open.
---

author: foreman
created: 2026-07-13 11:13
---
KEEP-PENDING WALK — owner-branch verdicts, foreman-VERIFIED against master (2026-07-13; corrects an operator error). (1) feat/statistical-variables-over-time-chart (hhssb): SAFE TO DELETE — fully content-superseded. Every file both branch commits touch is BYTE-IDENTICAL in master (chart, page, layout, history-reports wiring, and the postal_region_code export removal — verified file-by-file). The feature landed in master via a different commit path; the branch is a stale duplicate, no unmerged work. (The operator's report claimed 'content exists only on this branch' — FALSE; it conflated 'tip not an ancestor of master' with 'files absent'. The King's own read 'seems merged logically' was correct.) hhssb consult NOT needed — nothing to lose. (2) fix-custom-scripts (Erik Søberg): GENUINELY UNMERGED, KEEP pending Erik. custom/no.sql (Norway: hide stat idents, tax-ident→org-number rename) is ABSENT from master; custom/ke.sql EXISTS in master but DIFFERS. 2645 commits behind, ~31-line delta. Real work — deleting loses it. Route to Erik: port custom/no.sql, reconcile custom/ke.sql, confirm the custom/ ingestion pattern still holds + no schema drift broke the assumptions.

Earlier-verdict branches (operator sweep, foreman-relayed): db-snapshot (no shipped binary references it — note: legacy `git fetch origin db-snapshot` remediation code lives in v2026.05.2's seed.go, so keep until ≤ that tag is EOL, same rule as db-seed), debug/archive-partial-at-final-rootcause (findings in master — delete-safe), engineer/image-distribution-design (stale draft doc, no master equivalent — King: keep-to-docs or delete), engineer/layer2-recovery-flag (--recovery=auto superseded by the shipped recovery ladder — delete-safe), test/upgrade-resume-new-scenarios (scenario 30 covered by the arc campaign — delete-safe), red/031-rollback-watchdog (proof build, scenario shipped — delete-safe), feature/pg-oauth + feature/pgadmin (unshipped prototypes — King's discretion). Awaiting the King's per-branch go.
---

author: foreman
created: 2026-07-13 11:56
---
WALK EXECUTION (2026-07-13, King directives): DELETED feat/statistical-variables-over-time-chart (content-superseded, verified) + engineer/image-distribution-design (intent shipped — per-commit statbus-sb image + install.sh --commit are live; the 242-line draft doc's concept is realized). KEPT: feature/pgadmin (now the FOUNDATION for STATBUS-173, builds on it — not a delete-candidate), feature/pg-oauth (King: belongs to another project, keep until he moves it), fix-custom-scripts (Erik's work — operator analyzing no.sql/ke.sql content vs master for the KING to judge intent; the King judges, not Erik). SEQUENCING HOLD (King): the seed-class branches db-seed + db-snapshot are NOT deleted now — they go AFTER we cut RC and R and the fleet is fully off the binaries that fetch them (shipped binaries ≤ v2026.05.6-rc.03 fetch db-seed; the install-recovery harness also depends on db-seed at vm-bootstrap.sh:472,508 — so db-seed additionally waits until the harness is weaned). db-snapshot rides the same after-RC/R timing. Remaining delete-safe pending the King's per-branch go: debug/archive-partial-at-final-rootcause, engineer/layer2-recovery-flag, test/upgrade-resume-new-scenarios, red/031-rollback-watchdog.
---

author: foreman
created: 2026-07-13 11:58
---
fix-custom-scripts CONTENT ANALYSIS (operator, foreman-VERIFIED 2026-07-13) — for the King's intent judgment. custom/ke.sql: master SUPERSEDES the branch. Master commit ea721b8c5 (2026-03-13, 'Replace custom reset hack with public.reset(getting-started)') rewrote ke.sql's reset call AND DELETED custom/reset.sql (61 lines) — so the branch's `\ir ./reset.sql` references a file master no longer has; the branch also sets `enabled=TRUE` where master sets `FALSE` (opposite intent on hiding the default Kenya ident type). Porting the branch's ke.sql as-is would regress to deleted/broken code. VERDICT: do NOT port ke.sql; master's is production-current. custom/no.sql: NET-NEW (absent from master), a Norway customization — hide all external_ident_type except tax_ident, rename tax_ident→'Org.Number'. It uses the SAME old `\ir ./reset.sql` pattern, so if ported it must be MODERNIZED to `SELECT public.reset(true,'getting-started')` first. THE KING'S DECISION (roadmap, his to make): does Norway want this ident-hiding/rename customization? YES → port no.sql modernized, then the branch retires; NO → drop the branch. The branch's only live value is no.sql; ke.sql is dead against master. Full evidence: tmp/operator-custom-scripts-analysis.md.
---

author: foreman
created: 2026-07-23 15:54
---
WALK EXECUTION 2 (2026-07-23, King directives in chat): DELETED on the King's GO, verified absent — debug/archive-partial-at-final-rootcause, engineer/layer2-recovery-flag, test/upgrade-resume-new-scenarios, red/031-rollback-watchdog. fix-custom-scripts RETIRED per STATBUS-174's own recorded plan (the King confirmed 174 is where the Norway decision lives; no.sql intent preserved verbatim there, tip 7b01c88cb recorded; verified absent from origin). LEGACY-DOTNET ANSWER for the King's history question, empirically verified: BOTH legacy-dotnet-3-ms-sql (3412 commits) and legacy-dotnet-7-postgresql (3682 commits) are FULLY CONTAINED in master (merge-base ancestor check) — deleting them loses ZERO history; the branch names are only labels/signposts on commits master already carries forever. Awaiting the King's one word on that pair. REMAINING on this ticket after that word: only the seed-class sequencing holds (db-seed + db-snapshot go after RC + stable release + fleet off old binaries + harness weaned — the King's 2026-07-13 ruling).
---

author: foreman
created: 2026-07-23 16:23
---
TRIAGE COMPLETE — FINAL DISPOSITION TABLE (2026-07-23, King's closing directives; recorded so this triage is NEVER repeated). Every one of the original 36 branches is now accounted for:
· DELETED, fully-merged/retired (the 13-list): done 2026-07-12 by verified absence.
· DELETED in the walk: feat/statistical-variables-over-time-chart, engineer/image-distribution-design (2026-07-13); debug/archive-partial-at-final-rootcause, engineer/layer2-recovery-flag, test/upgrade-resume-new-scenarios, red/031-rollback-watchdog (2026-07-23, King GO); legacy-dotnet-3-ms-sql + legacy-dotnet-7-postgresql (2026-07-23, King order — both verified FULLY CONTAINED in master first: 3412/3682 commits all reachable, zero history lost, only the labels removed).
· RETIRED with intent preserved: fix-custom-scripts → STATBUS-174 carries the Norway no.sql intent verbatim + all King directives (semantic codes, Organisasjonsnummer label, reconciliation resolved); ke.sql confirmed dead. Tip 7b01c88cb recorded there.
· KEPT deliberately: feature/pgadmin (foundation for STATBUS-173), feature/pg-oauth (King: belongs to another project, keep until he moves it).
· NEVER-DELETE: master + 11 deploy pointers.
· SEQUENCING HOLD (the ONLY remaining action on this ticket): db-seed + db-snapshot delete AFTER the RC + stable release land, the fleet is off binaries ≤ v2026.05.6-rc.03, and the harness is weaned off db-seed (vm-bootstrap.sh:472,508) — King ruling 2026-07-13. The ticket closes when that hold releases and the two are deleted.
AC#4 checked — the keep-pending walk is complete; no owner question remains open anywhere.
---

author: foreman
created: 2026-07-27 16:01
---
LOCAL-CLONE APPENDIX (2026-07-27, King ruling: 'keep for now'): the King's clone carried local-only leftovers surfaced by his git-gone run. RESOLVED: four stale agent worktrees removed (all verified clean, branches contained in master) + six contained/pinned local branches deleted. KEPT on the King's word: parked/015-container-restart-superseded, red/031-rollback-watchdog (local twin), wip/rc.42-broken-70x, fix/upgrade-resume-start-phase-timeout, feature/mint-prototype, feat/import-definition-editor — all local-only, no origin presence, revisit at his leisure. The 49 local seed/<sha> branches ride the existing post-release seed-family hold. Origin itself is clean (master + 11 deploy pointers + db-seed/db-snapshot held + pgadmin/pg-oauth kept + the weekly-swept test churn).
---
<!-- COMMENTS:END -->

## Status (2026-09-07 19:41): In Progress

Code landed and Sol-accepted (`e5d392a22`). Waiting on: the batch RC ladder green (owner-gated), then R3 branch deletion.
