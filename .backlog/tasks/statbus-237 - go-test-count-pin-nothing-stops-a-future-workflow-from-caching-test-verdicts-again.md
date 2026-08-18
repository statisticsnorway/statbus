---
id: STATBUS-237
title: >-
  go-test-count-pin: nothing stops a future workflow from caching test verdicts
  again
status: To Do
assignee: []
created_date: '2026-08-18 15:53'
labels:
  - ci
  - quality-gate
dependencies: []
references:
  - cli/cmd/workflow_triggers_test.go
  - .github/workflows/go-test.yaml
  - .github/workflows/fast-tests.yaml
priority: low
type: enhancement
ordinal: 237000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Our most important tests are pins: they read files outside the Go module — workflow YAML, checked-in lists, shell scripts — and assert facts about them. Go's test cache can replay a pass for such a test without re-reading those files, so a cached "ok" can vouch for content that has since changed. STATBUS-234 closed that by putting `-count=1` on every CI invocation of `go test`, and STATBUS-235 then turned the CI build cache on now that it is safe to do so.

WHAT GOES WRONG: the two halves are held together by prose. The workflows that run tests carry a comment explaining why `-count=1` must stay; the five that only build carry a comment stating they never run tests. Both are true today. Neither is enforced. A future editor adding a `go test` step to a build-only workflow, or trimming `-count=1` from a test one, re-opens the staleness with nothing to notice — and now with the cache live, which is the state that makes it bite.

THE DETAIL: this is the pattern this project has been bitten by repeatedly — a comment stating a condition-dependent fact, which a later change quietly falsifies. STATBUS-197 invalidated a premise written a dozen lines from the code that broke it, and it cost two tickets and a red suite to find. The remedy each time has been the same: state the invariant as a mechanism rather than as prose.

THE FIX: assert it. `cli/cmd/workflow_triggers_test.go` already parses every workflow with yaml.v3 for the trigger pins; extend it so that any step whose command invokes `go test` must also carry `-count=1`. That covers both directions at once — adding a test to a build-only workflow, and removing the flag from a test one — and it needs no list of which workflows are which, because it reads what each one actually does.

WHY THAT HELPS: the guard stops depending on whoever edits a workflow next having read a comment in a different file. The rule becomes checkable, and the answer to "is our test cache safe?" stops being "yes, as long as nobody changed anything."
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A workflow step invoking `go test` without `-count=1` fails the pin, naming the file and step
- [ ] #2 Verified RED both ways: removing -count=1 from a test workflow fails, and adding a bare `go test` step to a build-only workflow fails
- [ ] #3 The check reads what each workflow actually does rather than consulting a maintained list of which ones run tests
- [ ] #4 Comment mentions of `go test` in prose do not satisfy or trip the check — it inspects parsed run commands, not raw file text
<!-- AC:END -->
