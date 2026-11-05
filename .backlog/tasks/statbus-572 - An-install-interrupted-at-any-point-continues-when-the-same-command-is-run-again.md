---
id: STATBUS-572
title: >-
  An install interrupted at any point continues when the same command is run
  again
status: In Progress
assignee: []
created_date: '2026-11-05T11:36:00Z'
updated_date: '2026-11-05T13:55:00Z'
labels:
  - installer
dependencies: []
priority: high
type: bug
ordinal: 491204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
North Star: the install is idempotent. Ctrl-C, a dropped ssh session or a reboot at any moment leaves a box where running the same install command again finishes the install; the operator never needs an outside fix.

### Zoom in
Manual box, rc.09, 2026-11-05: Ctrl-C during [10/19] Images of a first install (no container existed yet). Every rerun printed 'Continuing the upgrade on the new binary after the planned handoff.' and stopped: 'The database connection route is missing: the web server (proxy) container was removed while an upgrade was interrupted', fix 'docker compose up -d proxy'. Cause: the interrupted install's own marker (tmp/upgrade-in-progress.json, holder install, no live process) was adopted as an upgrade recovery lock; crash recovery then required the database route before it reached the code that clears an install marker.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An install marker (holder install, not a restart) with no live process is cleared by the next install run before any upgrade recovery work, without needing a database or containers, and the run says 'The previous install was interrupted; continuing it.' and continues; no upgrade wording and no outside fix are shown
- [ ] #2 LXD scenario 5-install-interrupted-before-services: SIGINT a real first install at Images RUNNING, rerun the same command, it continues to serving web and API
- [ ] #3 [Owner] On the manual box, Ctrl-C during an install then the same command again finishes the install
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- **2026-11-05 fix:** crash recovery settles an install's own marker (holder install, trigger != restart) first: RecoverFromFlag removes it under its own flock, no DB needed, then 'The previous install was interrupted; continuing it.' and the install continues. The upgrade opening line and the 'previous upgrade stopped' state line are not shown for an install marker. TestCrashRecoveryClearsAnInterruptedInstallsMarkerWithoutADatabase red (tmp/interrupted-install-red.log: recovery went to config regeneration/route), green (tmp/interrupted-install-green.log); go test ./... green; terminal filter passes the line. New LXD scenario 5-install-interrupted-before-services (SIGINT at Images RUNNING, rerun, assert continuation and no upgrade wording, serving web/API).

- **2026-11-05 rc.10 box run:** the marker was cleared ('The previous install was interrupted; continuing it.') but the same run then stopped: the re-detect after recovery treated 'database unavailable' (no db container yet, Ctrl-C before Services) as fatal ('the installer could not finish'); a second run continued. Fix: the re-detect applies the first look's rule, a positively identified 'no database' continues to the step table in the same run ('No StatBus database is running yet; continuing with the installation.'). TestInterruptedInstallContinuesInTheSameRunWhenNoDatabaseExists red (tmp/interrupted-same-run-red.log: 're-detect after recovery: ... database unavailable'), green; go test ./... green. The LXD scenario already requires the single rerun to exit 0.

rc.11 LXD gate (run 42030136824): 5-install-interrupted-before-services failed. Cause was the harness, not the product: the first install was launched with & from a non-interactive shell, so SIGINT arrived ignored and bash cannot reset it. docker compose died, sb survived and reported 'A required image could not be downloaded', exited normally and removed its marker, so the rerun had no interrupted install to continue (it still finished). With a real terminal Ctrl-C, sb dies and leaves the marker that this ticket's recovery settles. Fix da14dbcea: perl restores SIGINT's default before exec. Linux prototype tmp/sigint-launch-proto.log: old launch SURVIVED SIGINT, new launch died on SIGINT. Re-proven in the rc.12 gate.
<!-- SECTION:NOTES:END -->
