---
id: STATBUS-430
title: >-
  A state-detection failure that clears on rerun says so, not 'correct the
  settings'
status: In Progress
assignee: []
created_date: '2026-09-29 08:24'
updated_date: '2026-09-30 13:12'
labels:
  - install
dependencies: []
priority: medium
ordinal: 379200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the Ville replay (tmp/ville-replay-v2026.09.3.md D4, 2026-09-29). Attempt 2 on the repaired box failed state detection with 'FATAL: the database system is shutting down' (psql over the db socket). cli/cmd/install.go:547 returns 'the install state could not be determined safely; nothing was changed. Run the same install command again ...', but install.sh's exit-78 fallback (install.sh:859) prints 'Installation cannot start with the current settings. Correct the settings, then run: ...', which is wrong: nothing about the settings was wrong. Also find what restarted the database between attempt 1 (Settings refusal) and attempt 2 (likely the upgrade daemon restarting under the swapped binary and converging the db container while install ran) and whether install and daemon must serialise there.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 install.sh shows the state-detection rerun remedy using trusted command/path values (rather than echoing an untrusted log line), instead of the settings sentence
- [ ] #2 The cause of the database restart between attempts is identified with evidence, and either prevented or documented as expected with the rerun remedy
- [x] #3 A test covers the detection-failure message path
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-09-29: fix on fix/430-detection-message (8dd6a68d6). Review tmp/review-430.md: MERGE WITH CHANGES (A: new allowlist entry is only prefix-anchored, so arbitrary trailing text crosses the log boundary; print the trusted rerun command and a validated bundle path from the shell, and $-anchor the existing port/disk/restart members; B: test should drive the real Go error and add negatives; C: comment wording). AC2's strongly supported explanation is that a 09.2 unit left in a Restart=always loop re-execs the swapped binary, whose boot Pre-flight A/B (config generate + up -d db, no install mutex) can recreate the db container while install runs. The source paths and serialization gap were checked independently, but a correlated daemon/container lifecycle trace proving this was the restart in the original Ville run is still missing. Filed as STATBUS-432. AC2 remains unchecked.

2026-09-30: merged as signed 0ff6a590c after independent Opus MERGE reviews in tmp/review-430-2.md and tmp/review-evidence-and-430-final.md. AC1 and AC3 are validated by the real Go-producer/install.sh-branch tests, raw-psql and suffix-injection negatives, strict support-bundle filename cases including the fallback path, and independent mutations that turn the relevant tests red when reverted. Full `cd cli && go test ./... -count=1` passed on the merged tree (background task 006928s3ck, exit 0, 185.9 seconds), as did `go vet ./...`, `bash -n install.sh`, `shellcheck -S warning install.sh` and `git diff --check`. Logs: tmp/test-go-merged430-20260930.log and tmp/vet-merged430-20260930.log. Disk-space baseline failures are no longer present after the owner's disk repair. No CI or real-guest acceptance result is claimed for this merge yet.
<!-- SECTION:NOTES:END -->
