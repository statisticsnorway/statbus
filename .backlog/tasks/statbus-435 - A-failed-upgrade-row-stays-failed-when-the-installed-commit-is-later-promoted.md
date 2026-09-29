---
id: STATBUS-435
title: A failed upgrade row stays failed when the installed commit is later promoted
status: To Do
assignee: []
created_date: '2026-09-29 21:23'
labels:
  - upgrade
dependencies: []
priority: high
ordinal: 384200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the LXD arc run (STATBUS-425 M3b, tmp/lxd-all-gates-progress.md 2026-09-29T14:00Z; evidence test/install-recovery/lxd/evidence/v2026.09.3-rc.17/ on ci/lxd-arcs). Arcs rollback-pair-terminal and restore-broke-reattempt install candidate A (ebe058af), break upgrade B on purpose, and expect B's row to stay 'failed' (the operator's evidence of what went wrong). On LXD it becomes 'superseded': the daemon's discovery enriches A's row to release_status='release' because A was promoted to v2026.09.3 (seen on an isolated fork: 'commit' -> 'release' within one 90 s tick), and the next ./sb install calls upgrade_supersede_older(A), which ranks release tier before version ('lower release tiers are always older', migration 1d857c6e6) and supersedes B's 'failed' commit row. On Hetzner the arcs pass only because their daemons cannot fetch tags ('could not read Username for https://github.com', 21 hits in run 36509925405), so A stays 'commit'. Owner decision pending: (a) supersede no longer touches 'failed' rows, which stay until the operator acts; or (b) current behaviour is intended and the two arcs expect 'superseded' once a release covers the installed commit.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Owner decision on (a) or (b) recorded here
- [ ] #2 The chosen behaviour is implemented as a forward migration with a pg_regress test covering a failed commit row and a later-promoted installed commit
- [ ] #3 rollback-pair-terminal and restore-broke-reattempt give the same verdict on LXD and Hetzner, and the Hetzner arc VMs can fetch tags (or the gap is recorded)
<!-- AC:END -->
