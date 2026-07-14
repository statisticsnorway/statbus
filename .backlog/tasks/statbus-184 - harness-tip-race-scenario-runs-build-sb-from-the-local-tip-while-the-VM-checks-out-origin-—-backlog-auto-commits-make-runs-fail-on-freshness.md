---
id: STATBUS-184
title: >-
  harness-tip-race: scenario runs build sb from the local tip while the VM
  checks out origin — backlog auto-commits make runs fail on freshness
status: To Do
assignee: []
created_date: '2026-07-14 16:47'
labels:
  - install-recovery
  - harness
  - tooling
dependencies: []
priority: low
ordinal: 185000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a scenario/arc dispatch is self-consistent by construction — the binary the harness uploads always resolves in the checkout the VM gets, regardless of what the team's backlog auto-commits are doing to the local tip.
> FOUND: 2026-07-14, two burned VM runs back-to-back on 4-flagless-selfheal-at-target: run 1 uploaded sb built at local-only 01a88e29a (a STATBUS-183 board-edit auto-commit) against a VM at origin-tip 5f670fb86; run 2, dispatched right after pushing, uploaded sb built at 357808d95 (an architect ruling-comment auto-commit that landed between my push and the harness's build step) against a VM at 01a88e29a. Both died identically: the staleness guard's freshness check — `git diff` exit 128, "bad object <build commit>" — because the binary's embedded commit wasn't in the VM's repo. In a busy team session the local tip moves every few minutes; the dispatch window race is structural, not operator sloppiness.
> WORKAROUND in use: chain `git push origin master && ./dev.sh test-install-recovery <scenario>` in one command so any just-landed backlog commit is pushed before the harness builds.
> COMPLEXITY: mechanic-small. Candidate fixes for the architect/engineer to pick from: (a) the harness snapshots the SHA it builds at and pins the VM checkout to THAT sha (self-consistent even unpushed-dirty... no — the VM must fetch it, so pushed is still required); (b) the harness refuses to start if local HEAD != origin/master (loud precondition, names the fix `git push`); (c) the harness builds sb from origin/master's tree (detached worktree) instead of the local tip. (b) is the smallest honest guard; (c) is the most reproducible.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Fix shape picked (refuse-on-unpushed vs build-from-origin) and implemented in the scenario/arc dispatch path
- [ ] #2 A dispatch with a deliberately unpushed local commit either refuses loudly naming the remedy, or succeeds self-consistently — proven by a run
<!-- AC:END -->
