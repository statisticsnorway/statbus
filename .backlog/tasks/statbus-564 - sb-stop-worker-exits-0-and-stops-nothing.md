---
id: STATBUS-564
title: sb stop worker exits 0 and stops nothing
status: To Do
assignee: []
created_date: '2026-11-04T00:08:00Z'
updated_date: '2026-11-04T00:08:00Z'
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
- [ ] #1 ./sb stop worker stops the worker container and leaves the others running
- [ ] #2 ./sb stop with a name that is neither a profile nor a service fails with a clear message and a non-zero exit
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
North Star: sb stop <name> stops the named service or profile and never exits 0 having stopped nothing. Zoom out: reject unknown names instead of silently matching no compose service; check sb start/restart for the same profile-vs-service gap. Closing review: no memory needed; update the stop/start help text with the accepted names; no cleanup.
<!-- SECTION:NOTES:END -->
