---
id: STATBUS-404
title: Running the install command again changes only what an answer changed
status: In Progress
assignee: []
created_date: '2026-09-24 15:35'
updated_date: '2026-10-15 20:08'
labels:
  - release-bug
  - install
  - idempotency
dependencies: []
priority: high
type: bug
ordinal: 357000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
Running the install command again on a ready box changes nothing that does not need changing: an unchanged box stays exactly as it is, and a changed answer touches only what depends on it.

### Zoom out
The one install command is also the repair and reconfigure command, so operators run it often and should be able to run it without fear. That works only if every step is convergent: it checks whether its result is already in place, reports OK and does no work when it is, and acts only on a real difference. A rerun that pulls images, regenerates settings or restarts services on a healthy box costs downtime and hides which change actually mattered.

For a changed setting, each generated setting declares which services read it (its restart class). A changed answer then restarts exactly those services and nothing else. A setting with a wrong declaration either restarts too much or, worse, leaves a service running with the old value.

### Zoom in
- **Incident, Finland 2026-09-24 (v2026.09.2):** reruns pulled every image again (`tmp/finland-transcript-2-actual.txt:31-48,83-100`). The image check read a `Container` field while Compose's JSON uses `ContainerName`, so present images looked absent.
- **Shipped:** `8d8f48704`, `224c99c5d` (v2026.09.3) make unchanged reruns quiet. Image detection reads `ContainerName` (`cli/cmd/install.go`, `composeServicesHaveImages`). `e6fc3f739` fixed the port preflight refusing StatBus's own port ranges on rerun (rc.01 smoke run `36063305786`). Restart classes are declared per key in `cli/internal/config/config.go` (`classes.declare`), and `TestGenerateEnvContent_EveryKeyHasARestartClass` keeps every generated key declared.
- **Proof:** `0-happy-install.sh` reruns the install command on a green box and requires every step OK exactly once, no RUNNING/DONE, and no image pull (smoke `36505292818` PASS). `TestComposeServicesHaveImagesRequiresEachNamedService` (`cli/cmd/statbus_349_test.go`) covers `ContainerName`. `TestRestartClassesForKeys_*` (`cli/cmd/install_apply_config_changes_logic_test.go`) covers key-to-service mapping.
- **Defect found 2026-10-15:** the country display name `DEPLOYMENT_SLOT_NAME` is declared with no restart class ("no verified consumer"), but `docker-compose.app.yml` passes it to the app as `PUBLIC_DEPLOYMENT_SLOT_NAME`, which `app/src/app/layout.tsx` renders. A rerun that changes only the display name therefore restarts nothing, and the app keeps showing the old name until something else restarts it. Declared that way since `9fead5e3c` (STATBUS-332).

### Closing review
- **Memory:** none needed.
- **Documentation:** none needed.
- **Cleanup:** merged branch `fix/port-preflight-own-ports` deleted 2026-10-15.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A second run on a ready unchanged box reports every step OK, none RUNNING or DONE, and pulls no image (`0-happy-install.sh` green-box rerun)
- [x] #2 Image detection recognises present images from Compose JSON `ContainerName` (`TestComposeServicesHaveImagesRequiresEachNamedService`)
- [ ] #3 Changing only the display name in the installer restarts the app and no other service, and the app then shows the new name (a rerun with only `DEPLOYMENT_SLOT_NAME` changed)
- [ ] #4 [Owner] Decide whether AC3 is fixed in this ticket or split into its own bug ticket, and record it in Implementation Notes. Here: AC3 stays. Split: file the bug, link it, remove AC3, then set Done.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1:** smoke `0-happy-install` PASS `36505292818` (v2026.09.3), and on the rc ladder since.
- **AC2:** green locally on master, 2026-10-15.
- **AC3:** unmet; defect identified from source on 2026-10-15, not yet reproduced on a box.
- **Superseded criteria:** the restyle asked for captured Compose v2 and v5 JSON fixtures and a `0-rerun-display-name-change.sh` scenario that were never written.
<!-- SECTION:NOTES:END -->
