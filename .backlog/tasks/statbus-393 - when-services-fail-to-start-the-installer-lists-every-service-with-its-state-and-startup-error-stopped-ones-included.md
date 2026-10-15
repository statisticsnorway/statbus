---
id: STATBUS-393
title: >-
  When starting services fails, the installer names every service's state and
  the support file holds every service's logs
status: In Progress
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-10-15 20:08'
labels:
  - release-bug
  - install
dependencies: []
priority: high
type: bug
ordinal: 1
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
When starting services fails, the operator sees in the terminal which of the six StatBus services is not running and why, and the support file holds every service's logs.

### Zoom out
A partial start is the normal shape of an install failure: some containers are healthy, one could not start, and others never got that far. `docker ps` hides stopped and never-started containers, so the operator cannot tell which part failed. The installer therefore reports all six services by plain name and state (running, restarting, exited, stopped, absent, inactive), and puts the full logs where support will look, not in the terminal.

STATBUS-394 owns the later moment: waiting for client services to become ready after migrations. This ticket owns the failure report and the support file.

### Zoom in
- **Incident, Finland 2026-09-24 (v2026.09.2):** step 8 Services failed because Apache held port 80: `statbus-local-proxy` failed with `failed to bind host port for 0.0.0.0:80 ... address already in use`, while `db` was healthy and `rest` had started (`tmp/finland-transcript-actual.txt:67-74`). Later `docker ps` showed only `db` and a restarting `rest`; app, worker and proxy were invisible (`:145-148`).
- **Shipped (v2026.09.3):** `7277ff65a` and `b869c6c4a`. On a services or final-readiness failure the installer prints all six services with plain names, for example `the web server (proxy): restarting` and `the automatic update service (upgrade): inactive` (`cli/cmd/install_services.go`). The support bundle now holds `docker compose ps -a`, 200-line logs for db, proxy, rest, app and worker, and the automatic update service's journal (`cli/internal/upgrade/bundle.go`).
- **Proof:** `TestStartEarlyFailuresPrintSixServiceInventory`, `TestVerifyInstallServing` (`cli/cmd/install_services_test.go`), `TestWriteBundleSections_Composition` (`cli/internal/upgrade/bundle_test.go`), all green 2026-10-15. Fake-stack tests, no real box.
- **Real box:** the Finland trigger no longer reaches this report: `4-install-port-80-taken.sh` shows a port-80 conflict is now refused before services start, naming `sudo systemctl disable --now apache2`. No scenario on a real box produces a partial start and observes the six-service report.
- **Branch:** `fix/services-392-394` is fully merged.

### Closing review
- **Memory:** none needed.
- **Documentation:** `./sb support gather --help` still lists `docker compose ps`; update it to `ps -a` plus per-service logs.
- **Cleanup:** delete the merged branch `fix/services-392-394` once STATBUS-392 and 394 no longer reference it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A failed start or final readiness prints all six services by plain name with running, restarting, exited, stopped, absent or inactive (`TestStartEarlyFailuresPrintSixServiceInventory`, `TestVerifyInstallServing`)
- [x] #2 The support file contains `docker compose ps -a`, per-service logs for db, proxy, rest, app and worker, and the automatic update service journal (`TestWriteBundleSections_Composition`)
- [ ] #3 [Owner] Decide whether a real-box partial start (a service failing for a reason preflight does not catch) is required beyond the fake-stack tests, and record it in Implementation Notes. No: check this and set Done. Yes: add that scenario as a new criterion.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1-2:** green in Go Test (v2026.09.3); re-run green locally on master, 2026-10-15.
- **Superseded criteria:** the 2026-09-24 restyle named two scenarios and a support test that were never written (`5-install-partial-services.sh`, `5-install-api-restart-loop.sh`, `support_test.go`). The tests that did land are cited instead. The restart-loop case belongs to STATBUS-394.
<!-- SECTION:NOTES:END -->
