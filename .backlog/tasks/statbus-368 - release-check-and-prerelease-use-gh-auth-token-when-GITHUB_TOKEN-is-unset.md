---
id: STATBUS-368
title: >-
  release check / prerelease: use `gh auth token` when GITHUB_TOKEN is unset,
  and say which identity the gate is reading GitHub as
status: In Progress
assignee: []
created_date: '2026-09-14 11:41'
updated_date: '2026-09-23 15:10'
labels:
  - release
  - cli
dependencies:
  - STATBUS-370
priority: medium
type: bug
ordinal: 20
---

## Ground truth

`githubAuthHeader()` in `cli/internal/release/check.go:332` sends a Bearer
token only when `GITHUB_TOKEN` is set. Every developer machine here is
logged in via `gh auth login`; none exports `GITHUB_TOKEN`. So the release
gate reads GitHub anonymously: 60 requests/hour shared by every process on
the host's IP. On 2026-09-14 a 30 s poll of `./sb release check` hit 403
after ~20 minutes and the gate reported all three workflow checks as
"GitHub API error HTTP 403", which reads like a CI problem.

## Work

1. Token resolution order: `GITHUB_TOKEN` env, else `gh auth token` (exec,
   ignore failure), else anonymous. Same helper for every GitHub read in
   `cli/internal/release` and `cli/cmd/release`.
2. The preflight table's first GitHub-reading line says which identity it
   used: `(GitHub: authenticated via GITHUB_TOKEN | via gh auth | anonymous,
   60/h)`. On a 403 with anonymous auth the Fix line says `gh auth login` or
   `GITHUB_TOKEN`, not "check network connectivity".
3. Tests: helper returns env token first; falls back to a stubbed `gh`
   on PATH; anonymous when neither. 403 message names the auth mode.

## Done when

`./sb release check` on a machine with only `gh auth login` reports
"via gh auth" and stays green through 100 consecutive runs (no 403).

## Built and accepted, held in scratch until rc.05 is cut (2026-09-14 13:37)

Scratch `$JCODE_SCRATCH_DIR/statbus-368`, branch `statbus-368`, commits
`f6d4ae2f7` (one `GitHubAuth()` helper, GITHUB_TOKEN -> `gh auth token` ->
anonymous; preflight prints the mode once; anonymous 403 says `gh auth
login`) and `1fe04e1a9` (every git ls-remote/fetch of GitHub in the release
code carries the resolved token via STATBUS-341's GIT_CONFIG_* extraheader
env; anonymous inherits the env byte-for-byte; stub-git test proves env not
argv). Luna (pawprint) round 1 REJECT (git reads bypassed the helper), round
2 ACCEPT: `tmp/STATBUS-368-367-review.md`. `upgrade.gitFetchEnv()` stays
env-only on purpose: boxes have no `gh`.

Done-when's 100-run test is the coordinator's poller on the next cut.

## Batch sequencing (owner ruling 2026-09-15)

This ticket lands in the ONE batch after the current release: it does not
touch master until v2026.09.1-rc.08 (or the first later rc that goes fully
green) has been installed on Norway and promoted to stable. Then all batch
tickets land in one push, one candidate, one ladder. Position in that push:
**2 of 8**. release gate uses gh auth token; built and Luna-accepted in scratch (f6d4ae2f7 + 1fe04e1a9)

Batch order: 370 -> 368 -> 367 -> 363 -> 357 -> 361 -> 362 -> 359.

## Update 2026-09-22

**Duplicate:** STATBUS-379 records the same `GITHUB_TOKEN` then `gh auth token`
fallback defect for release preflight. Keep both files for history. STATBUS-368
is the broader form because it also requires identity reporting and authenticated
Git transport coverage. Neither duplicate is deleted or closed by this sweep.

## Reconciliation 2026-09-23

Classification: PARTIAL. Evidence: scratch fallback implementation only; not on master and no next-candidate proof.

Remaining: Land GH_TOKEN fallback in both release checks, add tests, and prove it in the next release.
