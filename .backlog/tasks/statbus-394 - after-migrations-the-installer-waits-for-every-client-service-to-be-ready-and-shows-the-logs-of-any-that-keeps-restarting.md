---
id: STATBUS-394
title: The installer reports success only when every service runs and the API answers
status: Done
assignee: []
created_date: 2026-09-24 16:42
updated_date: '2026-10-28T02:27:00Z'
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
- [x] #5 The final check fetches the advertised site the way a user would, with the chosen name connecting to this box (curl --resolve <domain>:<port>:127.0.0.1, no reliance on DNS or hairpin routing): HTTPS with the certificate verified against the system trust store when HTTPS is configured, plain HTTP otherwise. With plain HTTP or a supplied certificate (TLS_CERT_FILE), a failure stops install non-zero and names what failed: no answer, certificate not trusted, name not covered, or certificate expired. With an automatic (ACME) certificate, install completes and prints 'HTTPS is not working yet: <reason>' in place of a plain success. Go tests cover each outcome. The LXD guest trusts the harness CA so 0-happy-install.sh passes the check with a supplied certificate
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

### Owner decision 2026-10-21: finalize what we control
Plain HTTP and a supplied certificate are ours, so a failed check stops install with the reason. An ACME certificate is issued from outside after install (389: the operator owns reachability), so install completes and says plainly that HTTPS is not working yet, and why. Staging-first Let's Encrypt is STATBUS-523, decided with STATBUS-399.

### AC5 evidence (worker, 2026-10-21, commit d19546722)
- **Implementation:** cli/cmd/install_visit.go adds verifyAdvertisedSite, called from cli/cmd/install.go right after verifyInstallServing, before the completion banner. It probes every origin installVisitOrigins advertises with an http.Client whose DialContext pins <domain>:<port> to 127.0.0.1:<port> (no DNS, no hairpin), ServerName = the domain, system trust store (seam visitSystemRoots for tests), 1-minute budget with 2s retries (Caddy may still be loading the certificate; budget injected in tests).
- **Classification (plain words):** did not answer / certificate not trusted (unknown authority) / does not cover this name / expired or not yet valid / answered with HTTP status <n>.
- **Mode decisions (owner 2026-10-21):** certificate setup read from .env.config TLS_CERT_FILE/TLS_KEY_FILE (they never reach .env) plus CADDY_DEPLOYMENT_MODE from .env. Plain HTTP and supplied certificate: failure stops install non-zero via the same return path as verifyInstallServing. ACME (standalone without TLS_CERT_FILE, private): install completes and prints 'HTTPS is not working yet: <origin> <reason>'.
- **Development mode choice:** development.caddyfile.tmpl serves HTTPS with 'tls internal' (Caddy internal CA), which is in no system trust store, so verifying trust would always fail without naming a real defect — not coherent to treat as ours. Development checks the plain HTTP origin strictly (fatal) and the HTTPS origin for reachability/status without trust verification (fatal), which still catches Caddy not serving.
- **Go tests:** TestProbeVisitClassifies_STATBUS394 (success with Host-header proof, untrusted, wrong name, expired, no answer, HTTP 500, plain HTTP, dev-mode no-verify), TestVisitChecksFollowCertificateSetup_STATBUS394 (per-mode planning), TestVerifyAdvertisedSite_STATBUS394 (success line, supplied-cert fatal, ACME warning line). Red: tmp/394-red.log (compile-fail before implementation). Green: tmp/394-green.log (all pass, -v).
- **Harness:** vm-bootstrap.sh provision_harness_certificate and lxd-backend.sh lxd_certificates now install harness-certs/ca.crt into the guest system trust (/usr/local/share/ca-certificates/statbus-harness-ca.crt + update-ca-certificates), so 0-happy-install passes the new check with the supplied harness cert. 4-install-standalone-no-public-dns now asserts install completes with 'Installation complete!' AND the 'HTTPS is not working yet: https://statbus-no-public-dns.invalid ...' line. 5-install-cert-repair comment updated. README coverage table row added.
- **Gates:** gofmt clean; golangci-lint run ./... 0 issues; go test ./cmd/ ./internal/... all ok; ./dev.sh test-harness PASS; bash -n on edited shell files OK.
- Not checked: AC5 checkbox and Done — owner reviews first; real-box proof comes with the next candidate's fleet.

- **CI for d19546722 (2026-10-21):** all 7 runs completed success — Go Test (incl. golangci-lint gate), Fast Tests, app build & lint, Push on master, Images, Harness Selftest, Notify cloud services.

### Review 2026-10-21 (rabbit)
- d19546722 read. `verifyAdvertisedSite` (`cli/cmd/install_visit.go`) runs after `verifyInstallServing` and before 'Installation complete!'. It fetches each `installVisitOrigins` origin with the chosen name dialled to 127.0.0.1. That is reachable in every mode: standalone binds 0.0.0.0:80/443, development and private bind 127.0.0.1, and on niue the host-level Caddy on :443 routes private slots by SNI.
- How each setup is treated:
  - Plain HTTP: fatal.
  - Supplied certificate: verified, fatal.
  - Automatic (ACME): verified, prints `HTTPS is not working yet: <origin> <reason>` and completes.
  - Development HTTPS: Caddy's internal CA, so no trust check, but it must answer.
- Tests: `TestProbeVisitClassifies_STATBUS394`, `TestVisitChecksFollowCertificateSetup_STATBUS394` and `TestVerifyAdvertisedSite_STATBUS394`. Red `tmp/394-red.log`, green `tmp/394-green.log`. CI for d19546722: 7/7 success.
- Remaining for AC5: the next candidate's fleet. `0-happy-install.sh` passes with the guest trusting the harness CA, and `4-install-standalone-no-public-dns.sh` prints the warning line.

AC5 real candidate evidence: rc.05 LXD Fork Fleet run 40618330397 passed all 24 scenarios. 0-happy-install had already passed with the supplied certificate in rc.03 Test Smoke job 122549573505. On rc.05, 4-install-standalone-no-public-dns PASS (185s) shows the operator-visible line 'HTTPS is not working yet: https://statbus-no-public-dns.invalid did not answer' and completes installation. rc.04 exposed that the terminal filter hid this warning; 00301e024 fixed it with red/green tests tmp/394-terminal-warning-red.log and tmp/394-terminal-warning-green.log. Full CLI tests and ./dev.sh test-harness are green.
<!-- SECTION:NOTES:END -->
