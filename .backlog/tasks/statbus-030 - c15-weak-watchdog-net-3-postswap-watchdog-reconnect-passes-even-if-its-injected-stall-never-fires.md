---
id: STATBUS-030
title: >-
  c15-weak-watchdog-net: 3-postswap-watchdog-reconnect passes even if its
  injected stall never fires
status: Done
assignee: []
created_date: '2026-06-11 11:51'
updated_date: '2026-06-19 15:38'
labels:
  - install-recovery
  - test
  - watchdog
dependencies: []
references:
  - .backlog/docs/doc-006
  - test/install-recovery/scenarios/3-postswap-watchdog-reconnect.sh
  - test/install-recovery/scenarios/3-postswap-archivebackup-watchdog.sh
priority: medium
ordinal: 30000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the engineer's King-directed diagram<->reality / scenario-vacuity audit (doc-006, 2026-06-11).

3-postswap-watchdog-reconnect (C15) is a WEAK watchdog net: it uses a blind sleep and never confirms its injected stall actually fired, so its `NRestarts delta == 0` assertion passes even if the stall never happens — a potential silent false-pass. Same vacuity class as 3-postswap-migration-timeout (which the STATBUS-012 RED rewrite is already fixing).

Why it matters: watchdog-reconnect is one of the headline GREEN scenarios in the validation tallies (STATBUS-008). If its stall can silently not-fire, its green doesn't actually prove the watchdog/reconnect recovery path. The audit swept all 30 scenarios — the kill-nets are exemplary (explicit RED-confirmed site-proofs); C15 is the ONE additional weak watchdog net besides migration-timeout, so the suite's vacuity exposure is bounded to exactly these two.

Fix: confirm the stall fired before the assertion, using the 1-line pgrep-the-parked-process pattern the sibling 3-postswap-archivebackup-watchdog already uses.

Harness-only, ~1 line, NOT cut-blocking, parallelizable. Engineer flagged this HIGH for suite-trust; filed MEDIUM as a small harness hardening off the cut path — bump if desired.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 3-postswap-watchdog-reconnect confirms its injected stall actually fired (e.g. pgrep the parked process) BEFORE the NRestarts/recovery assertions
- [ ] #2 The scenario FAILS if the stall never fires (no more silent false-pass on a blind sleep)
- [ ] #3 Stall-confirmation matches the pattern the sibling 3-postswap-archivebackup-watchdog already uses
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DONE (foreman-verified 2026-06-19): the C15 reshape (postswap-watchdog-reconnect-arc.sh:98-102) added the (e) anti-false-pass gate — asserts the row is STILL in_progress after the hold, i.e. the injected stall genuinely held past WatchdogSec, so the scenario can no longer pass vacuously if the stall never fires.
<!-- SECTION:NOTES:END -->
