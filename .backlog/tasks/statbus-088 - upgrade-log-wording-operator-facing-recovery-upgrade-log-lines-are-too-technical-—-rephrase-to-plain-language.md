---
id: STATBUS-088
title: >-
  upgrade-log-wording: operator-facing recovery/upgrade log lines are too
  technical — rephrase to plain language
status: To Do
assignee: []
created_date: '2026-06-18 12:48'
updated_date: '2026-06-18 12:50'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CATALOGUE (operator, 2026-06-18) + foreman correction. Operator-visible upgrade/recovery messages in cli/internal/upgrade/service.go:
- logRecover: :867, :875, :894 (the flagged one), :946, :974
- progress.Write: :3713, :4069, :4075, :4728, :4785, :4804, :4807
Jargon in use: "post-swap", "pipeline", "ground truth", "flag", "Resuming-phase", "binary-swap commit boundary".

CORRECTION (foreman): the operator classified the logRecover lines as NOT UI-surfaced, but the King saw line :894's exact text ("Post-swap restart detected... resuming pipeline on new binary") ON the Software Upgrades page. So logRecover DOES reach the UI log (both progress.Write AND logRecover write into the per-upgrade log the page's Log expander shows). => the rewording scope is ALL ~12 messages above, not just the progress.Write ones. Confirm the log-surfacing path (logRecover -> per-upgrade log file -> UI) when fixing; reword every operator-visible line to plain language, keep only genuinely journal-only log.Printf lines technical.
<!-- SECTION:NOTES:END -->
