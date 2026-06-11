---
id: doc-008
title: Stale-branch cleanup analysis (2026-06-11)
type: specification
created_date: '2026-06-11 15:44'
tags:
  - cleanup
  - branches
  - ops
  - review-needed
---
# Stale-branch cleanup analysis — 2026-06-11

**Author:** engineer · **Status:** for King review · **Action:** DELETE NOTHING until the King approves; foreman executes after.

## TL;DR — the landscape is much smaller and cleaner than reported

- **Ground truth: 36 remote branches** (`git ls-remote --heads origin`), not ~70.
- **There is no 40-branch `seed/*` class.** The entire seed/snapshot family is **8 branches**. The earlier "~40 seed/*" estimate was wrong.
- **No `parked/*` or `wip/*` branches exist on origin** at all.
- The git-branch seed transport was **retired** (commit `9ee422652`, "the image is the sole seed source"). But **`db-seed` is still load-bearing**: every shipped release binary from `v2026.05.2` through `v2026.05.6-rc.03` fetches it via `git fetch origin db-seed`, and the install-recovery harness actively depends on it.

**Recommendation:** 13 branches confident-SAFE-to-delete · 11 KEEP-pending one specific question each · 12 NEVER-delete (master + deploy pointers + load-bearing `db-seed`).

## Methodology (every verdict is evidence-backed)

1. `git fetch --prune` then `git ls-remote --heads origin` → authoritative server-side list (36).
2. `git branch -r --merged origin/master` + `git rev-list --left-right --count master...<b>` → merged status and exact ahead/behind per branch.
3. Repo-wide + CI-workflow grep for live consumers of each branch name (`.github/workflows/`, `cli/`, `ops/`, `test/`, `dev.sh`).
4. `git log -S` archaeology on the seed/snapshot transport; **read the shipped pre-retirement `seed.go` (`v2026.05.4`)** to confirm exactly which branch the consume path fetches.

## The seed/snapshot family — the high-uncertainty class, fully resolved

**Lineage** (from `git log`): `snapshot/<sha>` pins → renamed to `seed/<sha>` pins (`3d5f1e02c`) → per-commit pin gate (`50fd4325f`) → **retired in favor of the Docker image** (`9ee422652`). The `statbus-seed:<commit_short>` image now "replaces the db-seed git branch transport" (`images.yaml:138-139`).

**What the consume path actually fetches** (read from shipped `v2026.05.4 cli/cmd/seed.go`): `git fetch origin db-seed` **primary**, falling back to `git fetch origin db-snapshot` **legacy** if `db-seed` is absent. It **never** fetches `seed/<sha>` or `snapshot/<sha>` by name — those were *publish-side archival pins* for the now-retired release preflight gate.

**Retirement ancestry** (`git merge-base --is-ancestor 9ee422652 <tag>`):
- `v2026.06.0-rc.01` → contains retirement (image-only, no git-branch fetch)
- `v2026.05.6-rc.03`, `v2026.05.5`, `v2026.05.4`, `v2026.05.3`, `v2026.05.2` → **all pre-retirement, still fetch `db-seed`**

So `db-seed` must stay until every deployed/tested binary ≤ `v2026.05.6-rc.03` is EOL. The commit-pins were never consumed by name and their creating gate is gone → safe.

## Full classification table

