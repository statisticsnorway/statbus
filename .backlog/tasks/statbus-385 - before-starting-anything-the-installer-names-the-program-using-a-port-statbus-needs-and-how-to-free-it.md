---
id: STATBUS-385
title: Before starting StatBus, the installer names any program using a required port and how to free it
status: In Progress
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 18:40'
labels:
  - release-bug
  - install
dependencies: []
priority: high
type: bug
ordinal: 1
---

## Status 2026-09-24

**In Progress.** `373d15fc3`: `cli/cmd/install_ports.go` and `cli/cmd/install_ports_test.go::TestPortConflictGuidance` cover port-owner diagnostics (#1 partly, non-80 named test pending). `4-install-port-80-taken.sh` is authored for #2-3, but a successful real-VM run is proof pending. **Remaining:** assert non-80 ownership, then execute Apache refusal and pasted rerun on a real VM.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After setup questions, the installer checks every port selected by the answers. A conflict names the port and owning program, prints a program-appropriate recovery command when one is known, says the answers are saved, and prints the complete rerun command. Apache is one fixture-specific remedy, not a universal fix.

## Evidence, 2026-09-24

The Finland run failed before the web entry point started because port 80 was already in use (`/Users/jhf/ssb/statbus/tmp/finland-transcript-actual.txt:67-80`). The separate provenance record says how Apache arrived on that laptop is undetermined (`/Users/jhf/ssb/.jcode/scratch/apache-origin.md:1-18`). Current startup streams the service-start failure rather than performing the proposed preflight (`cli/cmd/install.go:1374-1381` at master `7a9cf707e`, as indexed by `/Users/jhf/ssb/statbus/tmp/installer-message-audit.md:103-104`).

Failed evidence, 2026-09-24: v2026.09.3-rc.01 (`10f094f2b`) smoke run `36063305786` (`0-happy-install`) failed its idempotent rerun on a healthy box: `cli/cmd/install_ports.go:113-119` string-matched `docker ps` Ports output for `:3014->`, while Docker prints consecutive ports as a range (`127.0.0.1:3014-3015->3014-3015/tcp`), so StatBus's own database port was refused as another program's. A fix is in review on `fix/port-preflight-own-ports` (`e6fc3f739`); real-VM proof remains pending.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: cli/cmd/install_ports_test.go::TestSelectedPortsAndOwners` covers port 80 and a non-80 configured port, reporting the discovered port and owning program before any StatBus service starts.
- [ ] #2 `new: test/install-recovery/scenarios/4-install-port-80-taken.sh` installs Apache, observes zero StatBus service starts, and prints the fixture-specific `sudo systemctl disable --now apache2` recovery command plus the saved-answer rerun command.
- [ ] #3 `new: test/install-recovery/scenarios/4-install-port-80-taken.sh` applies the printed fix, pastes the same rerun command from the home directory, and reaches a ready installation.
<!-- AC:END -->
