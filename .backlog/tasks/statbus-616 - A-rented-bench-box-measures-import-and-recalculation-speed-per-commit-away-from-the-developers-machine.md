---
id: STATBUS-616
title: >-
  A rented bench box measures import and recalculation speed per commit, away
  from the developer's machine
status: In Progress
assignee:
  - hibiscus
created_date: '2026-11-11T11:57:00Z'
updated_date: '2026-11-11T11:59:00Z'
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
- [ ] #5 test/import_benchmark.py --worker-in-container runs the worker inside the compose worker container (the commit's statbus-worker image): the round log shows the worker started with docker compose exec and the import finished
- [ ] #6 [Owner] Each workaround in Implementation Notes gets a decision, recorded here: keep it in bench-box, or fix it in setup or the scripts as its own change
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Workarounds and findings while building the bench box (for the owner, to decide on systematic fixes):
1. test/import_benchmark.py runs the worker only as a host binary (cli/bin/statbus), which needs Crystal on the host. Fix in this ticket: a --worker-in-container flag that runs the commit's worker image instead.
2. Non-interactive setup needs SERVER_FQDN even on a box with no public name; the bench box sets a .local name, as manual-box does.
3. Setup's core tools lack python3-venv, which the benchmark and BRREG scripts need; bench-box installs it with apt.
<!-- SECTION:NOTES:END -->
