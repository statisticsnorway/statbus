---
id: STATBUS-350
title: >-
  fleet concurrency: the orchestrator is the only dispatcher into hetzner-vm-fleet on a tag; other entrants refuse with the owner's run id
status: To Do
assignee: []
created_date: '2026-09-04 06:40'
updated_date: '2026-09-04 06:55'
labels:
  - release
  - ci
  - fail-fast
dependencies: []
priority: high
type: bug
ordinal: 343000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**What the group is.** `concurrency: group: hetzner-vm-fleet` is a GitHub Actions scheduler slot, not anything we store. GitHub holds at most ONE running and ONE pending run per group; a third entrant makes GitHub cancel the previously pending run, silently, zero jobs, no line saying why. `cancel-in-progress: false` protects only the running run. The group is NOT a VM count: each fleet run rents its own VMs; the group bounds the number of fleet RUNS so the Hetzner project quota is not exceeded (install-recovery-harness.yaml:48,73).

**Who coordinates.** The orchestrator (release-fleet-orchestrator.yaml) is the real queue: its `needs:` chain plus `dispatch-fleet-and-wait` dispatches ONE fleet run at a time and polls it to completion before dispatching the next, so more than two never coexist. It sits in its own per-tag group because it rents nothing. The King's supersession rule (`decide-obsolete`, re-checked at every stage `if:`) is separate from GitHub's group and stops a chain BETWEEN stages when a newer tag appears; it never yanks running VMs. That rule is untouched by this ticket.

**Observed 2026-09-04, v2026.09.0-rc.14.** The foreman hand-dispatched upgrade-arc-harness at the tag (33835503755) while the tag-fired orchestrator (33835497127) had test-install + test-upgrade in the group. Third entrant: test-install 33835566015 CANCELLED with zero jobs; test-upgrade starved past the 2700s poll budget; orchestrator attempt 1 failed on timeout. A rerun (attempt 2) while the old test-upgrade was still running re-created the collision: the fresh test-upgrade 33845135678 was cancelled the same way. Attempt 3 on an empty group is the recovery. No product red at any point; ~3 hours lost.

**Two facts made this possible:**
1. The orchestrator dispatches stages 1 and 2 in PARALLEL (`needs: [decide-obsolete]` on both), deliberately occupying both group slots. The smokes execute serially anyway (one runs, one pends), so serial dispatch costs nothing.
2. Nothing tells a second dispatcher on the same tag that the group is owned; GitHub's cancellation is silent.

**Fix, narrow:**
1. Stage 2 `needs: [decide-obsolete, smoke-install]`. Same wall clock, same order, one slot.
2. Each fleet workflow's first job probes `gh run list --json databaseId,status,headSha,name` for a run in the group that is running or pending at the same head sha with a DIFFERENT run id, and FAILS with: `refused: run <id> (<workflow>) owns hetzner-vm-fleet for <tag>; wait for it, or cancel it deliberately, then re-dispatch`. The message is the fix. Hand dispatch remains valid when no one else holds the group on that tag; the probe makes that rule self-enforcing.
3. `dispatch-fleet-and-wait`: if the correlated run concludes `cancelled` with zero jobs, report "cancelled by concurrency: <owning run id>" instead of a bare failure.
4. README (test/install-recovery): never dispatch into the fleet group while an orchestrator is live on the same tag; if you must rerun the orchestrator, wait until `gh run list` shows the group empty.

Not for the rc in flight; lands on master after v2026.09.0.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
<!-- COMMENTS:END -->
