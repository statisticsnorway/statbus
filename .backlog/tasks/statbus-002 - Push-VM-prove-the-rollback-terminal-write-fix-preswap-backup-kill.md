---
id: STATBUS-002
title: Push + VM-prove the rollback terminal-write fix (preswap-backup-kill)
status: In Progress
assignee: []
created_date: '2026-06-07 11:25'
updated_date: '2026-06-07 16:08'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Push-go approved by King (2026-06-07). Pushed master->origin (3b0adbbb3..6158fc4c9) — AC#1 push done; CI rebuild triggered, operator monitoring fast-tests. VM-prove of 2-preswap-backup-kill launched on a Hetzner VM (foreman background, guarded against a dirty tree); verdict pending for AC#2.

Local VM-prove (tester) DIED AT INIT (2026-06-07): exited after the scenario header, before VM provisioning — no meaningful logs, no orphaned Hetzner VM (clean). Likely a local-env/background-handling quirk, not a harness bug (the GitHub 0-happy-install run proved the harness runs fine on GHA). Dropping the local run. AC#2 (preswap-backup-kill green on a real VM) will be satisfied by the RECORDED GitHub drive-through run instead (tracked in STATBUS-008) — preswap-backup-kill added to that queue.
<!-- SECTION:NOTES:END -->
