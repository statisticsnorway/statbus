---
id: STATBUS-394
title: The installer reports success only when every service runs and the API answers
status: In Progress
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-10-20 21:22'
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
The installer prints "Installation complete!" only when StatBus actually serves: every service running and the API answering, and when a client service will not come up, the operator is told which one and why.

### Zoom out
Containers that "started" are not a working site. A client service (API, web app, worker) can start and then crash-loop, for example on a password the database does not accept, and a step table that ends all green over that is a lie. So the installer ends with a bounded readiness gate: wait a fixed budget for every service to run and the API to answer, and on timeout name the failing service in plain words, with its own startup error and recent logs kept in the install log.

What makes a client crash-loop is a separate concern: role-password drift is STATBUS-407, the daemon's database route is STATBUS-390. STATBUS-393 owns the six-service failure report and the support file.

### Zoom in
- **Incident, Finland 2026-09-24 (v2026.09.2):** after Migrations, `statbus-local-rest` was `Restarting (1)` while `db` was healthy, and the installer gave no focused diagnosis (`tmp/finland-transcript-actual.txt:144-148`). In the second session the automatic update service sat in `activating` retrying `127.0.0.1:5431` (`tmp/finland-transcript-2-actual.txt:131-154`). The original gap: `cli/internal/compose/compose.go` treated restarting as not-running.
- **Shipped (v2026.09.3):** `f3889e5e8` makes step 8 start every service and adds the final gate `verifyInstallServing` (`cli/cmd/install.go`, before `Installation complete!`), which requires all services running and `http://$REST_ADMIN_BIND_ADDRESS/ready` = 200. `da7e8acfe` names restarting clients (`the API service (rest) keeps restarting`) and keeps their own logs.
- **Proof:** `TestVerifyInstallServing`, `TestRestartingClientsReportOwnLogsAfterBoundedReadiness` (`cli/cmd/install_services_test.go`), green 2026-10-15. On real boxes, `0-happy-install.sh` asserts CA-verified HTTPS on `https://<domain>/rest/` after install, and `5-install-orphaned-db-volume-credentials.sh` (STATBUS-407) shows the rest crash-loop cause fixed and `/ready 200`.
- **Next (AC5, owner 2026-10-20):** the gate also fetches the advertised site the way a user would: the chosen name, connecting to this box, HTTPS with the certificate verified when HTTPS is configured, plain HTTP otherwise, naming what failed. Worker functional readiness beyond running stays out of scope. Testing a certificate before committing to it is STATBUS-523.

### Closing review
- **Memory:** none needed.
- **Documentation:** none needed.
- **Cleanup:** delete the merged branch `fix/services-392-394` once STATBUS-392 no longer references it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `Installation complete!` is printed only after every service is running and the API admin `/ready` returns 200 within a bounded budget (`TestVerifyInstallServing`)
- [x] #2 A client that keeps restarting past the budget is named in plain words in the terminal, with its own startup error and recent logs in the install log (`TestRestartingClientsReportOwnLogsAfterBoundedReadiness`)
- [x] #3 On a real standalone box, the advertised site answers CA-verified HTTPS after install (`0-happy-install.sh`, `assert_harness_https_passes`)
- [x] #4 [Owner] Decide whether the final readiness gate must also probe the advertised `https://<domain>` before printing success, and record it in Implementation Notes. No: check this and set Done. Yes: add that probe as a new criterion.
- [ ] #5 The final check fetches the advertised site the way a user would, with the name the operator chose, connecting to this box (curl --resolve <domain>:443:127.0.0.1, no reliance on DNS or hairpin routing): over HTTPS with the certificate verified against the system trust store when HTTPS is configured, over HTTP otherwise. 'Installation complete!' is printed only when it answers. Otherwise the terminal names what failed (certificate not issued, certificate not trusted, name not covered, no answer) and install exits non-zero
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1-2:** green in Go Test (v2026.09.3); re-run green locally on master, 2026-10-15.
- **AC3:** smoke `0-happy-install` green on the rc ladder (recorded in the 2026-09-29 audit, `ea170989e`).
- **Superseded criteria:** the 2026-09-24 restyle grew this ticket to five unwritten scenarios. Credential reconciliation went back to STATBUS-407 (its own scenario passes), the private plain-HTTP mode criterion was dropped as obsolete under STATBUS-418's standalone-only harness, and the daemon route check is STATBUS-390's `checkUpgradeDatabaseRoute`. The 394 -> 407 dependency was removed: 407 fixes a cause, not a precondition.

### Owner decision 2026-10-20: yes, probe the advertised site
Install says the site is installed, so install checks that a user can reach it. If HTTPS is set up, verify it. If not, check plain HTTP. Print any issue found. Testing Let's Encrypt before committing to it, and verifying a supplied certificate up front, are a separate ticket (STATBUS-523).

### Owner 2026-10-20: AC5 scope
AC5 checks whatever this install set up and prints any issue it finds. HTTP-first and the certificate strategy belong to STATBUS-399 and STATBUS-523, not here.
<!-- SECTION:NOTES:END -->
