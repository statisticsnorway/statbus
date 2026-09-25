---
id: STATBUS-385
title: Before starting StatBus, the installer names any program using a required port and how to free it
status: In Progress
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-25 09:28'
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

## Status 2026-09-25

**In Progress, release blocker.** Candidate `v2026.09.3-rc.02` failed scenario `4-install-port-80-taken.sh`, run `36104217764`, job `107973800497`: after Configuration DONE the terminal printed only the generic settings refusal (exit 78), not Apache's name and remedy. The installer wrapper admits only `port N is in use by ...` on this exit path; a failed Compose ownership probe instead says `port N is in use, but ... could not ask Docker`, which the wrapper replaces with the generic sentence. The job artifact did not collect `install-last-run-output.txt`, so the exact Go-side probe error is not available. The captured independent `docker compose ps` reports missing generated `.env` variables, evidence consistent with a Compose probe failure but not proof of its exact cause.

The local reproducer fakes `apache2` owning port 80 and a failed Compose probe; before the repair it produced the Docker uncertainty error, and after the repair it produces `sudo systemctl disable --now apache2`, saved answers, and the complete rerun command. Unknown owners still retain conservative Docker-probe failure handling. VM acceptance criteria #2-3 remain **proof pending** until the next tagged candidate is run. No push or VM run in this change.

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After setup questions, the installer checks every port selected by the answers. A conflict names the port and owning program, prints a program-appropriate recovery command when one is known, says the answers are saved, and prints the complete rerun command. Apache is one fixture-specific remedy, not a universal fix.

## Evidence, 2026-09-24

The Finland run failed before the web entry point started because port 80 was already in use (`/Users/jhf/ssb/statbus/tmp/finland-transcript-actual.txt:67-80`). The separate provenance record says how Apache arrived on that laptop is undetermined (`/Users/jhf/ssb/.jcode/scratch/apache-origin.md:1-18`). Current startup streams the service-start failure rather than performing the proposed preflight (`cli/cmd/install.go:1374-1381` at master `7a9cf707e`, as indexed by `/Users/jhf/ssb/statbus/tmp/installer-message-audit.md:103-104`).

Failed evidence, 2026-09-24: v2026.09.3-rc.01 (`10f094f2b`) smoke run `36063305786` (`0-happy-install`) failed its idempotent rerun on a healthy box: `cli/cmd/install_ports.go:113-119` string-matched `docker ps` Ports output for `:3014->`, while Docker prints consecutive ports as a range (`127.0.0.1:3014-3015->3014-3015/tcp`), so StatBus's own database port was refused as another program's. A fix is in review on `fix/port-preflight-own-ports` (`e6fc3f739`); real-VM proof remains pending.
<!-- SECTION:DESCRIPTION:END -->

## Release blocker notes

Candidate smoke 0-happy-install run 36063305786 (orchestrator 36063171711) installed successfully but the green-box rerun refused its own proxy port 3014. Docker's `Ports` string compressed 3014-3015, defeating substring matching. Preflight now uses this Compose project's structured per-port `Publishers`, preserving rejection of foreign listeners and other slots; Docker-probe failures report uncertainty rather than blaming another program. Keep In Progress until a candidate VM rerun proves the fix.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: cli/cmd/install_ports_test.go::TestSelectedPortsAndOwners` covers port 80 and a non-80 configured port, reporting the discovered port and owning program before any StatBus service starts.
- [ ] #2 `new: test/install-recovery/scenarios/4-install-port-80-taken.sh` installs Apache, observes zero StatBus service starts, and prints the fixture-specific `sudo systemctl disable --now apache2` recovery command plus the saved-answer rerun command.
- [ ] #3 `new: test/install-recovery/scenarios/4-install-port-80-taken.sh` applies the printed fix, pastes the same rerun command from the home directory, and reaches a ready installation.
<!-- AC:END -->
