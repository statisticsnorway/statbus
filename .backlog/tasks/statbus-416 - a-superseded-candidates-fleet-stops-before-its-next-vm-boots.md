---
id: STATBUS-416
title: >-
  When a newer release candidate appears, the older candidate's fleet stops
  before taking another box
status: In Progress
assignee: []
created_date: '2026-09-25 09:45'
updated_date: '2026-10-26 13:25'
labels:
  - release-bug
  - ci
dependencies: []
priority: high
type: bug
ordinal: 367000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
When a newer release candidate is tagged, the older candidate's test fleet stops starting new work, reports itself as superseded rather than failed or green, and leaves the capacity to the newer one.

### Zoom out
Release candidates are tested by long fleets (smoke, the LXD fault fleet, upgrade arcs). If rc.N+1 is tagged while rc.N's fleet is still queued, every further rc.N scenario is wasted time on shared capacity. Two rules follow:
- **Stop before, not during:** each scenario checks for a newer candidate just before it would take a box. A scenario already running is left to finish and clean up after itself, because cancelling mid-run strands boxes and contends with the newer fleet.
- **A third verdict:** a stopped fleet is SUPERSEDED, distinct from failed and from green. It never counts as release proof, a real failure with no newer tag stays red, and a missing marker never turns into green.

### Zoom in
- **Incident, 2026-09-25:** rc.02's install-recovery run `36104217764` had three failed scenarios by 07:23Z and 12 still queued at 07:30Z; queued scenarios checked out and then rented a Hetzner VM with no freshness check. The orchestrator checked the newest tag only between stages.
- **Shipped:** `ef32c20c5` (v2026.09.3) adds the shared action `.github/actions/scenario-superseded` (`check.sh`) as the first step after checkout, gates every later step on its output, and aggregates a SUPERSEDED verdict in `test-smoke.yaml` and `upgrade-arc-harness.yaml`. When the fault fleet moved to LXD (`06d2395c2`, 2026-09-28, which also retired `install-recovery-harness.yaml`), `lxd-fleet.yaml` gained the check before any paid operation and again after waiting for box occupancy.
- **Proof, unit:** `TestSupersededCandidateStopsBeforeEachVMAndPropagatesFleetVerdict_STATBUS416` (`cli/cmd/workflow_harness_domain_validation_test.go`) pins the step order and gating for smoke and arcs. Green 2026-10-15. It does not cover `lxd-fleet.yaml`.
- **Observed in CI:** the check runs in every LXD fleet run (for example `38714275075`, `38696133051`, 2026-10-15) but has never fired: none of the 27 LXD fleet runs on record (2026-09-28 to 2026-10-15) logs `SUPERSEDED by`.

### Closing review
- **Memory:** none needed.
- **Documentation:** none needed.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Smoke and upgrade-arc scenario jobs check freshness as the first step after checkout, gate every later step (including cleanup) on it, and aggregate a SUPERSEDED verdict (`TestSupersededCandidateStopsBeforeEachVMAndPropagatesFleetVerdict_STATBUS416`)
- [x] #2 The LXD fault fleet is held to the same rule by a test: freshness before any paid operation and again after the occupancy wait, with a SUPERSEDED verdict distinct from failure
- [ ] #3 One real supersession is observed: a newer RC is tagged while the older RC's fleet is queued; the older fleet's queued scenarios stop before taking a box, its verdict is SUPERSEDED and the newer fleet proceeds; run IDs recorded in Implementation Notes
- [x] #4 [Owner] Decide whether AC3 is forced now or waits for a natural occurrence, and record it in Implementation Notes. Force: add "tag a throwaway RC on top of a queued one" as a new criterion. Wait: leave AC3 open.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1:** green locally on master, 2026-10-15.
- **AC2:** open; `lxd-fleet.yaml` has the checks but no test pins them.
- **AC3:** open; never observed (2026-09-29 audit, rechecked 2026-10-15 against recent LXD fleet logs).
- **Superseded criteria:** the original five criteria targeted the Hetzner install-recovery workflow, retired in `06d2395c2`. The audit asked to rescope to LXD; that is done above.

### AC2 (bbd8ec0fd, 2026-10-16)
- `TestLXDFleetSupersessionStopsBeforePaidWorkAndIsItsOwnVerdict_STATBUS416` (`cli/cmd/workflow_lxd_supersession_test.go`) pins three things in lxd-fleet.yaml. (1) The step order: freshness check, then the occupancy wait, the recheck, the ramp, the driver; both checks are the shared scenario-superseded action, given this run's tag. (2) The gating: the ramp and the driver need both checks clear. (3) The verdict: it **executes** the workflow's own collector and verdict scripts against the real fleet-status.sh for seven outcomes. Superseded at the first check, after the wait, or at a fork batch boundary gives SUPERSEDED. A failed scenario or ramp gives FAILED. A missing driver status gives ERROR. All of these are not green; only PASSED is green.
- **Red, then green:** it ran against a workflow with the ramp's after-wait gate removed and the collector's SUPERSEDED branch disabled. It failed with 'Ramp warm box must be gated on steps.after-wait...' and 'fleet status = STATUS=ERROR, want STATUS=SUPERSEDED' (twice). On the real workflow it passes.

- **CI:** Go Test on bbd8ec0fd failed on two golangci-lint findings in the new test (errcheck f.Close, staticcheck De Morgan); the tests themselves passed. Fixed in b35c70ad5, where golangci-lint reports 0 issues locally and Go Test passes in CI. AC2 is done. AC3 (a real supersession) and the [Owner] AC4 remain.

### Owner decision 2026-10-26: wait for a natural supersession
Nobody has asked for a forced test, so AC3 stays open until a newer candidate is tagged while an older candidate's fleet is still queued. The 527 candidate following today's candidate may produce it.
<!-- SECTION:NOTES:END -->
