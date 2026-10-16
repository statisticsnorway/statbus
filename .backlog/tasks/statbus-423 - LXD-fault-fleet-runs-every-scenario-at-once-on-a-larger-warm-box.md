---
id: STATBUS-423
title: >-
  A candidate full LXD gate reports its verdict in about a quarter of an hour on
  a larger, script-provisioned box
status: To Do
assignee: []
created_date: '2026-09-28 08:18'
updated_date: '2026-10-16 07:59'
labels:
  - ci
  - lxd
dependencies: []
priority: medium
ordinal: 372200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
A release candidate's full LXD gate (fault scenarios and upgrade arcs together) reports its verdict in about a quarter of an hour, so candidates move faster without weakening any check.

### Zoom out
The gate runs every scenario on one shared LXD box, forked from installed checkpoints. Its wall time is set by three things: how many forks run at once, how long the longest scenario takes, and how long the base checkpoints take to build. More concurrency only helps while each fork still gets real CPU: timing-sensitive scenarios (startup timeout, concurrent install) can fail falsely when the box is oversubscribed, so concurrency must grow with the box, never ahead of it. The box is created on demand and reaped when idle, so a larger box costs little; its size must be chosen by the provisioning script, never changed by hand.

### Zoom in
- **Measured at filing (rc.12, run `36388841250`):** 25 scenarios, 6,957 s of work, longest 419 s; 6 forks at a time for 29 min; bases built one after another in 4.3 min; about 34 min overall.
- **Measured now (v2026.10.1, 2026-10-15):** fault fleet `38740447079` took 52 min (13:10-14:02) for 27 scenarios and 11,301 s of work; the longest is now `5-install-source-identity-operator` at 1,261 s. The upgrade arcs (`38740570520`, 13:11-14:07) share the same box since STATBUS-425, so the two gates compete for it.
- **Current limits:** `run-forks.sh` caps `LXD_PARALLEL` at 1-8 (default 6); host admission allows `LXD_HOST_SLOTS=8` (`ops/lxd-fleet/admission.sh`); each fork is `limits.cpu=2`, `limits.memory=6GiB` (`lib/lxd-backend.sh`); the box is a Hetzner `ccx33` (8 vCPU, 32 GB), hard-coded and checked in `ops/lxd-fleet/up.sh`, which refuses any other type.
- **Proposal (not started):** a larger type (for example CCX53, 32 vCPU / 128 GB) with a larger Btrfs pool and slots sized to it; build independent bases in parallel with per-base locks; schedule longest-first from the previous run's `comparison.tsv`.
- **Floor:** with the longest scenario at 1,261 s, a fork phase cannot finish under about 21 minutes, so a 15-minute target needs that scenario shortened or split as well.

### Closing review
- **Memory:** none needed.
- **Documentation:** `test/install-recovery/README.md` should state the box type and slot count once chosen.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `ops/lxd-fleet/up.sh` creates the fleet box on the chosen larger type, and recreates an existing box of the old type through its drift handling, with no manual step
- [ ] #2 Host slots and `LXD_PARALLEL` are sized to the new box so that no fork gets less than its 2 vCPU, shown by the admission settings and one run's CPU steal or load record
- [ ] #3 Independent checkpoint bases build in parallel, each under its own lock, shown by overlapping base build times in a run's driver log
- [ ] #4 Forks are scheduled longest-first from the previous run's `comparison.tsv`, shown by the dispatch order in a run's driver log
- [ ] #5 A full candidate gate (fault fleet and upgrade arcs) on the new box gives the same verdict per scenario as the preceding candidate's run; both run IDs recorded in Implementation Notes
- [ ] #6 Dispatch-to-verdict wall time for that run is recorded in Implementation Notes, including the cold ramp
- [ ] #7 [Owner] Set the wall-time target, given the longest scenario (1,261 s, about 21 minutes, measured 2026-10-15), and record it in Implementation Notes. Under 21 minutes: add "shorten or split `5-install-source-identity-operator`" as a new criterion. 21 minutes or more: the measurement in AC6 decides Done.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- 2026-10-16 grounding: fault fleet `38740447079` and arc harness `38740570520` timings from GitHub; scenario seconds from the run's `comparison.tsv` artifact (copied to `tmp/vet/fleet-38740447079/`); limits read from `run-forks.sh`, `admission.sh`, `lxd-backend.sh` and `up.sh` on master `e804329c8`.
- No work has started; status stays To Do.
<!-- SECTION:NOTES:END -->
