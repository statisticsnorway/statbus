---
id: STATBUS-423
title: >-
  A candidate's LXD gate runs as one ordered queue on the existing box and keeps
  every slot busy
status: To Do
assignee: []
created_date: '2026-09-28 08:18'
updated_date: '2026-10-20 20:29'
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
A release candidate's whole LXD gate runs as one queue on the existing box, keeping every slot busy, so the verdict comes as fast as the work allows without a larger machine.

### Zoom out
The gate's tests are independent jobs on one shared box. When separate limiters each decide part of what runs, none sees the whole queue, so slots sit idle while work waits. One runner that owns the queue, orders it (checkpoints first, smoke-critical jobs early, then longest first) and starts the next job the moment a slot frees, removes that waste. Slot count is then raised only as far as measured contention allows. The owner's principle: fix the architecture rather than buy a faster box.

### Zoom in
- **Limiters today:** GitHub's arc matrix (`max-parallel: 4`), the fault driver (6 at a time, each new one waiting for the oldest), and host admission (8 slots).
- **Measured (v2026.10.2-rc.01, orchestrator `38818198690`, 75 min):** smoke 12, dev 2, then faults (46) and arcs (60) in parallel; box 6.1 of 8 slots busy on average; fault start delay from the oldest-first wait 40 min summed (45 in v2026.10.1).
- **Replay** (`tmp/lxd-explain/simulate.py`, validated out of sample on v2026.10.1, within 2-4 min): parallel phase 54 min today; one queue 45 / 31 / 24 min at 8 / 12 / 16 slots; with STATBUS-514/516/517 waits removed 37 / 25 / 19 min.
- **Contention:** guest boot takes 16 s median with 4 or fewer guests and 28 s with 7 or more; whole-test durations show no link to load at 8 slots.
- **Design (owner decision 2026-10-17, option A):** a runner on the box takes a run manifest (candidate, jobs with checkpoint, script, expected duration), builds checkpoints, runs one ordered queue, writes a result file per job as it finishes, and cancels the queue of a superseded candidate. One long GitHub job submits the manifest, follows progress, uploads all logs as one artifact and sets the verdict. Design record: `tmp/lxd-gate-design.md` (T7).

### Closing review
- **Memory:** none needed.
- **Documentation:** `test/install-recovery/README.md` and `doc/release-ladder.md` describe the runner, the manifest and how results reach GitHub.
- **Cleanup:** retire the arc matrix, `run-forks.sh` dispatch and the admission slot files once the runner replaces them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Write the runner: it reads a run manifest, builds missing checkpoints in dependency order, runs one queue ordered checkpoints, smoke-critical, then longest first, and starts a job when any slot frees; a harness test shows the order and the any-slot start
- [ ] #2 The runner writes a result file per job as it finishes and cancels queued jobs when a newer candidate arrives; a harness test shows both
- [ ] #3 Replace the fault dispatch, the arc matrix and host admission with one GitHub job that submits the manifest, follows progress, uploads all logs as one artifact and sets the verdict
- [ ] #4 A full candidate gate through the runner gives the same verdict per test as the preceding candidate; both run IDs and the dispatch-to-verdict time recorded in Implementation Notes
- [ ] #5 Record per-run load average and guest boot times in the gate artifact, at the current slot count and at one higher count
- [ ] #6 [Owner] Choose the slot count for the existing box from those records and note it in Implementation Notes. The runner then uses that count; a count that raises boot times past the scenario timeouts is not chosen
- [ ] #7 Start the arc fixture construct and image builds at the gate decision, in parallel with the runner's checkpoints and smoke jobs; shown by fixture build start times before the first smoke job ends in a run
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

### Reshaped 2026-10-17 (owner decision)
The owner chose architecture over a larger box: one queue runner on the existing box, one long GitHub job (option A), slots set from measured contention. The earlier criteria (larger type via `up.sh`, per-base locks, longest-first in `run-forks.sh`, arc `max-parallel`, wait-any dispatch, box-type choice) are superseded by the runner. The removal of old-version tests, snapshot use and fixture timing moved to STATBUS-516, STATBUS-517 and STATBUS-518.

2026-10-20 owner decision: starting arc fixtures at the gate decision moves here from STATBUS-518. Today's workflows make the arc harness share the hetzner-vm-fleet concurrency group with smoke, so an early start there would still wait for smoke; the runner removes that ordering, so it delivers the early start. Not to be designed yet (owner pushed back on starting the runner design now); it stays in the todo list.
<!-- SECTION:NOTES:END -->
