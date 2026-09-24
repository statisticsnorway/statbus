---
id: STATBUS-385
title: >-
  Before starting anything, the installer names the program using a port StatBus
  needs and how to free it
status: To Do
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 15:34'
labels:
  - install
dependencies: []
priority: high
type: bug
ordinal: 1
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
At the end of setup questions, the installer checks every network port the selected installation uses. When another program owns a port, the installer names that program in plain words, prints the exact command that frees the port, says the answers are saved, and prints the one install command to continue.

## Evidence, 2026-09-24

Ubuntu Desktop on the Finland laptop included Apache. Apache held port 80, so the first start stopped after partial service creation.

## Proving scenario

New harness scenario `4-install-port-80-taken`: install Apache, run the unattended standalone install, and assert a preflight refusal naming Apache and `sudo systemctl disable --now apache2` before any StatBus service starts. Run that command and repeat the one install command; installation reaches green.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The installer checks every network port selected by the setup answers before starting StatBus.
- [ ] #2 A port conflict message names the program and gives the exact command that frees the port.
- [ ] #3 The `4-install-port-80-taken` scenario reaches green after the printed fix and the same install command.
<!-- AC:END -->
