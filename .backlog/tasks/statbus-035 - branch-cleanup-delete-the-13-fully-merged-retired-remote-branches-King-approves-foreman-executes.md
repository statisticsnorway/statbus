---
id: STATBUS-035
title: >-
  branch-cleanup: delete the 13 fully-merged/retired remote branches (King
  approves, foreman executes)
status: To Do
assignee: []
created_date: '2026-06-12 07:57'
updated_date: '2026-07-13 11:58'
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
> NORTH STAR: every visible branch is live.
> BENEFIT: 13 evidence-backed dead branches stop inviting wasted investigation (dead code has already misdirected root-cause work twice in this repo), and the 11 keep-pending branches each get their one owner answer instead of ambient uncertainty forever.
> STAGE: Hygiene.
> COMPLEXITY: one King sitting (approve + walk), then foreman-executes the deletes; owner-gated ones route to hhssb / Erik Søberg.
> DEPENDS ON: nothing.

---

Actionable branch cleanup, folded from the engineer's full 36-branch analysis (was doc-008; consolidated into this ticket per the 2026-06-12 King convention that plans live in tickets). DELETE NOTHING until the King approves; foreman executes after.

GROUND TRUTH (git ls-remote --heads origin): **36** remote branches, not the ~70 estimated. The seed/snapshot family is **8** branches, not ~40. No parked/* or wip/* exist. Every verdict is evidence-backed: merged status via `git rev-list --left-right --count master...<b>`, live-consumer grep across .github/cli/ops/test/dev.sh, and `git log -S` archaeology on the seed transport.

== DELETE — 13 confident-safe (execute ONLY on King approval) ==
Fully-merged feature/fix/ui (0 unique commits, all in master):
1. engineer/upgrade-recovery-validation
2. fix/recovery-hardening-stop-loop-and-start-existing-db
3. ui/minor-improvements
Retired seed/snapshot archival pins (publish-side; the consume path never fetched seed/<sha> or snapshot/<sha> by name; the creating gate was retired in 9ee422652):
4. seed/c823a88f
5. snapshot/2be9da13
6. snapshot/9ac0666c
7. snapshot/e1fe8456
8. snapshot/b9bbceb7
9. snapshot/e2355634
dotnet/EF-era abandoned feature (superseded by the PostgreSQL rewrite; its 8 commits are EF migrations that can never apply):
10. feature/split-statistical-unit
Stale Dependabot bumps (handle by CLOSING the PR — which deletes the branch; deleting the branch under an open PR lets Dependabot recreate it):
11. dependabot/go_modules/cli/github.com/jackc/pgx/v5-5.9.2
12. dependabot/npm_and_yarn/app/postcss-8.5.10
13. dependabot/npm_and_yarn/app/undici-7.24.0

Commands (foreman runs the 10 non-dependabot after approval; closes the 3 PRs for the dependabot set):
  git push origin --delete engineer/upgrade-recovery-validation
  git push origin --delete fix/recovery-hardening-stop-loop-and-start-existing-db
  git push origin --delete ui/minor-improvements
  git push origin --delete seed/c823a88f
  git push origin --delete snapshot/2be9da13
  git push origin --delete snapshot/9ac0666c
  git push origin --delete snapshot/e1fe8456
  git push origin --delete snapshot/b9bbceb7
  git push origin --delete snapshot/e2355634
  git push origin --delete feature/split-statistical-unit

== NEVER delete (12) ==
master; the 11 deploy pointers ops/cloud/deploy/{demo,dev,et,jo,ma,no,production,tcc,ug} + ops/standalone/deploy/rune-no; and **db-seed** (load-bearing: every shipped pre-retirement binary v2026.05.2–v2026.05.6-rc.03 fetches it via `git fetch origin db-seed`, and the harness depends on it at vm-bootstrap.sh:472,508). db-seed stays until every deployed/tested binary ≤ v2026.05.6-rc.03 is EOL.

== KEEP-pending — 11, each needs ONE owner answer (foreman does NOT decide these) ==
db-snapshot (legacy fallback name in shipped binaries — confirm no binary relies on it before retiring); debug/archive-partial-at-final-rootcause (3 commits — findings captured in master/doc?); engineer/image-distribution-design (1-commit draft doc — King: still wanted?); engineer/layer2-recovery-flag (4 commits, --recovery=auto not in master — superseded?); test/upgrade-resume-new-scenarios (scenario 30 kill-mid-rsync-resumable not in master — merge or superseded?); feat/statistical-variables-over-time-chart (hhssb's UI WIP); feature/pg-oauth (5mo prototype); feature/pgadmin (8 commits, 3mo); fix-custom-scripts (Erik Søberg's Norway scripts); legacy-dotnet-3-ms-sql + legacy-dotnet-7-postgresql (deliberate historical archive markers, 0-ahead — King's discretion). Owners to consult: hhssb, Erik Søberg, King.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 King approves the 13-branch delete list
- [x] #2 The 10 non-dependabot branches deleted via `git push origin --delete`; foreman executes
- [x] #3 The 3 Dependabot branches handled by CLOSING their PRs (not branch-delete), so Dependabot does not recreate them
- [ ] #4 The 11 keep-pending branches untouched (each routed to its owner for the one open question); the 12 never-delete set untouched
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
<!-- COMMENTS:END -->
