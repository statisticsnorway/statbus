---
id: STATBUS-235
title: >-
  ci-go-cache-cold: setup-go's cache restore silently no-ops every run — go.sum
  lives in cli/, the action looks at the repo root
status: Done
assignee:
  - '@mechanic'
created_date: '2026-08-18 15:42'
updated_date: '2026-08-18 16:48'
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
- [x] #2 A run after the fix shows the cache restore actually succeeding in the Set up Go step log, and a subsequent unchanged-cli run shows the speed benefit
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

author: mechanic
created: 2026-08-18 16:04
---
AC#2 empirical check (run 32157266530, workflow go-test.yaml, commit c1f20078c — the 235 landing itself, confirmed via `git show c1f20078c --stat` touching exactly the 7 workflow files). Checked both jobs' "Set up Go" step logs via `gh run view --log`.

CONFIRMED — the old failure mode is GONE: no `##[warning]Restore cache failed: Dependencies file is not found` in either job. Both jobs' Set up Go logs now show `cache-dependency-path: cli/go.sum` recognized, and (correctly, since this is the FIRST run under the new dependency-path-keyed cache key) `Cache is not found` on restore — that is the expected first-run miss, not a repeat of the old failure.

SAVE side confirmed for one job: `cli golangci-lint (...)`'s Post Set up Go step ran and logged `Cache saved with the key: setup-go-Linux-x64-ubuntu24-go-1.25.5-28359ad5dd9284ac20fd35d6c87fbe246b9bb5d38ead3b928363d98f1964004a`. GOCACHE is genuinely being populated now.

SAVE side NOT confirmed for the other job: `cli go test ./...`'s Post Set up Go step shows conclusion `skipped` — because that job's later `go test` step FAILED (unrelated: `TestRealRepo_PreRebaselineTagIsDisconnected_STATBUS233`, a self-diagnosing test whose own failure message says its premise changed — v2026.05.5 is now an ancestor of HEAD via history regraft — not a caching issue, flagging separately below). actions/setup-go's post-step (cache save) does not run when an earlier required step in the job fails, so this job's cache never got populated on this run.

RESTORE-side proof (a genuinely warm cache being pulled, with the timing benefit) is still pending — needs a NEXT workflow-touching push, as you flagged. Noting pending, not closing AC#2.

SEPARATE FINDING, out of scope for 235, flagged not fixed: `cli/cmd` package's `TestRealRepo_PreRebaselineTagIsDisconnected_STATBUS233` is currently FAILING on master (this same run, unrelated to the cache work) — real failure, not flaky: v2026.05.5 has become an ancestor of HEAD (history was re-grafted) and the test's own message says its premise changed and the gate's refusal wording needs re-reading. No open STATBUS-233 ticket found in .backlog/tasks/ to attach this to — surfacing it here so it isn't silently dropped.
---

author: mechanic
created: 2026-08-18 16:47
---
AC#2 RESTORE-side proof (run 32160081622, go-test.yaml @ 8147551e2 — the 239 unbreak, cli/-touching). Both jobs now completed SUCCESS end to end (the STATBUS-233 canary test that failed the prior run is fixed by 8147551e2, unrelated to caching). Checked both jobs' Set up Go logs via `gh run view --log` and job timing via `gh run view --json jobs`.

(1) RESTORE CONFIRMED, both jobs: `Cache hit for: setup-go-Linux-x64-ubuntu24-go-1.25.5-28359ad5dd9284ac20fd35d6c87fbe246b9bb5d38ead3b928363d98f1964004a` → `Cache restored successfully` → `Cache restored from key: ...`. Same primary key the golangci-lint job SAVED at the c1f20078c run — this is a genuine warm-cache hit, not a coincidental re-save.

(2) TIMING BENEFIT CONFIRMED. Comparing this warm run against the cold run (32157266530 @ c1f20078c, same workflow, same jobs):
- golangci-lint job wall time: cold 49s (15:54:23–15:55:12) → warm 23s (16:24:03–16:24:26) — ~2.1x faster.
- go-test job wall time: cold 62s (15:54:23–15:55:25) → warm 55s (16:24:04–16:24:59) — smaller win, expected: `-count=1` (STATBUS-234's guard) forces the actual test binaries to re-run regardless of cache, so only the BUILD/module-resolution phase benefits. That phase's win is clean and large: the cold run's `go vet` step logged eleven `go: downloading ...` lines and took ~19.7s (15:54:48.795→15:55:08.490); the warm run's `go vet` step logged ZERO download lines and took ~2.9s (16:24:39.021→16:24:41.941) — GOMODCACHE was warm too, not just GOCACHE.

(3) SAVE SIDE, go-test job: NOT a new save this run — setup-go logged `Cache hit occurred on the primary key ..., not saving cache` for BOTH jobs. Correct/expected behavior: an exact primary-key hit means there is nothing new to save; a re-save would only happen if the key's inputs (go.sum) changed while build outputs differ, which didn't happen here. The go-test job's cache is still only ever populated by whichever run first gets an exact-key MISS (the golangci-lint job at c1f20078c, since go-test's own job failed that run before its Post step could run) — not itself a problem, since both jobs share the identical cache key and either one populating it benefits both.

AC#2 checked. All three of STATBUS-235's acceptance criteria are now satisfied: #1 (fix applied, swept), #2 (restore + timing benefit empirically observed), #3 (-count=1 guard confirmed present before the cache went live). Ticket now only awaits final close.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CI's Go cache now actually works: every setup-go step across seven workflows names cli/go.sum, ending years of the restore silently no-oping because the action searched the repo root while go.sum lives in cli/. Empirically proven end-to-end on real runs: the c1f20078c run saved the first cache; the 8147551e2 run hit and restored it in both jobs — the golangci-lint job's wall time halved (49s cold → 23s warm), and go vet went from 11 module downloads / 19.7s cold to zero downloads / 2.9s warm, showing GOMODCACHE warm alongside GOCACHE. The go-test job's smaller win is by design: STATBUS-234's -count=1 guard forces tests to physically re-run regardless of cache — the exact property that makes a warm cache safe for the pin-test family, and the reason this fix was sequenced strictly after that guard. The five build-only workflows carry the architect's rule-stating comment (any future go test step must carry -count=1), with the parse-based enforcement pin filed as STATBUS-237. Built by mechanic, approved by architect with one comment reword applied at landing, landed as c1f20078c.
<!-- SECTION:FINAL_SUMMARY:END -->