| Branch | Class | Last commit | behind/ahead vs master | Verdict | Reason |
|---|---|---|---|---|---|
| master | trunk | 2026-06-11 | — | **NEVER** | trunk |
| ops/cloud/deploy/demo | deploy ptr | 2026-03-31 | merged | **NEVER** | live deploy pointer |
| ops/cloud/deploy/dev | deploy ptr | 2026-05-07 | merged | **NEVER** | live deploy pointer |
| ops/cloud/deploy/et | deploy ptr | 2026-03-31 | merged | **NEVER** | live deploy pointer |
| ops/cloud/deploy/jo | deploy ptr | 2026-03-31 | merged | **NEVER** | live deploy pointer |
| ops/cloud/deploy/ma | deploy ptr | 2026-03-31 | merged | **NEVER** | live deploy pointer |
| ops/cloud/deploy/no | deploy ptr | 2026-03-31 | merged | **NEVER** | live deploy pointer |
| ops/cloud/deploy/production | deploy ptr | 2026-03-31 | merged | **NEVER** | live deploy pointer |
| ops/cloud/deploy/tcc | deploy ptr | 2026-03-31 | merged | **NEVER** | live deploy pointer |
| ops/cloud/deploy/ug | deploy ptr | 2026-03-31 | merged | **NEVER** | live deploy pointer |
| ops/standalone/deploy/rune-no | deploy ptr | 2026-05-06 | merged | **NEVER** | live deploy pointer (Norway/rune) |
| db-seed | seed transport | 2026-05-26 | 0/? | **NEVER (load-bearing)** | fetched by all shipped pre-retirement release binaries (`v2026.05.2`–`v2026.05.6-rc.03`) + active harness dep (`vm-bootstrap.sh:472,508`) |
| engineer/upgrade-recovery-validation | feature | 2026-05-25 | 312/0 | **SAFE-DELETE** | 0 unique commits — fully contained in master |
| fix/recovery-hardening-stop-loop-and-start-existing-db | fix | 2026-05-29 | 254/0 | **SAFE-DELETE** | 0 unique commits — fully in master |
| ui/minor-improvements | ui | 2026-05-15 | 473/0 | **SAFE-DELETE** | 0 unique commits — fully in master |
| seed/c823a88f | seed pin | 2026-05-26 | not merged | **SAFE-DELETE** | publish-side archival pin; consume path never fetches `seed/<sha>` by name; creating gate retired (`9ee422652`) |
| snapshot/2be9da13 | snapshot pin | 2026-04-26 | not merged | **SAFE-DELETE** | older snapshot-era archival pin; not consumed by name |
| snapshot/9ac0666c | snapshot pin | 2026-04-25 | not merged | **SAFE-DELETE** | same |
| snapshot/e1fe8456 | snapshot pin | 2026-04-25 | not merged | **SAFE-DELETE** | same |
| snapshot/b9bbceb7 | snapshot pin | 2026-04-24 | not merged | **SAFE-DELETE** | same |
| snapshot/e2355634 | snapshot pin | 2026-04-24 | not merged | **SAFE-DELETE** | same |
| feature/split-statistical-unit | legacy feature | 2023-10-03 | 5058/8 | **SAFE-DELETE** | dotnet/EF-era abandoned feature; architecturally superseded by the full PostgreSQL rewrite (its 8 commits are EF migrations that can never apply) |
| dependabot/go_modules/cli/.../pgx/v5-5.9.2 | dependabot | 2026-04-23 | 659/1 | **SAFE-DELETE** | stale dep bump; Dependabot recreates if still applicable |
| dependabot/npm_and_yarn/app/postcss-8.5.10 | dependabot | 2026-04-24 | 615/1 | **SAFE-DELETE** | stale dep bump |
| dependabot/npm_and_yarn/app/undici-7.24.0 | dependabot | 2026-03-24 | 1241/1 | **SAFE-DELETE** | stale dep bump |
| db-snapshot | legacy seed fallback | 2026-04-26 | not merged | **KEEP-pending** | legacy fallback name in shipped binaries; shadowed by live `db-seed` (stale, older content). Q: confirm no shipped binary relies on the `db-snapshot` fallback before retiring |
| debug/archive-partial-at-final-rootcause | debug | 2026-05-29 | 252/3 | **KEEP-pending** | 3 unique commits, recent campaign debug. Q: are the root-cause findings captured in master/doc/backlog? |
| engineer/image-distribution-design | design | 2026-05-26 | 312/1 | **KEEP-pending** | 1 unique commit = draft design doc "for user review"; the implementation shipped. Q: does the King still want the draft doc? |
| engineer/layer2-recovery-flag | feature | 2026-05-20 | 454/4 | **KEEP-pending** | 4 unique commits; `--recovery=auto` is NOT in master CLI. Q: feature still wanted, or superseded by what shipped? |
| test/upgrade-resume-new-scenarios | harness | 2026-05-28 | 264/2 | **KEEP-pending** | 2 unique commits incl. scenario 30 `kill-mid-rsync-resumable`, NOT in master. Q: merge scenario 30 or is it superseded? (campaign is active) |
| feat/statistical-variables-over-time-chart | ui (hhssb) | 2026-05-21 | 425/2 | **KEEP-pending** | another dev's UI WIP, 2 unique commits. Q: owner (hhssb) — still active? |
| feature/pg-oauth | prototype | 2026-01-13 | 1903/4 | **KEEP-pending** | pg OAuth prototype, 4 unique commits, 5mo old. Q: owner — abandon? |
| feature/pgadmin | feature | 2026-03-11 | 1359/8 | **KEEP-pending** | 8 unique commits, 3mo old. Q: owner — still wanted? |
| fix-custom-scripts | fix (E. Søberg) | 2026-03-28 | 1379/3 | **KEEP-pending** | another dev's Norway custom scripts, 3 unique commits. Q: owner — deployed-relevant? |
| legacy-dotnet-3-ms-sql | historical archive | 2023-06-02 | 5240/0 | **KEEP-pending** | deliberately-named legacy archive; 0-ahead (reachable from master, no commits lost if deleted). Q: King's discretion — keep as historical marker or delete? |
| legacy-dotnet-7-postgresql | historical archive | 2023-11-22 | 4970/0 | **KEEP-pending** | same — deliberate `legacy-` archive marker |

