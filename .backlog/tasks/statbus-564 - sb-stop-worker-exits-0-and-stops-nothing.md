---
id: STATBUS-564
title: sb stop worker exits 0 and stops nothing
status: Done
assignee: []
created_date: '2026-11-04T00:08:00Z'
updated_date: '2026-11-05T13:54:00Z'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 487204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
./sb stop <name> passes <name> to compose.Stop (cli/internal/compose/compose.go:182), which runs 'docker compose --profile <name> down --remove-orphans'. 'worker' (also db, rest) is a service, not a profile, so compose matches no service, stops nothing and exits 0. The help says 'Profiles: all, all_except_app, app', but nothing rejects a service name. Found 2026-11-04 when the local worker had to be stopped during a database OOM loop; docker compose stop worker worked. The older dockerComposeStop in cli/cmd/db.go:1242 already handles db/worker/rest/app as services.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ./sb stop worker stops the worker container and leaves the others running
- [x] #2 ./sb stop with a name that is neither a profile nor a service fails with a clear message and a non-zero exit
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
North Star: sb stop <name> stops the named service or profile and never exits 0 having stopped nothing. Zoom out: reject unknown names instead of silently matching no compose service; check sb start/restart for the same profile-vs-service gap. Closing review: no memory needed; update the stop/start help text with the accepted names; no cleanup.

Fixed in 9086602cf. Shared resolver compose.ResolveTarget (cli/internal/compose/target.go) defines profiles all, all_except_app, app and services db, worker, rest, app, proxy; start, stop and restart all use it and refuse unknown names before any docker call. stop/start/restart help now list both sets. start previously ran 'docker compose --profile <name> up' for every name (a service matched nothing); restart had its own profile-only switch and built '--profile <name> down'. Red run tmp/564-red.log (5 failing tests), green run tmp/564-green.log; go vet ./... and go test ./... green in tmp/564-vet.log and tmp/564-go-test.log. Tests: TestStopServiceStopsOnlyThatService, TestStopProfileKeepsDownBehaviour, TestStopUnknownTargetRefusesBeforeDocker, TestStartServiceStartsOnlyThatService, TestStartUnknownTargetRefusesBeforeDocker, TestRestartServiceUsesServiceArgs, TestRestartUnknownTargetRefusesBeforeAnyWork, TestServiceCommandsDocumentAcceptedTargets.

Reviewed by rabbit 2026-11-05. Commit 9086602cf: Go Test, Fast Tests, Images, app build all success. Live on statbus-test slot: ./sb stop worker stopped only statbus-test-worker (app, db, proxy, rest kept running); ./sb start worker started it again (tmp/564-live-check.log). ./sb stop nonsense: 'Error: unknown target "nonsense": profiles all, all_except_app, app; services db, worker, rest, app, proxy', exit 1. Ships in rc.12.
<!-- SECTION:NOTES:END -->
