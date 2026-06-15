---
id: STATBUS-027
title: >-
  midtx-kill-assertion: 3-postswap-mid-tx-kill still RED — advanced past
  stall-detection to an upgrade-row-state assertion failure
status: In Progress
assignee:
  - mechanic
created_date: '2026-06-11 07:48'
updated_date: '2026-06-15 14:14'
labels:
  - install-recovery
  - harness
dependencies: []
priority: medium
ordinal: 27000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Run 27306718138 @ cd2f5d51f: 3-postswap-mid-tx-kill FAIL. The mechanic's tonight fix (new wait_for_midtx_stall_ready polling pg_stat_activity for the parked migration backend, since the inline dispatch path has no migrate subprocess for pgrep, + an || true fence on the masking pipeline) cleared the stall-not-firing layer, but the scenario then failed at a LATER assertion: "rc=1 at assertions.sh:50" reading the upgrade row state (SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1). HARNESS, 0 product. Investigate: did the SIGKILL of the host-side docker-exec PID actually kill the in-container migration backend (docker-exec signal forwarding), and what state did the upgrade row end in vs what the scenario asserts? May need to assert against the actual post-recovery state on the inline path. Does NOT block the RC cut.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
COMMITTED 82c3fd7ff (pushed). Foreman verified: assert_upgrade_row_state was the one SSH-based assertion missing 016's gzip-t INFRA-skip; the fix adds `local _rc=0` + `|| _rc=$?` + skip-on-nonzero (matches assert_db_migration_max_version_unchanged). A genuine wrong-state still fails; only a transport failure skips. HARNESS-only. Bonus: also hardens the new 4-rollback-restore-watchdog scenario, which calls this assertion 3x. GREEN pending the comprehensive matrix run.

VERIFIED COMPLETE (mechanic evidence, foreman accepted). Original red WAS a transport failure, not a state mismatch: run 27306718138's trace is `rc=1 at assertions.sh:50: tr -d ' '` — set -e firing on the SSH/psql PIPELINE ASSIGNMENT (line 50), ~7s after pg_terminate_backend, with the DB mid-recovery (a transient psql-connect blip). A state mismatch would instead fail later at the `if [ "$actual" = "$expected" ]` comparison with a different message. So the INFRA-skip (skip on transport rc≠0) is the correct + complete remedy; a genuine wrong-state still fails at the comparison. 3-postswap-mid-tx-kill expected GREEN on the comprehensive run; no deeper fix needed.
<!-- SECTION:NOTES:END -->
