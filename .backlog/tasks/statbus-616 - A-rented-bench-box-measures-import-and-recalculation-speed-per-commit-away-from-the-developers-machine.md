---
id: STATBUS-616
title: >-
  A rented bench box measures import and recalculation speed per commit, away
  from the developer's machine
status: In Progress
assignee:
  - hibiscus
created_date: '2026-11-11T11:57:00Z'
updated_date: '2026-11-11T13:29:00Z'
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
- [ ] #1 A base, candidate, candidate, base run of rc.01 (4a66d259) against master reports wall time per load and identical fingerprints, recorded in this ticket
- [ ] #2 After down, hcloud lists no bench box
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
<!-- SECTION:NOTES:END -->
