---
id: STATBUS-235
title: >-
  ci-go-cache-cold: setup-go's cache restore silently no-ops every run — go.sum
  lives in cli/, the action looks at the repo root
status: In Progress
assignee:
  - '@mechanic'
created_date: '2026-08-18 15:42'
updated_date: '2026-08-18 15:45'
labels:
  - ci
  - tooling
dependencies:
  - STATBUS-234
references:
  - .github/workflows/go-test.yaml
priority: low
type: enhancement
ordinal: 235000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every CI Go run rebuilds and retests from scratch because the module cache restore never actually restores anything. Fixing one line would make CI meaningfully faster — but only after the -count=1 guard from STATBUS-234 is in place, because a live cache is exactly what makes stale pin greens reachable.

WHAT THE EVIDENCE SHOWS (mechanic, 2026-08-18, from real run logs — STATBUS-234 comment #1): `actions/setup-go@v5` with its default `cache: true` looks for `go.sum` at the repository root, but this repo's go.mod/go.sum live in `cli/`. The Set up Go step logs, on every run checked (e.g. run 32151213525):
`##[warning]Restore cache failed: Dependencies file is not found ... Supported file pattern: go.sum`
So GOCACHE starts cold every run and every test line shows a real timing, never "(cached)". Confirmed across multiple consecutive board-only-push run pairs whose cli/ diff was empty.

THE FIX: add `cache-dependency-path: cli/go.sum` to the setup-go step in go-test.yaml (and any other workflow using setup-go with Go builds — check fast-tests.yaml and the release workflows).

ORDERING CONSTRAINT (the reason this depends on STATBUS-234): the moment the cache goes live, Go's test cache can replay results across runs — and the pin family reads files outside the module that the cache does not track. STATBUS-234's `-count=1` is what makes a warm cache safe for the pin tests. Never apply this fix on a tree that lacks it.

WHAT IS ACHIEVED: CI stops rebuilding the Go toolchain output from scratch on every push — a real speed win on every Go-touching run — without reopening the stale-green hole that STATBUS-234 closed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 setup-go steps that build Go code carry cache-dependency-path: cli/go.sum — go-test.yaml and any sibling workflow using setup-go
- [ ] #2 A run after the fix shows the cache restore actually succeeding in the Set up Go step log, and a subsequent unchanged-cli run shows the speed benefit
- [ ] #3 Verified that go test still runs with -count=1 on the same invocation (the STATBUS-234 guard) before the cache goes live
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-18 15:45
---
King's ruling 2026-08-18 (verbatim intent): fix issues we find, including this Go caching issue. Proceeding now — the ordering constraint is satisfied: STATBUS-234's -count=1 landed as 93804427e and is on master. Assigned @mechanic.
---
<!-- COMMENTS:END -->
