---
id: STATBUS-041
title: >-
  cloud-deploy-stop: Remove obsolete pre-install SIGTERM stop from cloud.sh
  (sibling to STATBUS-040)
status: Done
assignee:
  - architect
created_date: '2026-06-12 21:34'
updated_date: '2026-06-12 21:36'
labels:
  - deploy
  - upgrade
  - footgun
dependencies: []
modified_files:
  - cloud.sh
priority: high
ordinal: 41000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
cloud.sh carries the IDENTICAL deploy-stop footgun that STATBUS-040 removed from standalone.sh — on the niue multi-tenant deploy paths instead of the standalone box.

## The bug (verified)
- `stop_upgrade_service()` defined at `cloud.sh:90` runs `ssh_server ... "systemctl --user stop statbus-upgrade@${server}.service"` = SIGTERM.
- Called BEFORE the install on three deploy paths: `cloud.sh:497`, `:514`, `:534`.
- An in-flight upgrade catches SIGTERM → cancels its context → ROLLS BACK → snapshot restore over the live DB. On a wedged cloud slot the deploy ITSELF fires the restore trap before STATBUS-039's takeover (commit 5eacd6305) can run. Same class as the rune trap, on niue slots.

## The fix (mirror STATBUS-040 / commit f5b697928)
1. Delete `stop_upgrade_service()` (def at :90) and all three call sites (:497/:514/:534).
2. Replace with a tombstone NOTE explaining why no stop may return (mirror the comment at `standalone.sh:140`).
3. Rewrite the justifying comment at `cloud.sh:86` ("...replaced without 'text file busy'. Idempotent — systemctl stop on a...") — that rationale is false: install.sh places ./sb via curl→sb.tmp + atomic mv, so the running process keeps its inode; no ETXTBSY.
4. Update the flow comment at `cloud.sh:365` ("stop_upgrade_service → install → ensure_service_started") to the post-039 contract.

## Edge to confirm (same as 040, in code not assumed)
A genuinely-HEALTHY in-flight upgrade (flag held, NOT crash-looping) must still make `./sb install` REFUSE with wait-and-retry — 039's takeover only fires for a crash-looping unit (NRestarts >= 3) + StateLiveUpgrade. Removing the cloud.sh stop → a healthy in-flight upgrade → install refuses → deploy reports failed, operator retries (strictly better than the old SIGTERM-into-rollback of a healthy upgrade).

## Freeze-safety
cloud.sh is local deploy tooling — not in rc.02, not on rune, not in the VM battery. Committing is freeze-safe (moves HEAD only). The rune recovery (standalone) is unaffected.

## Precedent
STATBUS-040 (f5b697928): the standalone.sh version. install.sh:24-34 already documents the post-039 "callers must NOT stop the service first" contract — verified correct.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 stop_upgrade_service def + all 3 call sites (cloud.sh:90/497/514/534) removed; tombstone NOTE added mirroring standalone.sh:140
- [x] #2 Stale rationale comments at cloud.sh:86 and :365 rewritten to the post-039 contract (no false 'text file busy' / no pre-stop)
- [x] #3 Healthy-in-flight-upgrade edge confirmed in code: install REFUSES (not killed); takeover only on crash-loop NRestarts>=3
- [x] #4 bash -n cloud.sh passes; committed + pushed (freeze-safe), reported to foreman
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Committed e99c283a6 (pushed). stop_upgrade_service deleted from cloud.sh — definition (:90) and all three call sites (:497 build-from-source, :514 pinned-version, :534 channel) — replaced by a tombstone NOTE mirroring standalone.sh's, naming both false rationales: (1) mutex — post-039 `./sb install` refuses a genuinely-progressing upgrade (deploy reports failure, operator retries) and takes over a crash-looping unit (NRestarts ≥ 3) with a SIGKILL-class quiesce; (2) "text file busy" — every binary-replacement path is an atomic rename (curl→sb.tmp + mv on the install.sh path; `mv sb-linux-amd64 sb` on the build-from-source path — a nuance beyond the plan: that site's own comment claimed ETXTBSY "on mv", which is false; rename(2) swaps the directory entry while the running process keeps its old inode; ETXTBSY is write-in-place only). Flow comment (:365) and all three per-site rationale comments rewritten to the post-039 contract; the artifact-gate comments' "before stopping" wording fixed to "before touching the server". Healthy-in-flight edge confirmed in code (same dispatcher as STATBUS-040's verification): dispatchInstallState's LiveUpgrade arm refuses with wait-and-retry; upgradeUnitCrashLooping is conservative-false on NRestarts < 3 and on any probe failure, so takeover fires only on a genuine crash loop. bash -n green. Freeze-safe (local deploy tooling; rune pins to the rc.02 tag). The deploy-stop footgun class is now closed across BOTH deploy scripts (standalone.sh in STATBUS-040/f5b697928, cloud.sh here).
<!-- SECTION:FINAL_SUMMARY:END -->
