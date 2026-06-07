---
id: STATBUS-002
title: Push + VM-prove the rollback terminal-write fix (preswap-backup-kill)
status: In Progress
assignee: []
created_date: '2026-06-07 11:25'
updated_date: '2026-06-07 13:52'
labels:
  - upgrade
  - rollback
dependencies: []
references:
  - test/install-recovery/scenarios/2-preswap-backup-kill.sh
  - cli/internal/upgrade/exec.go
priority: high
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The rollback terminal-state-write hardening is code-complete, committed, and locally green — but UNPUSHED and not yet verified on a real VM. Commits: e32782a33 (bounded-retry terminal write, fail-loud, keep-flag-on-failure) + 0575405f4 (waitForDBHealth before the rollback reconnect — the root fix). The earlier preswap-backup-kill VM run FAILED; that failure is what motivated this fix.

Remaining work: get the go-ahead to push, let CI rebuild, then re-run the preswap-backup-kill install-recovery scenario on a Hetzner VM and confirm green (flag removed only on a landed write; health-wait covers the real DB restart).

Note: pushing is gated on an explicit go-ahead.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The two fix commits (e32782a33, 0575405f4) are pushed and CI has rebuilt
- [ ] #2 The preswap-backup-kill install-recovery scenario passes green on a Hetzner VM
<!-- AC:END -->
