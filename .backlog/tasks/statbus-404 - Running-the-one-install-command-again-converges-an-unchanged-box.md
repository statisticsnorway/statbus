---
id: STATBUS-404
title: Running the install command again preserves an unchanged ready installation
status: To Do
assignee: []
created_date: '2026-09-24 15:35'
updated_date: '2026-09-24 18:44'
labels:
  - install
  - idempotency
dependencies: []
priority: high
type: bug
ordinal: 357000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A second install run on a ready unchanged box reports settled steps and performs zero image pulls, zero settings or certificate regeneration, and zero service restarts. A named display-name change regenerates only affected settings and restarts only the application and web entry point.

## Evidence, 2026-09-24

Current image and step convergence logic is at `cli/cmd/install.go:990-1034` at master `7a9cf707e`. The audit records real Compose JSON using `ContainerName` and the mismatch with the parsed field (`/Users/jhf/ssb/statbus/tmp/installer-message-audit.md:144,268-272`). Finland reruns visibly pulled images again (`/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt:31-48,83-100`).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: cli/cmd/install_images_test.go::TestComposeV2AndV5ContainerNameFixtures` uses captured v2 and v5 JSON fixtures and recognizes every already-present image.
- [ ] #2 `test/install-recovery/scenarios/0-happy-install.sh` performs an unchanged second run and measures zero image pulls, zero settings or certificate regeneration, and zero service restarts.
- [ ] #3 `new: test/install-recovery/scenarios/0-rerun-display-name-change.sh` changes only the display name and observes only settings regeneration plus application and web-entry-point restart, with zero image pulls and no database, API, worker, or automatic-update restart.
<!-- AC:END -->
