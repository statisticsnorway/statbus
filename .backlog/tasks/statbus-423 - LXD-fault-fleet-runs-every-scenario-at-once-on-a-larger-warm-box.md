---
id: STATBUS-423
title: >-
  A candidate full LXD gate reports its verdict in about a quarter of an hour on
  a larger, script-provisioned box
status: To Do
assignee: []
created_date: '2026-09-28 08:18'
updated_date: '2026-10-16 13:55'
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
- **Latest measurement (v2026.10.2-rc.01, orchestrator `38818198690`, 75 min):** after smoke (12 min) and dev (2 min), the fault fleet (46 min, 27 scenarios, longest 1,142 s) and the upgrade arcs (60 min, 35 arcs behind `max-parallel: 4`) share the box since STATBUS-425. The arcs set the verdict time; breakdown in Implementation Notes.
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
- [ ] #1 `ops/lxd-fleet/up.sh` creates the fleet box on the type chosen in AC10, and recreates an existing box of the old type through its drift handling, with no manual step
- [ ] #2 Host slots and `LXD_PARALLEL` are sized to the new box so that no fork gets less than its 2 vCPU, shown by the admission settings and one run's CPU steal or load record
- [ ] #3 Independent checkpoint bases build in parallel, each under its own lock, shown by overlapping base build times in a run's driver log
- [ ] #4 Forks are scheduled longest-first from the previous run's `comparison.tsv`, shown by the dispatch order in a run's driver log
- [ ] #5 A full candidate gate (fault fleet and upgrade arcs) on the new box gives the same verdict per scenario as the preceding candidate's run; both run IDs recorded in Implementation Notes
- [ ] #6 Dispatch-to-verdict wall time for that run is recorded in Implementation Notes, including the cold ramp
- [ ] #7 [Owner] Set the wall-time target, given the longest scenario (1,261 s, about 21 minutes, measured 2026-10-15), and record it in Implementation Notes. Under 21 minutes: add "shorten or split `5-install-source-identity-operator`" as a new criterion. 21 minutes or more: the measurement in AC6 decides Done.
- [ ] #8 The upgrade-arc matrix `max-parallel` is set to the `LXD_HOST_SLOTS` count chosen in AC2, so arcs use slots the faults free; a run shows more than 4 arc guests at once and its arc wall time is recorded in Implementation Notes
- [ ] #9 After `PAR` forks, `run-forks.sh` starts the next fork when any running fork ends, not when the oldest ends, shown by fork start times in a run's driver log following the earliest end
- [ ] #10 [Owner] Choose the box type after the arc-cap and dispatch changes (AC8, AC9) have run once, using that run's wall time and boot-time-under-load record, and record it in Implementation Notes. A larger type: AC1-AC3 proceed. Keep `ccx33`: AC1 is struck and AC2 sizes slots to the current box.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- 2026-10-16 grounding: fault fleet `38740447079` and arc harness `38740570520` timings from GitHub; scenario seconds from the run's `comparison.tsv` artifact (copied to `tmp/vet/fleet-38740447079/`); limits read from `run-forks.sh`, `admission.sh`, `lxd-backend.sh` and `up.sh` on master `e804329c8`.
- No work has started; status stays To Do.

### Timing breakdown, v2026.10.2-rc.01 (2026-10-16)
Runs: orchestrator `38818198690` (75 min), smoke `38818339306`, fault fleet `38819807364`, arcs `38819893048`. Analysis and derived tables: `tmp/lxd-explain/how-it-runs.md`, `arc-phases.txt`, `occupancy.txt`.
- **Critical path:** smoke 12 min, dev 2 min, then arcs 60 min. The fault fleet (46 min) ends 15 min before the arcs, so arcs set the verdict time.
- **Arcs:** 35 arcs with 201 min of job time behind GitHub `max-parallel: 4`. After the faults end at 23:36, 4 of the 8 host slots stay idle for 15 min because no more than 4 arc jobs exist. The workflow comment says host admission, not `max-parallel`, bounds guests. The replay below gives the effect of raising it.
- **Faults:** dispatched alphabetically. The two 19-min `5-install-source-identity-*` scenarios start at position 20/21 (23:11) and end at 23:30; the replay below gives the effect of other orders. Each spends 5 min waiting for the old v2026.09.2 daemon to mark the false target's images ready, and installs v2026.09.2 from scratch.
- **Box use:** 6.1 guests running on average over the 54 busy minutes, 8 slots. No CPU load or steal is recorded, so the cost of 2x CPU oversubscription is unknown (AC2).
- **Fresh install:** every fresh install waits about 76 s before Seed, in `checkSeedRestored` (`cli/cmd/install.go:2904`, 15 x 2 s retry on an empty database, called twice). Seen in both smoke installs and all 15 fresh-install fault scenarios. This also costs real first installs; tracked separately.

