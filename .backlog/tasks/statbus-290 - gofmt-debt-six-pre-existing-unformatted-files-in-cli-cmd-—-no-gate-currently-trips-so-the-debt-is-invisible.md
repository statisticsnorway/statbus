---
id: STATBUS-290
title: >-
  gofmt-debt: six pre-existing unformatted files in cli/cmd — no gate currently
  trips, so the debt is invisible
status: To Do
assignee: []
created_date: '2026-08-27 18:42'
updated_date: '2026-08-27 22:27'
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
Found by the engineer during the 288 unit (2026-08-27): `gofmt -l cmd/` reports six files unformatted — cert.go, users.go, cert_test.go, root_resolve_test.go, session_orphan_test.go, stalenessguard_advice_test.go. None were touched by the 288 unit (its five files verified gofmt-clean). No current CI gate trips on them (go-test.yaml's lint job passed at these states), which is exactly why the debt persists invisibly.

Fix shape: one mechanical commit running gofmt on the six files (whitespace-only diff, review by `git diff -w` emptiness), and decide whether the lint job should gain a gofmt check so the class cannot regrow — that half is a small design call (strict gate vs advisory), consistent with the strict-gating preference.

WHAT IS ACHIEVED: gofmt-clean cli/cmd, and formatting drift becomes impossible to accumulate silently if the gate half is taken.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-27 22:27
---
FORMATTING HALF LANDED at caae6ab31: gofmt -l cmd/ six findings → zero; build + vet + uncached cmd suite green. Verification note worth keeping: the brief's `git diff -w`-empty criterion was IMPERFECT — -w hides intra-line whitespace but not added/removed lines, and gofmt did both (a trimmed trailing blank, an inserted doc-comment paragraph break); the mechanic flagged the criterion's failure rather than claiming a false clean, and certified formatting-only the stronger way: every hunk read (alignment, padding, doc-comment reflow — zero identifiers/logic/values touched). REMAINING for closure: the gate half — whether the lint job gains a gofmt check so the class cannot regrow (small design call, strict-gate vs advisory, consistent with the strict-gating preference).
---
<!-- COMMENTS:END -->
