---
id: STATBUS-532
title: >-
  Stable preflight reports pending work plainly and shows how to inspect
  relevant changes
status: In Progress
assignee: []
created_date: '2026-10-27T18:12:00Z'
updated_date: '2026-10-27T18:12:00Z'
labels:
  - release
  - ux
  - cli
dependencies: []
priority: high
type: enhancement
ordinal: 458204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
Stable preflight tells the operator what is actually happening: what passed, what is running, what has not started, and what genuinely failed. Pending work is not presented as failure, and the next action is the one the release chain actually needs.

### Zoom out
The 2026-10-26 stable preflight mixed every state into a wall of red. It repeated the arc list and changed-file counts, offered manual triggers while the orchestrator already owned the next step, called a two-minute dev wait a fault, and used abstract wording such as "refuses", "coverage" and "candidate evidence". The certificate smoke assertion also hid a useful failure until the log was investigated. The gate's decisions should not change here: only the operator-facing states, explanations and inspection commands.

### Zoom in
- Use `⏳` for pending and `✗` only for an observed failure. Keep `✓` for green. Say "running", "not started", "passed" and "failed" in plain words, including "0/33 scenarios have passed" rather than "coverage".
- Remove repeated arc-name and changed-file-count output. Offer `git log --oneline`, `git diff` and optionally `git log -p` with the SAME hard-coded pathspec the scenario's coverage check already uses. Do not discover or invent new paths for display.
- Canaries: dev is a fault only after a reasonable automatic-deploy window, not immediately. Norway waits for its next 6h release check before it is a fault. Say "Canary Norway", and remove the duplicated `(Upgrader|Upgrader)` text.
- Explain the orchestrator's actual blocked step and why later steps are skipped. Offer a manual trigger only when the orchestrator has finished without scheduling that work. Do not tell the operator to register/schedule dev by hand as the default action.
- End with "stable promotion is waiting for the checks above to complete" when only pending work remains, not an alarm that reads like a product failure.
- Go tests assert the output for each state and next action. They must fail on the old alarmist/misleading output and pass after the change.

### Closing review
- **Memory:** the owner's concrete wording rules are in this ticket and the output tests.
- **Documentation:** the preflight output itself is the guide; no separate long document.
- **Cleanup:** no duplicate path list maintained only for display.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Pending states use an hourglass and observed failures use the error icon; Go tests distinguish running, not-started, passed and failed, and do not mark pending scenarios as failures
- [ ] #2 Arc names and changed-file counts are not repeated. The output offers git log and git diff with the same hard-coded paths used by the scenario's coverage check, and tests prove the commands contain those exact paths
- [ ] #3 Dev's message becomes a fault only after the automatic-deploy window, Norway's message waits for the next 6h check, and the output says Canary Norway with no duplicated upgrader wording; tests cover short and long waits
- [ ] #4 The output names the orchestrator's blocked step and why later steps are skipped, offers manual triggers only when the orchestrator has finished without scheduling, and ends with a concrete waiting-for-checks message when only pending work remains
<!-- AC:END -->
