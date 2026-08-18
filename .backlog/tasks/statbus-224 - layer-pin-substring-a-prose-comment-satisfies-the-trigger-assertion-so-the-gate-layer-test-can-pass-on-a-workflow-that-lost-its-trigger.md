---
id: STATBUS-224
title: >-
  layer-pin-substring: a prose comment satisfies the trigger assertion, so the
  gate-layer test can pass on a workflow that lost its trigger
status: Done
assignee: []
created_date: '2026-08-18 09:54'
updated_date: '2026-08-18 15:40'
labels:
  - ci
  - release
  - quality-gate
dependencies: []
references:
  - cli/cmd/release_gate_layer_test.go
  - .github/workflows/test-install.yaml
priority: low
type: bug
ordinal: 224000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHAT THIS PART DOES: release_gate_layer_test.go pins a fact the STATBUS-205 gate layering rests on — that certain workflows fire only on the `v*-rc.*` tag push. If someone changes those triggers, the test is supposed to fail so the gate layering gets re-decided at the same time.

WHAT GOES WRONG: the assertion matches a substring in the workflow file's raw text, so any occurrence satisfies it — including one inside a comment. Observed 2026-08-18 during the STATBUS-214 review: after the tag trigger was removed from test-install.yaml, the pin still passed, because the explanatory comment left behind describing the move contains the literal trigger text. The test asserted a fact that had just stopped being true.

THE DETAIL: this is the same class the STATBUS-216 arc-path pin was hardened against a few hours earlier — a loose substring check satisfied by prose while the real declaration moved. There the fix was to match the composed glob that only a live line can contain; here the equivalent is to stop matching text at all. The immediate correctness fix (repointing the test-install row at the orchestrator, which genuinely owns the trigger now) restores the assertion's truth but leaves the method intact, so the next comment mentioning a trigger re-opens it.

THE FIX: parse the workflow YAML and assert on the structure — `on.push.tags` contains the `v*-rc.*` pattern, and `on.push.branches` is absent — rather than grepping the file's text. A comment then cannot satisfy a claim about the trigger, because comments do not survive parsing.

WHY THAT HELPS: the pin goes back to meaning what it says. A test that passes for the wrong reason is worse than no test — it reports a guarantee nobody is checking, and this one guards the layering that decides which gates may run before a tag exists.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The trigger assertions parse the workflow YAML and inspect on.push.tags / on.push.branches, instead of matching raw file text
- [ ] #2 Verified RED: removing the tag trigger from a pinned workflow fails the test even when a comment still mentions it
- [ ] #3 Every row in the pinned workflow table is re-checked against its current file, so no other row is passing for the wrong reason
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer
created: 2026-08-18 15:37
---
**BUILT, FROZEN for review (no commit).** Files: new `cli/cmd/workflow_triggers_test.go`, `cli/cmd/release_gate_layer_test.go` (Side 2 removed, pointer left), `cli/go.mod` (one line — see the dependency note). All three ACs met, plus the foreman's three-copy equality pin.

**AC#1 — the triggers are PARSED.** `workflowPushTriggers` decodes the workflow with `gopkg.in/yaml.v3` and returns the `on.push` block; the assertions read `on.push.tags` and `on.push.branches` as data. Comments cannot satisfy a claim about a trigger because comments do not survive parsing.

**THE `on:` KEY TRAP, handled rather than assumed.** In YAML 1.1 the bare word `on` is a BOOLEAN, so a naive parse can land the block under the key `true`. yaml.v3 follows YAML 1.2 (only true/false are booleans), but the helper checks BOTH keys and FAILS LOUDLY when neither is found — because a parse that silently finds nothing would satisfy every assertion below it by vacuous truth, which is the same defect class in a new costume.

**AC#2 — verified RED on the ticket's exact scenario, and I measured the old pin's behaviour on the same tree rather than describing it.** Removing `tags: ['v*-rc.*']` from test-hardening.yaml while LEAVING a comment that mentions it:
- the parsing pin FAILS (`on.push.tags` parsed as empty);
- the substring `v*-rc.*` is **still present in the file text**, so the old check would have PASSED.
That is precisely the 2026-08-18 observation this ticket was filed on, reproduced and closed.

**AC#3 — every row re-checked against its current file.** Both rows of `tagFiredWorkflows` (test-hardening.yaml, release-fleet-orchestrator.yaml) now pass structurally: each really declares `on.push.tags: ['v*-rc.*']` and really has no `on.push.branches`. No row was passing for the wrong reason.

**THE THREE-COPY EQUALITY PIN (foreman's addition).** `TestPathsIgnoreMatchesExemptList_STATBUS224` asserts `on.push.paths-ignore` in go-test.yaml and app_build_and_lint-workflow.yaml equals `ops/release/ci-exempt-paths.txt`, entry for entry, with the dialect mapping stated in the code: the Go matcher's entry is an anchored path PREFIX (`.backlog/`), GitHub's filter is a GLOB (`.backlog/**`), so `X/` ↔ `X/**`. RED-verified: adding `doc/` to the exempt list alone fails BOTH workflows with the expected-vs-actual printed. The failure text carries the fail-toward-full-build reasoning — ignoring MORE here than the preflight exempts is a HARD STOP (no run at the tip, and the ancestor-ride cannot rescue a commit it does not consider exempt), while ignoring less merely costs a redundant run.

**FINDING, FLAGGED NOT BURIED — THIS PIN FAMILY CAN REPORT STALE PASSES.** Go's test cache does NOT track files read from outside the module. Demonstrated: prime the cache, append `doc/` to `ops/release/ci-exempt-paths.txt`, re-run without `-count=1` → **`ok (cached)`**, a green that proves nothing. This is NOT introduced by my change — it applies to every existing pin that reads `../.github/**` or `../ops/**` (the arc-path pin, the run.sh marker pin, the images-never-rides pin, and this one). CI runs plain `go test ./...` (go-test.yaml:86) and `actions/setup-go@v5` caches the build cache by default, so CI is plausibly exposed too; I could not verify setup-go's default offline, so treat that half as unconfirmed. **Minimal remedy: `go test -count=1 ./...` in go-test.yaml** — one flag, and it is the mechanic's file, so I have not touched it. Worth its own ticket if the architect agrees.

**DEPENDENCY NOTE:** `gopkg.in/yaml.v3 v3.0.1` becomes a direct import (it was already in `go.sum` and in the local module cache, so no new download). I deliberately did NOT run `go mod tidy` — it pulled two extra test-only checksums (`kr/text`, `rogpeppe/go-internal`) for zero benefit here. The line therefore still reads `// indirect`, which is cosmetically stale; no CI step verifies tidiness (checked), so it is harmless. Say the word and I will tidy properly instead.

**Verification:** `go test -count=1 ./...` in cli/ — 12 packages ok, 0 failures. `gofmt -l` clean. `golangci-lint` 2.12.2 — 0 issues.
---

author: foreman
created: 2026-08-18 15:40
---
LANDED at 3f737b9db, architect-approved (his verdict: the YAML-1.1 bare-on-is-boolean trap — which caught HIM earlier today — handled by loud failure on an empty parse; RED-verified on the exact remove-trigger-keep-comment scenario the ticket was filed for; the three-copies exempt-list equality pin included and RED-verified both directions). go.mod deliberately untidied per his ruling — fold at the next deliberate go.mod touch. Done.
---
<!-- COMMENTS:END -->
