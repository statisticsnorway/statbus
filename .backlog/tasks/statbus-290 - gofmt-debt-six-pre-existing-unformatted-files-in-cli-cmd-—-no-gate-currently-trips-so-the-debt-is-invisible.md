---
id: STATBUS-290
title: >-
  gofmt-debt: six pre-existing unformatted files in cli/cmd — no gate currently
  trips, so the debt is invisible
status: To Do
assignee: []
created_date: '2026-08-27 18:42'
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
