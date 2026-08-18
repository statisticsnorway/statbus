---
id: STATBUS-224
title: >-
  layer-pin-substring: a prose comment satisfies the trigger assertion, so the
  gate-layer test can pass on a workflow that lost its trigger
status: To Do
assignee: []
created_date: '2026-08-18 09:54'
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
