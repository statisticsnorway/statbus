---
id: STATBUS-088
title: >-
  upgrade-log-wording: operator-facing recovery/upgrade log lines are too
  technical — rephrase to plain language
status: Done
assignee: []
created_date: '2026-06-18 12:48'
updated_date: '2026-06-18 17:32'
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

DONE 2026-06-18 — committed in 2134edab8 (with the 090-backend NOTIFY move, same service.go pass). Reworded the ~12 operator-facing log lines to plain 'what happened + what to expect + data safety' language: 4 success-path (maintenance + 3 install-fixup) + 8 recovery-narrative logRecover lines (resume-forward, resume-rollback, post-swap-resume, pre-swap-rollback, the rollback REASON strings, FLAG_PHASE_UNKNOWN) + the :867 forward-resume soften (covers the ground-truth-UNKNOWN sub-case without overclaiming) + the :954 PreSwap rollback reason (consistency with the reworded resume-died reason). PATTERN: plain operator sentence FIRST + a preserved `(detail: …)` triage tail — so SSB's support-bundle greps for the load-bearing identifiers (Err* stored-error prefixes, STATBUS-039, phase labels, FLAG_PHASE_UNKNOWN invariant, ground-truth) still work. Only operator-visible lines (logRecover/fmt.Println/progress.Write) touched; journal-only log.Printf left technical; the returned fmt.Errorf contracts unchanged; arg order unchanged (go vet clean). Especially serves the remote (Albania) operator watching a failed upgrade. Architect-reviewed (scope + Err*-prefix preservation) + foreman-reviewed (operator-clarity). Proposal record: tmp/engineer-088-wording.md. King reviews the final prose on return; can refine.
<!-- SECTION:NOTES:END -->
