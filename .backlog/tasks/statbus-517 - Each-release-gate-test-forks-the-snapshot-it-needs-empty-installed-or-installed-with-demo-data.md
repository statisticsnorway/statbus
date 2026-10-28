---
id: STATBUS-517
title: >-
  Each release-gate test forks the snapshot it needs: empty, installed, or
  installed with demo data
status: Done
assignee: []
created_date: 2026-10-17 15:40
updated_date: '2026-10-28T02:47:00Z'
labels:
  - ci
  - lxd
dependencies: []
priority: high
type: enhancement
ordinal: 443204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
A gate test spends its time on the fault it tests, never on rebuilding a state another snapshot already holds.

### Zoom out
The gate forks guests from checkpoints. Only a test of a failure during installation needs an empty box. A test that installs cleanly and then breaks something needs an installed box; a test that needs data needs an installed box with data. Each state is built once per candidate and forked many times.

### Zoom in
- Checkpoints today: `hardened-nothing-installed`, `installed-<prev stable>-standalone`, `installed-<candidate>-standalone`.
- 9 faults on the empty checkpoint install cleanly first, then break something, and read nothing from that first install (checked 2026-10-17): `5-install-stage-a` to `-e`, `5-install-bool-text-regression`, `5-install-proxy-never-started`, `5-install-live-upgrade-wait`, `6-uninstall-reinstall`. Each pays a full install, 2.5-4 min.
- All 35 arcs load demo data in `arc_prepare_box` (`lib/arc-helpers.sh`), about 70 s each, about 40 guest-min per candidate; they only assert the data survives. `worker-wedge-mid-derive` creates its own derive work afterwards.
- Faults that load demo data on the previous stable: `1-boot-concurrent-install`, `3-postswap-worker-ddl-deadlock`, `5-install-seed-on-populated`, and `0-https-only-egress` and `5-install-disk-threshold-repair`, which delegate to `0-happy-upgrade`. Smoke runs `0-happy-upgrade` itself and keeps loading for real.
- Owner decision 2026-10-17 (T2, T5 in `tmp/lxd-gate-design.md`).

### Closing review
- **Memory:** none needed.
- **Documentation:** `test/install-recovery/README.md` needs the checkpoint tree (which checkpoint each test forks, who builds it); added in 5f96870f7.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Add checkpoint `installed-<candidate>-demo`, built once from `installed-<candidate>`; `arc_prepare_box` forks it instead of loading data, shown by arc logs with no demo load
- [x] #2 Add checkpoint `installed-<prev stable>-demo` and move the fault scenarios that load data on the previous stable to it (`0-https-only-egress`, `1-boot-concurrent-install`, `3-postswap-worker-ddl-deadlock`, `5-install-disk-threshold-repair`, `5-install-seed-on-populated`), shown by their logs with no demo load; smoke's `0-happy-upgrade` keeps loading for real
- [x] #3 A candidate gate run gives the same verdicts as the preceding candidate, and its total guest-minutes for the fault fleet plus arcs are below 356 (v2026.10.2-rc.01) by at least the removed first-install and demo-load time (about 40 + 25 guest-min); totals and run IDs in Implementation Notes
- [x] #4 Map the 9 install-first faults to `installed-<candidate>-standalone` and remove their own first install; each passes in a gate run
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-20: commit 5f96870f7 implements the change. What it does:
- Scenarios declare their start in their own file: `# LXD_START=installed-candidate` on the 9 install-first faults; `lxd_checkpoint_for_scenario` reads it and forks `installed-<candidate>-standalone`. The scenario's first candidate install is then answered by the checkpoint after verifying the guest's HEAD (`_lxd_consume_candidate_preinstall`); later installs run for real; a wrong HEAD fails rather than reinstalling.
- Demo layer: `lxd_demo_ensure` builds `installed-<x>-demo` once (fork parent, one real `populate_with_demo_data`, drained worker, snapshot), claimed atomically like arc A. Candidate arcs and the previous-stable faults that load data (0-https-only-egress, 1-boot-concurrent-install, 3-postswap-worker-ddl-deadlock, 5-install-disk-threshold-repair, 5-install-seed-on-populated) fork it; their `populate_with_demo_data` only confirms (`HARNESS_DEMO_PRELOADED`). Smoke's 0-happy-upgrade still loads data for real, so the load stays proven per candidate. `LXD_ARC_DEMO_LAYER=0` restores per-arc loading for diagnosis.
- README gains a checkpoint-tree table.
Evidence: offline contract `tests/lxd-snapshot-layers-test.sh` (fake LXD store, real harness functions) fails against the parent's backend (tmp/test-517-parent.log: "install-first scenario did not select installed-<candidate>") and passes on 5f96870f7 (tmp/test-517-fixed.log); `./dev.sh test-harness` green (tmp/test-517-harness.log). CI on 5f96870f7: Push on master, Go Test, app build & lint, Harness Selftest, Images, Notify all success.
Not yet proven: every criterion needs a real gate run, which waits for the next release candidate (no RC until sql_saga 1.2, owner 2026-10-20).

Partial candidate evidence at rc.03. AC2: all five previous-stable data scenarios passed in LXD Fork Fleet 40608110641 from installed-v2026.10.3-demo; logs explicitly confirm preloaded data instead of loading (tmp/517-rc03-demo-checkpoints.log). AC4: all nine install-first faults passed from installed-v2026.10.4-rc.03-standalone in the same run. Upgrade Arc Harness 40608201147 is green. AC1 and AC3 remain open pending complete arc/checkpoint and timing evidence; this note does not close them.

Full rc.05 candidate evidence completes this ticket. AC1: Upgrade Arc Harness 40618429007 is green; 32 arc artifacts explicitly name installed-v2026.10.4-rc.05-demo and say 'demo dataset preloaded by the forked checkpoint; confirming instead of loading'. The postswap-mid-tx-kill artifact begins after its preparation section and contains no demo-load operation; all 35 arc jobs passed without a per-arc demo load (tmp/517-rc05-arc-demo-coverage.log). AC3: the same expected verdicts are green across 25 fault scenarios and 35 arc jobs. Fault fleet 40618330397 totals 5141 seconds (85.68 guest-min); arc harness 40618429007 totals 8878 seconds (147.97 guest-min), combined 14019 seconds (233.65 guest-min). That is below 356 by 122.35 minutes and below the required 291-minute ceiling by 57.35 minutes, exceeding the roughly 65-minute saving. Raw timings: tmp/517-rc05-fault-time.txt and tmp/517-rc05-arc-time.json. AC2 and AC4 were previously verified on rc.03 and remain green on rc.05.
<!-- SECTION:NOTES:END -->
