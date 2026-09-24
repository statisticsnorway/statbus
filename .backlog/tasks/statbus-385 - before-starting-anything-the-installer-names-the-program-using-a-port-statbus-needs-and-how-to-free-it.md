---
id: STATBUS-385
title: Before starting StatBus, the installer names any program using a required port and how to free it
status: In Progress
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 18:40'
labels:
  - install
dependencies: []
priority: high
type: bug
ordinal: 1
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After setup questions, the installer checks every port selected by the answers. A conflict names the port and owning program, prints a program-appropriate recovery command when one is known, says the answers are saved, and prints the complete rerun command. Apache is one fixture-specific remedy, not a universal fix.

## Evidence, 2026-09-24

The Finland run failed before the web entry point started because port 80 was already in use (`/Users/jhf/ssb/statbus/tmp/finland-transcript-actual.txt:67-80`). The separate provenance record says how Apache arrived on that laptop is undetermined (`/Users/jhf/ssb/.jcode/scratch/apache-origin.md:1-18`). Current startup streams the service-start failure rather than performing the proposed preflight (`cli/cmd/install.go:1374-1381` at master `7a9cf707e`, as indexed by `/Users/jhf/ssb/statbus/tmp/installer-message-audit.md:103-104`).
<!-- SECTION:DESCRIPTION:END -->

## Release blocker notes

Candidate smoke 0-happy-install run 36063305786 (orchestrator 36063171711) installed successfully but the green-box rerun refused its own proxy port 3014. Docker's `Ports` string compressed 3014-3015, defeating substring matching. Preflight now uses this Compose project's structured per-port `Publishers`, preserving rejection of foreign listeners and other slots; Docker-probe failures report uncertainty rather than blaming another program. Keep In Progress until a candidate VM rerun proves the fix.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: cli/cmd/install_ports_test.go::TestSelectedPortsAndOwners` covers port 80 and a non-80 configured port, reporting the discovered port and owning program before any StatBus service starts.
- [ ] #2 `new: test/install-recovery/scenarios/4-install-port-80-taken.sh` installs Apache, observes zero StatBus service starts, and prints the fixture-specific `sudo systemctl disable --now apache2` recovery command plus the saved-answer rerun command.
- [ ] #3 `new: test/install-recovery/scenarios/4-install-port-80-taken.sh` applies the printed fix, pastes the same rerun command from the home directory, and reaches a ready installation.
<!-- AC:END -->
