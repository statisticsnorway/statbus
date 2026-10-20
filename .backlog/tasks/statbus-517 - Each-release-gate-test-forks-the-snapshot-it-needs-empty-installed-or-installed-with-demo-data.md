---
id: STATBUS-517
title: >-
  Each release-gate test forks the snapshot it needs: empty, installed, or
  installed with demo data
status: In Progress
assignee: []
created_date: '2026-10-17 15:40'
updated_date: '2026-10-20 12:19'
labels:
  - ci
  - lxd
dependencies: []
priority: high
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
- **Documentation:** `test/install-recovery/README.md` describes the checkpoint tree and which tests use which.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Map the 9 install-first faults to `installed-<candidate>` and remove their own first install; each passes in a gate run
- [ ] #2 Add checkpoint `installed-<candidate>-demo`, built once from `installed-<candidate>`; `arc_prepare_box` forks it instead of loading data, shown by arc logs with no demo load
- [ ] #3 Add checkpoint `installed-<prev stable>-demo` and move the fault scenarios that load data on the previous stable to it (`0-https-only-egress`, `1-boot-concurrent-install`, `3-postswap-worker-ddl-deadlock`, `5-install-disk-threshold-repair`, `5-install-seed-on-populated`), shown by their logs with no demo load; smoke's `0-happy-upgrade` keeps loading for real
- [ ] #4 A candidate gate run gives the same verdicts as the preceding candidate and records total guest-minutes against 356 (v2026.10.2-rc.01); run IDs in Implementation Notes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-20: commit 5f96870f7 implements the change (made by a helper agent dolphin started without the owner's approval; the owner chose to land it). What it does:
- Scenarios declare their start in their own file: `# LXD_START=installed-candidate` on the 9 install-first faults; `lxd_checkpoint_for_scenario` reads it and forks `installed-<candidate>-standalone`. The scenario's first candidate install is then answered by the checkpoint after verifying the guest's HEAD (`_lxd_consume_candidate_preinstall`); later installs run for real; a wrong HEAD fails rather than reinstalling.
- Demo layer: `lxd_demo_ensure` builds `installed-<x>-demo` once (fork parent, one real `populate_with_demo_data`, drained worker, snapshot), claimed atomically like arc A. Candidate arcs and the previous-stable faults that load data fork it; their `populate_with_demo_data` only confirms (`HARNESS_DEMO_PRELOADED`). Smoke's 0-happy-upgrade still loads data for real, so the load stays proven per candidate. `LXD_ARC_DEMO_LAYER=0` restores per-arc loading for diagnosis.
- README gains a checkpoint-tree table.
Evidence: new offline contract `tests/lxd-snapshot-layers-test.sh` (fake LXD store, real harness functions) passes, run by dolphin 2026-10-20 12:15 UTC; the commit says it fails on the parent. CI on 5f96870f7: Push on master, Go Test, app build & lint, Harness Selftest, Images, Notify all success; Fast Tests pending at 12:19 UTC.
Not yet proven: every criterion needs a real gate run, which waits for the next release candidate (no RC until sql_saga 1.2, owner 2026-10-20).
<!-- SECTION:NOTES:END -->
