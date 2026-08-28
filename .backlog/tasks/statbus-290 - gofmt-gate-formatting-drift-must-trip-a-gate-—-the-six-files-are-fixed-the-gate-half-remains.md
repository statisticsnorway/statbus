---
id: STATBUS-290
title: >-
  gofmt-gate: formatting drift must trip a gate — the six files are fixed, the
  gate half remains
status: To Do
assignee: []
created_date: '2026-08-27 18:42'
updated_date: '2026-08-28 08:06'
labels:
  - cli
  - ci
dependencies: []
priority: low
type: chore
ordinal: 283000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: formatting drift in the Go CLI must be unable to accumulate silently — either a gate trips when a file is unformatted, or the debt cannot exist. Today neither is true: no CI gate runs gofmt, which is exactly how six files drifted unnoticed until an unrelated unit tripped over them.

ALREADY DONE (2026-08-27, commit caae6ab31): the six unformatted files in cli/cmd — cert.go, users.go, cert_test.go, root_resolve_test.go, session_orphan_test.go, stalenessguard_advice_test.go — were gofmt'd in one mechanical commit. Certified formatting-only the strong way: every hunk read (alignment, padding, doc-comment reflow; zero identifiers, logic, or values touched). Verification lesson kept in comment #1: `git diff -w`-emptiness was the brief's criterion and it was imperfect — gofmt also adds/removes lines, which -w does not hide.

WHAT REMAINS — the gate: without a check, the class regrows. The decision is one call: the go CI lint job gains a gofmt check.
- SHAPE: strict — the job fails when `gofmt -l` reports any file, and the failure output IS the file list (actionable: run gofmt -w on the listed files). Not advisory: the house rule is strict gates over continue-on-error hedges; an advisory warning is how these six accumulated in the first place.
- SCOPE: all Go source in cli/ (cmd/ and internal/), since internal/ has no gate either and the same drift mechanism applies.
- COST: one `gofmt -l` invocation in the existing lint job — sub-second, no new workflow.

WHAT IS ACHIEVED: gofmt-clean is an enforced invariant instead of a hope; the next unformatted file fails its own PR/push instead of waiting months to be found by accident.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-27 22:27
---
FORMATTING HALF LANDED at caae6ab31: gofmt -l cmd/ six findings → zero; build + vet + uncached cmd suite green. Verification note worth keeping: the brief's `git diff -w`-empty criterion was IMPERFECT — -w hides intra-line whitespace but not added/removed lines, and gofmt did both (a trimmed trailing blank, an inserted doc-comment paragraph break); the mechanic flagged the criterion's failure rather than claiming a false clean, and certified formatting-only the stronger way: every hunk read (alignment, padding, doc-comment reflow — zero identifiers/logic/values touched). REMAINING for closure: the gate half — whether the lint job gains a gofmt check so the class cannot regrow (small design call, strict-gate vs advisory, consistent with the strict-gating preference).
---
<!-- COMMENTS:END -->
