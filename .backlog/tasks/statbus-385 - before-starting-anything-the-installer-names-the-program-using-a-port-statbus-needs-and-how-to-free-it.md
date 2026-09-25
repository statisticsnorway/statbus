---
id: STATBUS-385
title: Before starting StatBus, the installer names any program using a required port and how to free it
status: In Progress
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-25 16:35'
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

**Merged follow-up, proof pending.** `645a96236` (merge `56bfb8b36`) preserves a named Apache owner when the Docker ownership probe fails; `cli/cmd/install_ports_test.go:112-113` asserts the remedy and saved-answer rerun. rc.02 at `2198185bb` failed not only `4-install-port-80-taken` ([run 36104217764, job 107973800497](https://github.com/statisticsnorway/statbus/actions/runs/36104217764/job/107973800497)) but also phase a of `5-install-orphaned-db-volume-credentials` ([job 107973801514](https://github.com/statisticsnorway/statbus/actions/runs/36104217764/job/107973801514)), whose required port-80 cause/remedy is checked at `test/install-recovery/scenarios/5-install-orphaned-db-volume-credentials.sh:79-100`. Neither failed VM path proves AC #2-3. Await rc.03 reruns.

**In Progress, release blocker.** Candidate `v2026.09.3-rc.02` failed scenario `4-install-port-80-taken.sh`, run `36104217764`, job `107973800497`: after Configuration DONE the terminal printed only the generic settings refusal (exit 78), not Apache's name and remedy. The installer wrapper admits only `port N is in use by ...` on this exit path; a failed Compose ownership probe instead says `port N is in use, but ... could not ask Docker`, which the wrapper replaces with the generic sentence. The job artifact did not collect `install-last-run-output.txt`, so the exact Go-side probe error is not available. The captured independent `docker compose ps` reports missing generated `.env` variables, evidence consistent with a Compose probe failure but not proof of its exact cause.

The local reproducer fakes `apache2` owning port 80 and a failed Compose probe; before the repair it produced the Docker uncertainty error, and after the repair it produces `sudo systemctl disable --now apache2`, saved answers, and the complete rerun command. Unknown owners still retain conservative Docker-probe failure handling. VM acceptance criteria #2-3 remain **proof pending** until the next tagged candidate is run. No push or VM run in this change.

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After setup questions, the installer checks every port selected by the answers. A conflict names the port and owning program, prints a program-appropriate recovery command when one is known, says the answers are saved, and prints the complete rerun command. Apache is one fixture-specific remedy, not a universal fix.

## Evidence, 2026-09-24

The Finland run failed before the web entry point started because port 80 was already in use (`/Users/jhf/ssb/statbus/tmp/finland-transcript-actual.txt:67-80`). The separate provenance record says how Apache arrived on that laptop is undetermined (`/Users/jhf/ssb/.jcode/scratch/apache-origin.md:1-18`). Current startup streams the service-start failure rather than performing the proposed preflight (`cli/cmd/install.go:1374-1381` at master `7a9cf707e`, as indexed by `/Users/jhf/ssb/statbus/tmp/installer-message-audit.md:103-104`).

Failed evidence, 2026-09-24: v2026.09.3-rc.01 (`10f094f2b`) smoke run `36063305786` (`0-happy-install`) failed its idempotent rerun on a healthy box: `cli/cmd/install_ports.go:113-119` string-matched `docker ps` Ports output for `:3014->`, while Docker prints consecutive ports as a range (`127.0.0.1:3014-3015->3014-3015/tcp`), so StatBus's own database port was refused as another program's. A fix is in review on `fix/port-preflight-own-ports` (`e6fc3f739`); real-VM proof remains pending.
## rc.03 evidence and fix, 2026-09-25

rc.03 run 36116753412: job 108013584931 (4-install-port-80-taken) printed the correct apache2 refusal; the scenario failed on a stale literal assertion (`curl -fsSL https://statbus.org/install.sh | bash` vs the saved rerun command that includes the operator's env vars), fixed in the scenario by `ed82f865e`. Job 108013586533 (5-install-orphaned-db-volume-credentials phase a, root `python3 -m http.server 80`) printed the generic `Installation cannot start with the current settings` because the Docker ownership probe failed on a fresh box and the named-owner line was lost; fixed in `08bcd2908` (every owner shape: named service, another program, probe error reaches the terminal verbatim; test TestCheckInstallPortsOwnAndForeign). Both merged in `a3526f832`, first candidate v2026.09.3-rc.05. VM proof pending.

## VM proof, 2026-09-25 (rc.05, run 36130286326, job 108056844900)

4-install-port-80-taken: the first refusal named the owner and remedy verbatim on a real VM: `port 80 is in use by apache2. Free the port with sudo systemctl disable --now apache2. ... Your answers are saved. Then run the same install command again: curl ...` — both rc.03 fixes (08bcd2908, ed82f865e) proven. The scenario then failed at the RERUN for a NEW, unrelated product reason (interrupted-install signer refusal; fixed on fix/rc05-port80-rerun).

<!-- SECTION:DESCRIPTION:END -->

## Release blocker notes

Candidate smoke 0-happy-install run 36063305786 (orchestrator 36063171711) installed successfully but the green-box rerun refused its own proxy port 3014. Docker's `Ports` string compressed 3014-3015, defeating substring matching. Preflight now uses this Compose project's structured per-port `Publishers`, preserving rejection of foreign listeners and other slots; Docker-probe failures report uncertainty rather than blaming another program. Keep In Progress until a candidate VM rerun proves the fix.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: cli/cmd/install_ports_test.go::TestSelectedPortsAndOwners` covers port 80 and a non-80 configured port, reporting the discovered port and owning program before any StatBus service starts.
- [ ] #2 `new: test/install-recovery/scenarios/4-install-port-80-taken.sh` installs Apache, observes zero StatBus service starts, and prints the fixture-specific `sudo systemctl disable --now apache2` recovery command plus the saved-answer rerun command.
- [ ] #3 `new: test/install-recovery/scenarios/4-install-port-80-taken.sh` applies the printed fix, pastes the same rerun command from the home directory, and reaches a ready installation.
<!-- AC:END -->
