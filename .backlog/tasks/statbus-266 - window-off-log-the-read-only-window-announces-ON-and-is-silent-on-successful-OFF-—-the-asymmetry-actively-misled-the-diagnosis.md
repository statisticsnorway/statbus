---
id: STATBUS-266
title: >-
  window-off-log: the read-only window announces ON and is silent on successful
  OFF — the asymmetry actively misled the diagnosis
status: To Do
assignee: []
created_date: '2026-08-27 12:49'
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
