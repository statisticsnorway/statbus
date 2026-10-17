---
id: STATBUS-517
title: >-
  Each release-gate test forks the snapshot it needs: empty, installed, or
  installed with demo data
status: To Do
assignee: []
created_date: '2026-10-17 15:40'
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
- 4 faults load demo data on the previous stable: `0-happy-upgrade`, `1-boot-concurrent-install`, `3-postswap-worker-ddl-deadlock`, `5-install-seed-on-populated`.
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
- [ ] #3 Add checkpoint `installed-<prev stable>-demo` and move the 4 data-loading faults to it, shown by their logs with no demo load
- [ ] #4 A candidate gate run gives the same verdicts as the preceding candidate and records total guest-minutes against 356 (v2026.10.2-rc.01); run IDs in Implementation Notes
<!-- AC:END -->
