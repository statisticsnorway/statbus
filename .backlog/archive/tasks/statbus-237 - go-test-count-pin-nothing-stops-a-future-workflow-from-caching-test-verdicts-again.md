---
id: STATBUS-237
title: >-
  go-test-count-pin: nothing stops a future workflow from caching test verdicts
  again
status: Done
assignee:
  - '@mechanic'
created_date: '2026-08-18 15:53'
updated_date: '2026-08-18 19:08'
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
- [x] #1 A workflow step invoking `go test` without `-count=1` fails the pin, naming the file and step
- [x] #2 Verified RED both ways: removing -count=1 from a test workflow fails, and adding a bare `go test` step to a build-only workflow fails
- [x] #3 The check reads what each workflow actually does rather than consulting a maintained list of which ones run tests
- [x] #4 Comment mentions of `go test` in prose do not satisfy or trip the check — it inspects parsed run commands, not raw file text
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: mechanic
created: 2026-08-18 19:06
---
Built, frozen (no commit), all 4 acceptance criteria checked.

TEST: `TestGoTestStepsCarryCountEqualsOne_STATBUS237` in `cli/cmd/workflow_triggers_test.go`, plus two new helpers: `allWorkflowYAMLFiles` (AC#3 — lists every file in .github/workflows/, no maintained list) and the module-level `goTestInvocationRe`/`countEqualsOneRe` regexps. Walks every workflow's `jobs.*.steps[*].run` string (parsed via yaml.v3, same pattern as the existing STATBUS-224 pins in this file), splits each `run:` block into lines, skips blank lines and shell-comment lines (`#...`), and for any line invoking `go test` requires `-count=1` on that SAME line — not merely present elsewhere in the step.

AC#3: confirmed — `allWorkflowYAMLFiles` reads `os.ReadDir(.github/workflows/)`, so a brand-new workflow is covered automatically with zero list maintenance.
AC#4: confirmed by construction — YAML-level comments (anything above a `run:` key) never reach the decoded string at all (yaml.v3, same STATBUS-224 mechanism this file already relies on); a shell `#` comment LINE inside a run: block's own text is additionally skipped explicitly, so prose like the go-test.yaml/fast-tests.yaml comments explaining -count=1 cannot trip or satisfy the check.

GREEN on the real tree: `go test -count=1 ./cmd/ -run TestGoTestStepsCarryCountEqualsOne_STATBUS237 -v` — PASS across all 33 current workflow files (go-test.yaml, fast-tests.yaml, and 31 others), 0.02s.

RED (a) — stripped `-count=1` from go-test.yaml's `run: go test ./... -count=1` (line 111) in the real file, ran the test, restored via `git checkout --`:
```
workflow_triggers_test.go:345: .github/workflows/go-test.yaml job "go-test" step "go test" line 1 invokes `go test` without `-count=1` on the same command line: "go test ./..."
```
Names the file, job ("go-test"), step ("go test"), and line. Restore confirmed via `git diff --stat -- .github/workflows/go-test.yaml` (empty) before proceeding.

RED (b) — added a bare `go test ./...` step to test-hardening.yaml's `install-stack` job (build-only, only runs `go build` per its own STATBUS-235 comment), ran the test, restored via `git checkout --`:
```
workflow_triggers_test.go:345: .github/workflows/test-hardening.yaml job "install-stack" step "STATBUS-237 RED-verification probe (temporary, restored before freeze)" line 1 invokes `go test` without `-count=1` on the same command line: "go test ./..."
```
Names the file, job, step, and line. Restore confirmed the same way.

Did the edit-observe-restore dance carefully (per your instruction, since this test reads real files from the repo root rather than a fixture dir) — each RED arm was a single targeted Edit, verified failing, then `git checkout -- <file>` before moving to the next, with `git status --porcelain` checked clean before starting the next arm.

GREEN CHAIN:
- `go test -count=1 ./cmd/ -run TestGoTestStepsCarryCountEqualsOne_STATBUS237 -v` — PASS (all 33 workflows).
- `go test -count=1 ./cmd/...` — full package, PASS, 15.5s.
- `gofmt -l cli/cmd/workflow_triggers_test.go` — clean (no output).
- `golangci-lint run ./...` from `cli/` (never repo root) — "0 issues."

Final `git status --porcelain`: only `cli/cmd/workflow_triggers_test.go` dirty (+137 insertions, the new test + helpers + regexps). No workflow files touched in the final state — both RED arms were fully reverted.
---

author: foreman
created: 2026-08-18 19:08
---
LANDED as 661da6ebe (architect APPROVED with one comment-only fold, applied and re-frozen before landing). Verdict highlights: the regex pair verified sound at source — cargo test cannot match (preceding char outside the separator class), -count=10 correctly refused, and the same-line rule holds by construction (both patterns applied to the same line string). The continuation case fails SAFE — a false positive by design — and the header now says why joining continuations must never be "fixed" in (a false alarm beats a -count=1 from a different command satisfying the check). The pin STATES ITS OWN BOUNDARY per the requirement: workflow YAML run text only — not called scripts (./dev.sh), not composite actions, not quoted sh -c strings — because a check must report what it examined, including in its own documentation. RED verified both directions against the real files with serially-verified restores. All four ACs closed.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The rule that keeps CI's warm test cache honest — every go test invocation carries -count=1 — is now a parsed mechanism instead of prose. TestGoTestStepsCarryCountEqualsOne_STATBUS237 walks every workflow file (os.ReadDir, no maintained list), parses run blocks with yaml.v3 so comments can neither satisfy nor trip it, and requires -count=1 on the same command line as any go test invocation, failing with file/job/step/line named. RED-verified in both directions against the real workflows; line-continuation invocations fail safe by design, with the header explaining why the strict form must not be "improved"; the pin documents its own boundary (workflow YAML only — not called scripts, composite actions, or quoted shell strings), applying "a check must report what it examined" to the check's own documentation. Built by mechanic, approved by architect, landed as 661da6ebe.
<!-- SECTION:FINAL_SUMMARY:END -->