## Recommended DELETE list (13) — execute ONLY after King approval

```sh
# DO NOT RUN until the King approves. Foreman executes.
# Fully-merged feature/fix/ui branches (0 unique commits, all in master):
git push origin --delete engineer/upgrade-recovery-validation
git push origin --delete fix/recovery-hardening-stop-loop-and-start-existing-db
git push origin --delete ui/minor-improvements
# Retired seed/snapshot archival pins (publish-side, never consumed by name; gate retired):
git push origin --delete seed/c823a88f
git push origin --delete snapshot/2be9da13
git push origin --delete snapshot/9ac0666c
git push origin --delete snapshot/e1fe8456
git push origin --delete snapshot/b9bbceb7
git push origin --delete snapshot/e2355634
# dotnet/EF-era abandoned feature (architecturally superseded):
git push origin --delete feature/split-statistical-unit
# Stale Dependabot bumps (Dependabot recreates current ones):
git push origin --delete dependabot/go_modules/cli/github.com/jackc/pgx/v5-5.9.2
git push origin --delete dependabot/npm_and_yarn/app/postcss-8.5.10
git push origin --delete dependabot/npm_and_yarn/app/undici-7.24.0
```

Note on the 3 Dependabot deletes: cleanest path is to **close the PRs** (which deletes the branch) rather than delete the branch under an open PR, else Dependabot may recreate it. If the bumps are still wanted, leave them for review instead.

## KEEP-pending-investigation — the 11 with one open question each

These are NOT recommended for deletion. Each carries unique unmerged commits (or is a deliberate archive / load-bearing fallback). Resolve the per-row question (mostly: ask the owner, or confirm content is captured in master) before any deletion. Owners to consult: **hhssb** (`feat/statistical-variables-over-time-chart`), **Erik Søberg** (`fix-custom-scripts`), **King** (the rest + the two `legacy-dotnet-*` archives).

## Notable correction for the record

The raw estimate that seeded this task ("~70 branches, ~40 `seed/*`, plus `parked/*` and `wip/*`") does not match the server: there are **36 branches**, the seed/snapshot family is **8**, and **no `parked/*` or `wip/*` exist**. This is exactly why classification needed real judgment against ground truth rather than a count-based sweep.
