---
id: STATBUS-230
title: >-
  lint-zero-scope-green: the linter prints "0 issues" and exits 0 after failing
  to find the module
status: To Do
assignee: []
created_date: '2026-08-18 10:52'
labels:
  - ci
  - quality-gate
  - tooling
dependencies: []
references:
  - cli/
  - .github/workflows/go-test.yaml
priority: medium
type: bug
ordinal: 230000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every code change this week was certified by a three-step chain — tests, gofmt, lint — before a reviewer saw it. The lint step can report a clean result while having examined nothing at all, and it exits successfully when it does, so a script or a person reading the summary sees "clean" and moves on.

WHAT GOES WRONG: run from the repository root instead of `cli/`, golangci-lint cannot resolve the Go module, says so on one line, and then reports success anyway. Reproduced on the current tree:

```
$ golangci-lint run ./...
level=error msg="[linters_context] typechecking error: pattern ./...: directory prefix . does not contain main module or its selected dependencies"
0 issues.
$ echo $?
0
```

Zero issues over zero analysed packages, exit code 0. A chain written as `golangci-lint run ./... && echo clean` prints clean. The only thing standing between that and a false certification is a human noticing an error line above the summary — which is exactly what happened on 2026-08-18, when a builder caught it on a re-verify and re-ran from the right directory. Nothing in the tooling would have caught it.

THE DETAIL: this is the same shape as four other findings from the same day — a green signal produced by a check that never examined the thing it claims to have examined. A workflow run concluding success with zero scenario jobs; a release gate printing "FULL SUITE green (0/0 arc jobs present)" against an empty scenario folder; a trigger assertion satisfied by a comment containing the string it searched for; a path-matching feature whose tests all passed because the fixtures used simpler filenames than the real ones. Each was found by a person, not by the tooling. See the doctrine note filed alongside this ticket.

THE FIX: make the lint step refuse a zero-scope run. Either pin the working directory and assert the module resolves before linting, or check the output for the typechecking-error line and fail on it, or both — the choice belongs to whoever owns the chain. What matters is that "0 issues" becomes impossible to print when nothing was analysed, in CI and in the local chain equally, because the local chain is what gates a freeze before any reviewer sees it.

WHY THAT HELPS: a clean lint result goes back to meaning the code was read. Certification that can silently mean "I looked at nothing" is worse than no certification, because everyone downstream — reviewer, foreman, release gate — treats it as evidence.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A lint invocation that cannot resolve the module FAILS loudly instead of printing "0 issues" and exiting 0
- [ ] #2 The guard holds for both the local three-step chain and the CI job, since the local chain gates freezes before review
- [ ] #3 Verified by reproduction: running the guarded command from the repository root fails, and from cli/ still passes
- [ ] #4 The chain reports what was examined (package or file count), so a zero-scope run is visible even where it is not fatal
<!-- AC:END -->
