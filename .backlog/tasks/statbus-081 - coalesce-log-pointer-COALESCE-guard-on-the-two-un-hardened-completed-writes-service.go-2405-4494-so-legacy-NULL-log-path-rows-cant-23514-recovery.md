---
id: STATBUS-081
title: >-
  coalesce-log-pointer: COALESCE guard on the two un-hardened completed-writes
  (service.go:2405/:4494) so legacy NULL-log-path rows can't 23514 recovery
status: To Do
assignee: []
created_date: '2026-06-17 21:51'
labels:
  - upgrade
  - recovery
  - hardening
dependencies: []
references:
  - 'cli/internal/upgrade/service.go:2405'
  - 'cli/internal/upgrade/service.go:4494'
  - 'cli/internal/upgrade/service.go:4716'
  - 'cli/internal/upgrade/service.go:3573'
priority: medium
ordinal: 81000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHAT: Two of the three "state='completed'" UPDATEs in the upgrade recovery code (cli/internal/upgrade/service.go:2405 and :4494) set state='completed' WITHOUT a log_relative_file_path guard. Only the self-heal write (:4716) was hardened by STATBUS-067 with `COALESCE(log_relative_file_path, $fallback)`. Add the same COALESCE guard to :2405 and :4494.

WHY: chk_upgrade_state_attributes requires log_relative_file_path IS NOT NULL for state='completed'. New upgrade rows are reliably START-stamped at scheduled→in_progress (service.go:3573, enforced by the LOG_POINTER_STAMPED invariant), so real NEW upgrades never hit :2405/:4494 with a NULL log path. BUT a genuine LEGACY row (from a DB that predates the start-stamping migration) reaching one of these completed-writes would violate the constraint (SQLSTATE 23514) and fail recovery — a real defense-in-depth gap. Same class STATBUS-067 already guarded at :4716; the two parallel writes were missed.

STATUS / NON-GATING: NOT required for the rc.04 cut. Surfaced during the rc.04 install-recovery triage (run 27715901866) where harness-FABRICATED rows (fabricate_scheduled_upgrade_row sets log_relative_file_path=NULL, data-helpers.sh:315) hit :4494 → 23514. That harness symptom is fixed separately (fabricate stamps a non-NULL path, mirroring real start-stamping). This task is the PRODUCT-side consistency hardening for real legacy rows. Architect-identified during the STATBUS-075 triage; verified the from_commit_sha removal (1083c62b0) did NOT introduce it — :2405/:4494 are the pre-existing shape.

FIX SHAPE: add `COALESCE(log_relative_file_path, $fallback)` (a derived basename, same pattern as :4716/STATBUS-067) to the completed-write UPDATEs at service.go:2405 and :4494.
<!-- SECTION:DESCRIPTION:END -->
