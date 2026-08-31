---
id: STATBUS-323
title: >-
  install-fetch-race: install.sh's git fetch loses to the live upgrade service's
  discovery fetch — quiesce the service before touching the repo
status: To Do
assignee: []
created_date: '2026-08-31 11:11'
labels:
  - ops
  - upgrade
  - install
dependencies: []
priority: medium
type: bug
ordinal: 316000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: a bootstrap install cannot be raced by the very service it is replacing. Observed live on ma (2026-08-31, fleet convergence): install.sh's `git fetch origin --tags` (line 293) failed with `cannot lock ref 'refs/remotes/origin/master': is at 3bd85bfae but expected 376a18c38` — the box's still-running upgrade service fetches the same repo on its ~2-minute discovery tick (journal-confirmed ticks throughout the install window), and the two fetches collided on the ref. et and jo, run minutes earlier with identical commands, simply won their races.

THE MIXED STATE IT LEAVES, worth recording because it looked scarier than it was: the binary had already been swapped (sb at v2026.08.0, sb.old preserved) but the worktree stayed at the old tag and ./sb install never ran — box kept serving on the old stack, translation not run, ledger rows oddly 'skipped'. Recoverable by stop-service + retry (proven on ma).

THE FIX, in code: the bootstrap path (install.sh, and/or the cloud.sh install wrapper) STOPS the box's upgrade unit before its first repo operation and lets the install's own tail restart it — the same quiesce-the-owner principle the upgrade service itself applies before touching the stack. A retry-once-on-ref-lock band-aid is explicitly NOT the fix (it narrows the window without closing it, and a fetch race can bite any repo operation after it too).

Also worth a look while in there: whether ./sb install's step-table should refuse or warn when the upgrade unit is ACTIVE at bootstrap time — the arriving job checking for itself, same principle as 246/307.

Operational mitigation already standing (foreman ruling during the convergence run): stop-the-unit-first is step 1 of the fleet install procedure for all remaining slots.

WHAT IS ACHIEVED: the bootstrap owns the repo for its duration, and the race class dies in code instead of living in a runbook.
<!-- SECTION:DESCRIPTION:END -->