### Hypotheses tested (2026-10-16, no code changed)
Scripts and outputs: `tmp/lxd-explain/intervals.py` (per-guest intervals, `cur.tsv`, `prev.tsv`), `simulate.py` (schedule replay, `simulate-cur.txt`).
- **CPU oversubscription (H1):** guest boot/readiness takes a median of 16 s with 4 or fewer guests running and 28 s with 7 or more (rc.01, 61 guests; correlation 0.6). Whole-scenario durations show no measurable link to concurrency: correlation -0.01 and 0.15 within the v2026.10.1 and rc.01 runs, and -0.09 between them for the same 62 guests. Oversubscription costs boot seconds, not scenario minutes, at the current 8 slots.
- **Fault dispatch is head-of-line blocked (new finding):** after 6 forks, `run-forks.sh` waits on `pids[0]`, the oldest fork, not on whichever ends first. So fork *i* starts only after fork *i*-6 ends. Measured start delay against "start when any slot frees": 40 min summed in rc.01 and 45 min in v2026.10.1. The worst cases are `5-install-stage-e-worker-busy` and `6-uninstall-reinstall`, which waited 12 min behind the 19-min source-identity scenarios.
- **Schedule replay (H2):** measured durations, fixed. The as-run model reproduces the real faults end (23:36) and is 4 min late on the arcs (23:54 against 23:50). Gate wall time compared with the as-run model:

  | Policy | Faults end | Arcs end | Gate |
  |---|---|---|---|
  | Faults longest-first only | 23:34 | 23:55 | +1 min |
  | Faults wait-any only | 23:28 | 23:58 | +4 min |
  | Arcs max-parallel 8 | 23:37 | 23:47 | -7 min |
  | Arcs 8, both longest-first | 23:36 | 23:42 | -12 min |
  | Same plus wait-any | 23:24 | 23:41 | -13 min |
  | 16 slots, faults 8 (bigger box) | 23:17 | 23:20 | -34 min |

  Fault-side changes alone do not shorten the gate, because they hand slots to nobody: the arcs, capped at 4, are the long pole. Raising the arc cap is the first lever; ordering both lanes longest-first adds 5 min. A 16-slot box is the only change near the 15-min target for the parallel phase, and the boot-time result says it must keep 2 vCPU per guest (AC2).
- **Source-identity 5-min wait (H3):** the false target v2026.09.3 is upgrade row 29 (27 in v2026.10.1). The wait is stable at 280-311 s across both runs. Mechanism, validated by prediction: the box follows the prerelease channel (`HARNESS_UPGRADE_CHANNEL`), so the old v2026.09.2 daemon discovers every tag and verifies pending rows newest first (`ORDER BY committed_at DESC LIMIT 30`) on its main goroutine, as commit `649e97ffc` traced. Two arc journals in rc.01 show each row's verify taking 12-14 s (`Images verified` lines 23:11:43, :56, 23:12:10 and 23:42:59, 23:43:11, :23, :37). Tags that existed then put 24 distinct commits ahead of v2026.09.3 (23 for v2026.10.1). That predicts 288-336 s and 276-322 s; observed 280-311 s and 278-308 s. The wait grows by about 13 s with every newer release. The scenario could narrow what the old box discovers; that changes the proof's realism, so it is an owner call and is not added as a criterion.

<!-- SECTION:NOTES:END -->
