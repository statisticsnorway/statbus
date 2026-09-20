---
id: STATBUS-379
title: >-
  sb release preflight should fall back to `gh auth token` when GITHUB_TOKEN is
  unset
status: To Do
assignee: []
created_date: '2026-09-20 14:36'
updated_date: '2026-09-20 14:36'
labels:
  - release
  - cli
dependencies: []
priority: low
type: bug
ordinal: 21
---

## Observed failure (2026-09-20)

The rc.21 cut failed with GitHub API HTTP 403. In
`cli/internal/release/check.go`, `githubAuthHeader()` sends no `Authorization`
header when `GITHUB_TOKEN` is unset, even when the operator is authenticated
through the GitHub CLI. The anonymous 60-requests/hour shared IP bucket had
been exhausted.

The same command succeeded immediately when run as:

    GITHUB_TOKEN=$(gh auth token) ./sb release prerelease

## Work

Make release preflight resolve authentication as `GITHUB_TOKEN` first, then
fall back to `gh auth token` when the environment variable is unset. Preserve a
clear anonymous fallback/error when neither source is available. Add focused
tests for precedence, successful GitHub CLI fallback, and absence of both.

This small P3 ticket records the concrete rc.21 preflight failure. It overlaps
the broader queued STATBUS-368 scope but does not inherit that ticket's larger
identity-reporting and Git transport work.

## Done when

`./sb release prerelease` succeeds on an operator machine authenticated only by
`gh auth login`, and tests prove that an explicit `GITHUB_TOKEN` still takes
precedence over `gh auth token`.
