---
id: STATBUS-035
title: >-
  branch-cleanup: delete the 13 fully-merged/retired remote branches (King
  approves, foreman executes)
status: To Do
assignee: []
created_date: '2026-06-12 07:57'
updated_date: '2026-07-03 10:45'
labels:
  - git-hygiene
  - not-install-upgrade
dependencies: []
references:
  - .github/workflows/
  - cli/cmd/seed.go
  - test/install-recovery/lib/vm-bootstrap.sh
priority: low
ordinal: 35000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
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
- [ ] #1 King approves the 13-branch delete list
- [ ] #2 The 10 non-dependabot branches deleted via `git push origin --delete`; foreman executes
- [ ] #3 The 3 Dependabot branches handled by CLOSING their PRs (not branch-delete), so Dependabot does not recreate them
- [ ] #4 The 11 keep-pending branches untouched (each routed to its owner for the one open question); the 12 never-delete set untouched
<!-- AC:END -->
