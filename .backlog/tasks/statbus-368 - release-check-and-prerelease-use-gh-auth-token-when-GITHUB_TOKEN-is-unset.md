---
id: STATBUS-368
title: >-
  release check / prerelease: use `gh auth token` when GITHUB_TOKEN is unset, and say which identity the gate is reading GitHub as
status: To Do
assignee: []
created_date: '2026-09-14 11:41'
updated_date: '2026-09-14 11:41'
labels:
  - release
  - cli
dependencies: []
priority: medium
type: bug
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
