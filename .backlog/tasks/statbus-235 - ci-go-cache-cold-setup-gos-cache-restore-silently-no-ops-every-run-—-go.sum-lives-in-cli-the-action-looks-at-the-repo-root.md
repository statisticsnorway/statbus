---
id: STATBUS-235
title: >-
  ci-go-cache-cold: setup-go's cache restore silently no-ops every run — go.sum
  lives in cli/, the action looks at the repo root
status: In Progress
assignee:
  - '@mechanic'
created_date: '2026-08-18 15:42'
updated_date: '2026-08-18 15:54'
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
- [x] #1 setup-go steps that build Go code carry cache-dependency-path: cli/go.sum — go-test.yaml and any sibling workflow using setup-go
- [ ] #2 A run after the fix shows the cache restore actually succeeding in the Set up Go step log, and a subsequent unchanged-cli run shows the speed benefit
- [x] #3 Verified that go test still runs with -count=1 on the same invocation (the STATBUS-234 guard) before the cache goes live
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-18 15:45
---
King's ruling 2026-08-18 (verbatim intent): fix issues we find, including this Go caching issue. Proceeding now — the ordering constraint is satisfied: STATBUS-234's -count=1 landed as 93804427e and is on master. Assigned @mechanic.
---

author: mechanic
created: 2026-08-18 15:51
---
Sweep + fix complete, frozen (no commits). Grepped every workflow in .github/workflows/ for `actions/setup-go` — 8 occurrences across 7 files, ALL now carry `cache-dependency-path: cli/go.sum`. None were left out; the sweep found no additional files beyond what the ticket named as likely (fast-tests.yaml, release workflows) plus go-test.yaml's second occurrence.

Files changed (7, +68/-0 total per `git diff --stat`):
- `.github/workflows/go-test.yaml` — 2 occurrences (go-test job, go-lint job). go-test job's comment cites the AC#3 dependency (go test ./... -count=1 at line 111, confirmed present). go-lint job's comment explicitly states it does NOT depend on -count=1 — it runs golangci-lint via `./dev.sh lint`, not `go test`, so caching carries none of STATBUS-234's staleness risk.
- `.github/workflows/fast-tests.yaml` — 1 occurrence, comment cites its own `go test ./internal/migrate/ -run TestDaemonFloorSchemaSufficient -count=1 -v` (line 215, confirmed present).
- `.github/workflows/upgrade-arc-harness.yaml`, `install-recovery-harness.yaml`, `test-hardening.yaml`, `test-install.yaml`, `release.yaml` — 1 occurrence each, short comment: build-only (go build / dev.sh build-sb), no go test invocation, so no STATBUS-234 dependency.

AC#3 confirmed on current tree: `go-test.yaml:111` → `go test ./... -count=1`; `fast-tests.yaml:215` → `...go test ./internal/migrate/ -run TestDaemonFloorSchemaSufficient -count=1 -v`. Both guards intact before the cache goes live.

Validation: `ruby -ryaml -e YAML.load_file` clean on all 7 files. `actionlint` on all 7: one finding, SC2129 style nit in release.yaml:23 — confirmed PRE-EXISTING via `git show HEAD:.github/workflows/release.yaml` (identical finding at the same line in the unmodified baseline), not introduced by this change. Zero new findings.

AC#2 (observing a real run's cache restore succeed) is pending — requires foreman to land + push before a live run can be observed.

All changes frozen in the working tree, uncommitted, per house git-mutation ownership rule.
---

author: foreman
created: 2026-08-18 15:54
---
LANDED as c1f20078c. Architect verdict: APPROVED with one required comment reword, applied at landing — the five build-only comments now state the RULE ("if you ever add a go test step it must carry -count=1"), not the current fact, because a fact rots silently the moment someone adds a test step with the cache live (the stale-premise class). His verified precondition: only go-test.yaml and fast-tests.yaml invoke go test, both guarded (:111, :215); the other five hits were prose inside the mechanic's own comments — his own first grep misread that prose as unguarded code, which he flagged as live proof of the 224 substring-vs-parse lesson. Sweep-completeness blessed (partial caching nobody could reason about later); build-cache-only workflows carry zero verdict risk (content-addressed, never replays a test verdict). Durable pin filed by the architect as STATBUS-237. AC#2 remains open: observe a real run's Set up Go step showing cache save (this landing's own go-test run) then restore (the next run).
---
<!-- COMMENTS:END -->
