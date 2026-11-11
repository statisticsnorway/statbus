---
id: STATBUS-616
title: >-
  A rented bench box measures import and recalculation speed per commit, away
  from the developer's machine
status: In Progress
assignee:
  - hibiscus
created_date: '2026-11-11T11:57:00Z'
updated_date: '2026-11-11T19:19:00Z'
labels:
  - performance
  - ops
dependencies: []
type: feature
ordinal: 530204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Speed changes are measured by comparing two commits on the same full-register loads, with identical results, on a machine that shows only the difference between them.

Zoom out: a speed claim holds only for the machine it was measured on, so it is measured on an isolated host of production size under no other load, never on a developer's machine or a canary host that serves users. The host exists only for the measurement, so nothing it holds outlives the work.

Zoom in: ops/bench-box.sh rents a Hetzner ccx33 (8 dedicated cores, 32 GB) next to rune, prepares it with the published setup script (base system, service account, Docker), copies the BRREG files from rune, and runs rounds. Each round checks out a commit, takes sb from that commit's statbus-sb image, pulls that commit's images, rebuilds the seed and test template, imports the full BRREG files into a fresh database with that commit's worker image, runs a full recalculation, and fingerprints the derived tables. Results are copied back to tmp/bench/. down deletes the box.

Workarounds found while building it are recorded in this ticket's Implementation Notes.

Closing review: ops/bench-box.sh documents itself in its usage text, linked from doc/development-reference.md; no memory change; cleanup is down, checked by criterion 2.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A base, candidate, candidate, base run of rc.01 (4a66d259) against master reports wall time per load and identical fingerprints, recorded in this ticket
- [x] #2 After down, hcloud lists no bench box
- [ ] #3 A round takes all code from the commit under test, checked by the round log: it records the commit's sb version (./sb --version), the image tag of each running container (docker compose images), and the seed's newest migration, all naming that commit
- [ ] #4 ops/bench-box.sh without arguments prints its usage and exits 2; up, status, ssh, data, run, results and down each exit 0 against a real box, and run leaves a round log and fingerprint per round in tmp/bench/
- [x] #5 [Owner] Each workaround in Implementation Notes gets a decision, recorded here: keep it in bench-box, or fix it in setup or the scripts as its own change
- [ ] #6 Each round runs the worker as a one-off container of the commit's statbus-worker image (docker compose run worker ... --stop-when-idle), with no Crystal or Go on the box: the round log names the worker image tag and every import job finished
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Findings while building the bench box, each fixed where it lives (owner, 2026-11-11: fix as we go, land early):
1. test/import_benchmark.py starts the worker only as a host binary, which needs Crystal. Owner chose option A: the box runs the commit's worker image (docker compose run of the worker service), so the box needs no compiler.
2. dev.sh fetched sb from its image again on every call on a fresh Linux clone (the copied binary kept the image's build time). Fixed in f26c17644, test dev-sb-procurement-test.sh RED 2 fetches, GREEN 1.
3. run_bounded left its timer's sleep holding the test-run lock up to 120 s after dev.sh exited. Fixed in f26c17644, test dev-run-bounded-test.sh RED 1 holder, GREEN 0 (3 of 3 runs each).
4. brreg-import-downloads-from-tmp.sh failed since STATBUS-600 (missing status_code). Fixed in ca8f444f5: fits each file as brreg-monthly does; 200-row check RED COPY error, GREEN 160 rows (159 active, 1 passive).
5. Setup's core tools lacked python3-venv, which StatBus's Python helpers need. Fixed in 3824b3407.
6. Setup asks every StatBus server for its full name; a box with no public name is given a .local one, as manual-box does. That is setup's intended contract, not a gap.
Landed on master: f26c17644 and ca8f444f5 (Rabbit, ca8f444f5).

First master round (081fd660), stopped at 14:07 to free the dedicated cores for the rc.02 release ladder (Hetzner's dedicated-core limit holds one ccx33; the LXD fleet host is one). By then the import had processed 944,000 of 1,134,476 legal units in 45 minutes (13:22-14:07, load 2.7-3.5 on 8 cores); establishments (823,768) and relationships (33,710) not started. Partial logs in tmp/bench/20261111T132150Z/. Verified on the real box: up, data (945 MB from rune in 10 s, md5 equal), run (detached, returns in 1 s), progress, results, down (exit 0, hcloud lists no statbus-bench); usage without arguments exits 2. f2828f4cb: up refuses while any dedicated-core server runs.

Bench series 2026-11-11 on ccx33 (8 dedicated cores), rune dump no_20261110_161917 (1,134,475 legal units, 823,767 establishments), each commit from the same frozen copy (CREATE DATABASE TEMPLATE, 68-76 s). Wall seconds, rc.01 4a66d2591 vs master d6978425d (rc.02 + STATBUS-622), 0 failed tasks in every run:
- full recalculation: 740 vs 512 (-31%). Refresh batches 1,614 s in 3,162 vs 1,068 s in 451; history 482 vs 394; flush 61 vs 41. Fingerprints identical on every public table except relative_period (removed by STATBUS-606).
- 1% (11,344 LU renamed): 74 vs 70. Facets dominate (63 vs 57 s summed).
- 50% (567,249): 850 vs 835. Flush 453 vs 452, refresh 766 vs 716.
- 99% (1,123,131): 1,626 vs 1,698. Flush 874 vs 970, history 827 vs 611, refresh 1,492 vs 1,399.
- 3 legal units renamed, 3 rounds: master 20.6/21.6/19.6 s, rc.01 19.7/22.6/20.6 s.
Change-run fingerprints are not comparable in this run: the rename text carried the per-commit label (fixed in 409138e65). Results in tmp/bench/20261111-series/. Box deleted 19:18.
<!-- SECTION:NOTES:END -->
