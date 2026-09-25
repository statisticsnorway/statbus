---
id: STATBUS-404
title: Running the install command again preserves an unchanged ready installation
status: In Progress
assignee: []
created_date: '2026-09-24 15:35'
updated_date: '2026-09-25 10:28'
labels:
  - release-bug
  - install
  - idempotency
dependencies: []
priority: high
type: bug
ordinal: 357000
---

## Release gate observation 2026-09-25

**In Progress.** rc.02 (`2198185bb`) smoke [run 36102984100, `0-happy-install` job 107969435877](https://github.com/statisticsnorway/statbus/actions/runs/36102984100/job/107969435877) concluded **success**, including the scenario's unchanged healthy-install rerun (`test/install-recovery/scenarios/0-happy-install.sh`). This is observed-green VM evidence for AC #2, superseding rc.01's failed rerun below. It does not prove the missing Compose v2/v5 fixture (#1) or display-name-only rerun (#3), so do not mark Done.

## Status 2026-09-24

**In Progress.** `8543f493a`, `474cf6119`: `cli/cmd/install.go` and `test/install-recovery/scenarios/0-happy-install.sh` implement an unchanged-rerun check (#2 authored, real-VM proof pending). #1 named Compose v2/v5 fixtures and #3 display-name-only scenario are absent. **Remaining:** test image detection with both Compose formats and prove zero-pull/no-restart unchanged and selective display-name reruns on a VM.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A second install run on a ready unchanged box reports settled steps and performs zero image pulls, zero settings or certificate regeneration, and zero service restarts. A named display-name change regenerates only affected settings and restarts only the application and web entry point.

## Evidence, 2026-09-24

Current image and step convergence logic is at `cli/cmd/install.go:990-1034` at master `7a9cf707e`. The audit records real Compose JSON using `ContainerName` and the mismatch with the parsed field (`/Users/jhf/ssb/statbus/tmp/installer-message-audit.md:144,268-272`). Finland reruns visibly pulled images again (`/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt:31-48,83-100`).

Failed evidence, 2026-09-24: v2026.09.3-rc.01 (`10f094f2b`) smoke run `36063305786` (`0-happy-install`) failed its idempotent rerun on a healthy box: `cli/cmd/install_ports.go:113-119` string-matched `docker ps` Ports output for `:3014->`, while Docker prints consecutive ports as a range (`127.0.0.1:3014-3015->3014-3015/tcp`), so StatBus's own database port was refused as another program's. A fix is in review on `fix/port-preflight-own-ports` (`e6fc3f739`); real-VM proof remains pending.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: cli/cmd/install_images_test.go::TestComposeV2AndV5ContainerNameFixtures` uses captured v2 and v5 JSON fixtures and recognizes every already-present image.
- [ ] #2 `test/install-recovery/scenarios/0-happy-install.sh` performs an unchanged second run and measures zero image pulls, zero settings or certificate regeneration, and zero service restarts.
- [ ] #3 `new: test/install-recovery/scenarios/0-rerun-display-name-change.sh` changes only the display name and observes only settings regeneration plus application and web-entry-point restart, with zero image pulls and no database, API, worker, or automatic-update restart.
<!-- AC:END -->
