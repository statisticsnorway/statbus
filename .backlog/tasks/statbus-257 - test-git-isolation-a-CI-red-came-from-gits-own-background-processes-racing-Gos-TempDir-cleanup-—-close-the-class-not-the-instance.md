---
id: STATBUS-257
title: >-
  test-git-isolation: a CI red came from git's own background processes racing
  Go's TempDir cleanup — close the class, not the instance
status: In Progress
assignee:
  - engineer
created_date: '2026-08-19 12:46'
updated_date: '2026-08-19 12:51'
labels:
  - testing
  - ci
dependencies: []
priority: medium
type: bug
ordinal: 250000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A test failed in CI for a reason that had nothing to do with what it tests, and the same test passed on the next runner. Under the no-flaky-tests rule that is a real defect with a real cause, and it is now fixed at the pattern rather than at the instance.

**THE RED.** `TestFindExemptRide_AddThenRevertRidesTheOlderAncestor` failed at commit d59f5e06d (go-test lane, 11:58 run) — not on an assertion:

    testing.go:1369: TempDir RemoveAll cleanup: unlinkat …: directory not empty

It was green on the 12:35 run of the same lane.

**WHAT THE ERROR PROVES, and what it does not.** Go's `RemoveAll` walks a directory and then removes it, so "directory not empty" can only mean something wrote into it between those two steps. A test whose git commands have all returned cannot do that; a background process git spawned can. So the mechanism is certain: a concurrent writer.

WHICH spawner is not knowable from a developer machine — the red is on a runner nobody can attach to and it did not recur. The known candidates are auto-gc (which DETACHES by default and so outlives the command that triggered it), scheduled background maintenance, and the fsmonitor daemon — which is enabled by CONFIG, meaning a runner's global git config can switch it on for repos that never asked for it.

**WHY THE FIX IS A SHARED HELPER, not an edit to the failing test.** Ten test files across five packages each build throwaway git repos with their own copy of the same helper shape. Fixing one leaves nine, and fixing all ten leaves the eleventh — which someone will write by copying an older one, reintroducing a rare non-deterministic failure on a machine nobody is watching.

**WHAT IS ACHIEVED:** every test git invocation runs with background maintenance off and with the machine's git configuration cut off, so the suite behaves the same on a laptop, on a runner, and on the next runner — and a new helper that bypasses the rule fails a test that names itself.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The failing test's cleanup race cannot recur: no git invocation in any test can leave a background process writing into a TempDir after the command returns
- [x] #2 The fix lives at ONE definition, not in each helper — every existing test git helper routes through it
- [x] #3 A NEW helper that bypasses the shared definition fails a test that says so and shows how to fix it
- [x] #4 Host git configuration cannot reach a test fixture, including settings nobody thought to name explicitly
- [x] #5 Each guard is RED-verified by mutation with the mutation site asserted
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer
created: 2026-08-19 12:46
---
**BUILT AND FROZEN** — post-tag unit #5, landing last. Chain: build OK, `go test ./...` green, `golangci-lint run ./...` 0 issues, gofmt clean. The originally-failing test passes.

**What was built:** `cli/internal/testgit` — one definition of how a test invokes git, exposing `Args()` (isolation flags prepended to every invocation) and `Env()` (fixed identity + global/system config cut off). Twelve helper sites across ten files in five packages now route through it. The flags go on the COMMAND LINE rather than into repo config, because they must also cover `git init` — which runs before any repo config exists to read.

Closed: `gc.auto=0` (auto-gc is the spawner that detaches by default and outlives its command), `gc.autoDetach=false`, `maintenance.auto=false`, `core.fsmonitor=false`, signing off, and a deterministic default branch.

**THE DIAGNOSIS IS HONEST ABOUT ITS LIMITS, and the fix is shaped by that.** The error class proves a concurrent writer — `RemoveAll` walks then removes, so "directory not empty" means something wrote in between, and a test whose git commands have all returned cannot be that writer. But WHICH spawner is not knowable from here: the red is on a runner nobody can attach to and it did not recur. So the fix closes the whole known class rather than betting on one candidate. A fix aimed at a guess would leave the test able to fail again while looking fixed.

**RED-VERIFIED THREE WAYS, mutation site asserted each time** — and the second one is the finding worth reading.

The race cannot be forced, so the tests prove the MECHANISM behaviourally: a hostile global config switches ON everything this package switches off, and each setting is then read back through `git config --get` from a git process launched exactly as the helpers launch one — measuring what git ACTUALLY resolved, not what the package intended.

- Dropping `gc.auto=0` → fires.
- A helper bypassing the package → fires.
- **Dropping the global-config cut-off → DID NOT FIRE.** The `-c` flags already override global config for every key they name, so the test was measuring the flags twice and the cut-off not at all. The cut-off's real job is the keys nobody thought to name — so the test now also asserts that `core.autocrlf` and `core.hooksPath` do not reach a fixture. `hooksPath` is the sharp one: a machine pointing it at a directory of hooks would run them inside every fixture this repo builds. With those added, dropping the cut-off fires.

That is the same defect I keep catching in my own checks: a guard that passes for a reason other than the property it claims. It only surfaced because the RED was run at all.

**TWO THINGS THE EMPIRICAL RUN TAUGHT, neither predictable from review:**

1. Pinning `init.defaultBranch=main` — the modern default — immediately reddened two tests that hardcode `master`. The isolation's job is to make THIS PROJECT's convention deterministic, not to substitute a different convention for the machine's. Pinned to `master`, with the reason recorded at the line.
2. The pattern guard flagged its own file, because its guidance text quotes the call shape it searches for. I narrowed the MATCHER (skip the package that defines the rule) rather than allow-listing the file — an allow-list would have hidden a real bypass if one were ever written there.

**One process note against myself:** running `gofmt -w cmd internal` reformatted eleven files I never intended to touch — pre-existing formatting drift, swept into my diff. I verified each was whitespace-only (`git diff -w` empty) and restored them from HEAD, so the frozen change set contains only files this work actually changes.
---

author: architect (pinned by foreman)
created: 2026-08-19 12:51
---
VERDICT: LAND. Env() sets GIT_CONFIG_GLOBAL=/dev/null + GIT_CONFIG_SYSTEM=/dev/null with -c flags on the command line for keys needing values — correct, and flags-not-env is what makes it cover `git init`. The test fix is the substance: asserting core.autocrlf and core.hooksPath come back EMPTY inside a fixture tests an UNLISTED key, the only thing that can prove a cut-off — the original test could only check keys the -c flags already guaranteed trivially, passing identically with no isolation at all. hooksPath is the sharpest choice: a developer's hooksPath would execute that machine's hooks inside every fixture this repo builds. Same defect family as the mutation that hit the wrong line: a guard passing for a reason other than the property it claims.
---

author: architect (pinned by foreman)
created: 2026-08-19 12:51
---
LANDING PROTOCOL AMENDED BY ARCHITECT (applies to all five units): (1) `go build` per intermediate commit IN THE SHARED TREE verifies nothing — git apply --cached stages into the index while the working tree carries all units throughout, so each build would compile the same final state and manufacture confidence. Each intermediate commit is verified in a THROWAWAY WORKTREE (git worktree add at the new commit, go build ./... there, remove) so bisectability across the six overlapping-file commits is real. (2) After the final commit, `git status --porcelain` must be EMPTY (board files land in their own Backlog commit) — the only check proving the unit manifests PARTITIONED the tree; anything remaining was reviewed as part of nothing and goes to the architect, never folded in.
---
<!-- COMMENTS:END -->
