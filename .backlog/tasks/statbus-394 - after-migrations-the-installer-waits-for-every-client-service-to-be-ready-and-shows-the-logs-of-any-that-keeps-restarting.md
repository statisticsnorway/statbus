---
id: STATBUS-394
title: After database setup, the installer confirms every client service and the advertised site are ready
status: In Progress
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 18:42'
labels:
  - install
dependencies:
  - STATBUS-407
priority: high
type: bug
ordinal: 1
---

## Description

## Implementation note, 2026-09-24

Existing step-8 and final checks bound container-running and API `/ready` waits. A failed wait now records the complete container inventory and recent logs for services that failed to start, rather than only returning a condition. The automatic-update route, advertised HTTP/TLS endpoint proofs, and all disposable-VM scenarios remain pending; none of the five acceptance criteria is claimed complete.

Continuation: a bounded final readiness failure now emits an allowlisted plain restarting-service line for rest, app, worker, or proxy in the operator terminal. Its state and recent logs remain in the install log. Guarded tests exercise each restart loop, and the terminal filter was checked with synthetic input. No VM proof has been run; all five acceptance criteria remain open.

<!-- SECTION:DESCRIPTION:BEGIN -->
After STATBUS-407 reconciles database role passwords, this ticket confirms API, application, worker, automatic-update route, and advertised-site readiness. The selected certificate mode determines whether the final site check uses trusted HTTPS or plain HTTP, and the installer prints success only after that response.

## Evidence, 2026-09-24

The customer's API log establishes authenticator password failure but does not establish how the customer credentials diverged (`/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt:52-58`). Database role creation is in `postgres/init-db.sh:135-141,223` at master `7a9cf707e`. A disposable VM reproduced the surviving-volume and regenerated-settings mechanism (`/Users/jhf/ssb/.jcode/scratch/rest-loop.md:3-16,43-52`), while the normal local replay did not reproduce the loop (`/Users/jhf/ssb/statbus/tmp/local-ville-replay.md:984-987`). Its mismatch was deliberately injected (`/Users/jhf/ssb/statbus/tmp/local-ville-replay.md:914-962`). The customer step-17 timeout followed an unavailable host route (`/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt:114-154`), and current readiness points are `cli/cmd/install.go:2557-2559,2819-2823` at master `7a9cf707e`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: test/install-recovery/scenarios/5-install-api-restart-loop.sh` depends on STATBUS-407, changes credentials only on a disposable database, and observes API, application, and worker ready after reconciliation.
- [ ] #2 `new: test/install-recovery/scenarios/5-install-client-restart-loop-diagnostic.sh` deliberately leaves the API, application, and worker in a restart loop one at a time on a disposable VM, observes the installer fail within its bounded readiness timeout, and verifies the diagnostic names the restarting service and includes that service's own startup error and recent logs. The fixture does not assert how the customer's credentials diverged.
- [ ] #3 `new: cli/cmd/install_readiness_test.go::TestAutomaticUpdateRouteBeforeEnable` holds the selected route unavailable, observes a bounded actionable failure with logs, restores it, and confirms reachability before enablement.
- [ ] #4 `new: test/install-recovery/scenarios/5-install-standalone-https-readiness.sh` selects public or operator-supplied trust, proves a trusted TLS handshake and HTTP response at the advertised address, then observes the success banner afterward.
- [ ] #5 `new: test/install-recovery/scenarios/5-install-private-http-readiness.sh` selects a mode whose advertised endpoint is plain HTTP, proves the HTTP response, and observes no false HTTPS requirement.
<!-- AC:END -->
