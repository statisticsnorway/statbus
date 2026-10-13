---
id: STATBUS-494
title: Every apt operation in the prepare script retries and stops at a bound
status: In Progress
assignee: []
created_date: '2026-10-13 12:42'
updated_date: '2026-10-13 12:42'
labels:
  - install
  - hardening
dependencies: []
priority: high
type: bug
ordinal: 420204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUND 2026-10-13 on the Uganda box during Stage 1 of ops/setup-ubuntu-lts.sh. apt fetched git repeatedly and failed twice: first "Error reading from server. Remote end closed connection [IP: 185.125.190.81 80]", then a complete-size file whose checksums did not match (Hash Sum mismatch), and apt gave up with "E: Unable to fetch some archives". The operator then installed the same package by hand and it worked, which is the definition of a transient failure. Two further faults came with it: the script ran etckeeper commands after its own install had failed (etckeeper: command not found, twice), and the stage ended with two crosses while the run continued. Every apt operation now goes through one bounded-retry helper that refreshes the package index between attempts, keeps the apt options that matter on an intervening network, stops after the bound instead of hammering a mirror, and names the likely cause when it gives up.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every apt-get invocation in ops/setup-ubuntu-lts.sh goes through apt_retry or apt_install, and no bare apt-get call remains. Checked by a search of the file.
- [x] #2 A transient failure is retried and succeeds, the package index is refreshed between attempts, and the output says which attempt won. Checked by test/install-recovery/tests/setup-apt-retry-test.sh case 1.
- [x] #3 A persistent failure stops at the bound of three attempts, is recorded as a failed verification so the whole preparation exits non-zero, and names the likely cause. Checked by case 2.
- [x] #4 A working first attempt is not retried and refreshes nothing. Checked by case 3.
- [x] #5 A failed package install no longer lets the caller use a binary that was never installed: Stage 1 skips etckeeper initialization and logs why. Checked by reading the stage, where the etckeeper block sits inside the install-success branch.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-13, implemented and evidenced by the coordinator in one pass (the owner asked for it directly rather than delegated). RED: STATBUS_SETUP_SCRIPT=<HEAD copy> bash test/install-recovery/tests/setup-apt-retry-test.sh -> "FAIL apt_retry is not defined", rc=1. GREEN: the same test against the working tree -> three PASS lines (transient retried to success in 3 attempts with 2 index refreshes; persistent stopped after 3 attempts and named the cause; a working first attempt not retried), rc=0. bash -n on the modified script parses. The test is wired into .github/workflows/harness-selftest.yaml so CI runs it. Deliberately not done: it does not retry forever, and the Stage 1 locale warning is left to its own ticket.
<!-- SECTION:NOTES:END -->
