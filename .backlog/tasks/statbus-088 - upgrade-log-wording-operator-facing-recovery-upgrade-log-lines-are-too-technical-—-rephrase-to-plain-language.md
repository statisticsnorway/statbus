---
id: STATBUS-088
title: >-
  upgrade-log-wording: operator-facing recovery/upgrade log lines are too
  technical — rephrase to plain language
status: To Do
assignee: []
created_date: '2026-06-18 12:48'
labels:
  - upgrade-ui
  - ux
  - post-rc.04
dependencies: []
priority: medium
ordinal: 88000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OBSERVED (King, dev.statbus.org rc.04 upgrade, 2026-06-18): the Software Upgrades page surfaces internal log wording to the operator. Example flagged:
  "Post-swap restart detected for upgrade 254954 (v2026.06.0-rc.04) — resuming pipeline on new binary"
This is implementation jargon (post-swap, pipeline, binary handoff). Operators see it and shouldn't need to.

WANTED: plain operator language, e.g.
  "Upgrade 254954 (v2026.06.0-rc.04) switched to the upgraded sb binary."
or similar.

SCOPE / INSPECTION (delegated):
- The flagged line is service.go's FlagPhasePostSwap branch (logRecover, ~service.go:894: "Post-swap restart detected for upgrade %d (%s) — resuming pipeline on new binary (pid=%d)").
- Audit the SIBLING progress/recover messages that also surface to the operator (other phases: PreSwap rollback, Resuming forward/rollback, migrate steps, completion, self-heal) and give them all consistent, plain, operator-facing wording — not internal phase names.
- Distinguish operator-facing progress (progress.Write, surfaced in the UI log) from internal log.Printf/journal lines (those can stay technical). Only the UI-surfaced ones need rewording.

Post-rc.04 UX polish — not rc.04-blocking.
<!-- SECTION:DESCRIPTION:END -->
