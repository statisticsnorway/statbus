---
id: STATBUS-266
title: >-
  window-off-log: the read-only window announces ON and is silent on successful
  OFF — the asymmetry actively misled the diagnosis
status: Done
assignee: []
created_date: '2026-08-27 12:49'
updated_date: '2026-08-27 13:03'
labels:
  - upgrade
dependencies: []
priority: high
type: bug
ordinal: 259000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From STATBUS-262: the journal shows "read-only window ON" (the Printf in setDatabaseReadOnly, exec.go:394) with no matching OFF line when everything works — the success path is terminalExec(windowOffSQL), silent on success; only FAILURE paths call the printing function. A responder who greps the journal sees ON-without-OFF and concludes the window is stuck — the exact wrong diagnosis the architect built three ranked hypotheses on during 262, and the same trap awaits the next 2am responder.

Architect's ruling: a state change announced in one direction and silent in the other is a defect in its own right. Fix: log the successful OFF too. One line; the cheapest correction on the board, ranked ABOVE the ordering work because its absence has already cost a day of wrong-path investigation.

WHAT IS ACHIEVED: the journal tells the truth in both directions — ON always pairs with an OFF or a loud failure, and window state is answerable by grep.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer
created: 2026-08-27 12:58
---
**BUILT AND FROZEN.** Chain: build OK, `go test ./...` green, `golangci-lint run ./...` 0 issues, gofmt clean.

**MY FILES ARE EXACTLY FOUR** — `cli/internal/upgrade/service.go` and three test files in the same package. `ops/setup-ubuntu-lts-24.sh` is ALSO dirty in the tree and is NOT mine: it carries the 259 second session's per-stage input declarations. Please stage by name, not by `git add -A`.

## The fix

The ruling was "one line", and the honest implementation is one line of output behind one small helper, because there are SIX call sites clearing this window — logging at each would drift, and five of them already carry their own distinct invariant escalation that must not be disturbed.

`liftReadOnlyWindow(where)` runs the same `terminalExec(windowOffSQL)`, prints on SUCCESS, and **returns the error unchanged** so every caller's failure handling is untouched. All six sites now call it, each naming its own terminal — flagless-recovery completion, the STATBUS-163 boot backstop, serve-proven health check, upgrade completion, rollback completion, post-swap resume completion — because "which terminal lifted it" is the next question a responder asks after "did it lift".

The asymmetry is now closed in both directions: ON always pairs with an OFF or a loud failure, and window state is answerable by grep.

## THREE EXISTING PINS RETARGETED, NOT WEAKENED

Moving the call behind a helper broke three structural tests that named `terminalExec(windowOffSQL)` directly — the park-recovery ordering pin (lift AFTER the health gate), the restore-lift ordering pin (reattempt exclusion PRECEDES the clear), and the STATBUS-163 flip pin. Every property they assert is still true; only the call's spelling moved. Each now names `liftReadOnlyWindow(`, with the reason recorded at the line.

**And that retargeting quietly cost something, so I paid it back explicitly.** Those pins used to assert the TEARDOWN-IMMUNE transport as a side effect of naming `terminalExec`. Naming the wrapper instead, a wrapper that stopped using terminalExec would satisfy all three while silently returning the flip to a connection the teardown can kill — losing it at exactly the moment it has to land. `TestLiftReadOnlyWindowStillFlipsImmune_STATBUS266` now asserts that property directly, plus that the helper still logs and still returns the error unchanged.

RED-verified both ways, mutation site asserted: removing the log fires it; swapping terminalExec for a plain `queryConn.Exec` fires it.

## One process note against myself

My own patch's safety check — "exactly one raw call site may remain" — failed, and the survivor it printed was **my own doc comment quoting the call it was searching for**. Third time this week one of my verification steps has counted prose as code. The check now strips comment lines before counting. I flagged this pattern for the codebase in the 261 audit and then walked into it again in my own tooling the same day.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Landed at 5aa649f77 (architect: LAND, verified at source — helper logs only on success, returns the error unchanged so all six sites' distinct invariant escalations are untouched; throwaway-worktree build+vet+package tests green). The six window-clearing sites lift through liftReadOnlyWindow(where), which names its terminal and keeps the teardown-immune terminalExec transport pinned explicitly — the engineer caught that retargeting three structural pins at a wrapper would have silently dropped the teardown-immunity those pins bought as a side effect, and asserted it as its own guard (RED-verified). Standing rules recorded from review: a refactor can be behaviour-preserving without being guarantee-preserving — before wrapping a pinned call, ask what its pins were buying beyond their stated subject and assert it at the wrapper; and any check that greps source for call sites must strip comments first (well-documented code miscounts worst, because good comments name their subjects).
<!-- SECTION:FINAL_SUMMARY:END -->
