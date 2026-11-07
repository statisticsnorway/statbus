---
id: STATBUS-587
title: >-
  cloud.sh wipe works on standalone boxes and confirms with 'wipe <domain>';
  reimport is removed
status: In Progress
assignee: []
created_date: '2026-11-07T10:37:00Z'
updated_date: '2026-11-07T10:37:00Z'
labels:
  - cloud
dependencies: []
priority: high
ordinal: 499204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
A destructive operator command says what it does in its name and in its confirmation, so nobody deletes data by reading a label the friendly way.

### Zoom in
- `./cloud.sh reimport <box> <variant>` wiped the box's database (cmd_standalone_wipe: stop all, docker volume rm, ./sb install) before scheduling the import. The owner read "reimport" as "import again" (2026-11-07, run A on rune).
- `./cloud.sh wipe no` refused ("wipe is only available for cloud targets"), so the badly named reimport was the only way to wipe a standalone box.
- The wipe confirmation asked to type the box code. Norway's code is the English word "no", so typing "no" meant yes.

### Decision (owner, via hibiscus, 2026-11-07)
Remove reimport. `wipe <box>` works on a standalone box too. The confirmation names the action and the domain: `Type 'wipe no.statbus.org' to confirm:`. A fresh load is `wipe no`, then `import no downloads`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ./cloud.sh wipe <standalone box> runs the production-safe standalone wipe (stop, remove the database volume, ./sb install) (cloud-registry-test)
- [x] #2 Every wipe confirmation asks to type 'wipe <domain>'; the bare code (e.g. 'no') or 'wipe no' refuses before any connection (cloud-registry-test)
- [x] #3 reimport is gone from cloud.sh, its usage text and doc/CLOUD.md; ./cloud.sh reimport is an unknown command (cloud-registry-test)
- [x] #4 wipe all still covers only cloud boxes and never reaches a standalone host (cloud-registry-test)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Red tmp/587-red.log, green tmp/587-green.log (test/cloud-registry-test.sh, run in Harness Selftest). Owner confirmation ruling via hibiscus 10:35.
<!-- SECTION:NOTES:END -->
