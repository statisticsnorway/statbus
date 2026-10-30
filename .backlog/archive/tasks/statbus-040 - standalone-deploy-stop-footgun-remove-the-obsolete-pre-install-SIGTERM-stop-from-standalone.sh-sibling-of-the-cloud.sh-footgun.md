---
id: STATBUS-040
title: >-
  standalone-deploy-stop-footgun: remove the obsolete pre-install SIGTERM stop
  from standalone.sh (sibling of the cloud.sh footgun)
status: Done
assignee:
  - architect
created_date: '2026-06-12 17:12'
labels:
  - install-recovery
  - upgrade
  - deploy
  - norway
  - footgun
dependencies: []
references:
  - standalone.sh
  - install.sh
  - STATBUS-039
  - STATBUS-037
  - cloud.sh
modified_files:
  - standalone.sh
  - install.sh
priority: high
ordinal: 40000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
THE BUG (King-approved fix, 2026-06-12). cmd_install_one in standalone.sh ran stop_upgrade_service BEFORE the install.sh curl, on both the versioned and channel paths. stop_upgrade_service = `systemctl --user stop statbus-upgrade@statbus.service` = SIGTERM. An in-flight upgrade process catches TERM, cancels its context, and ROLLS BACK (snapshot restore over the live DB). On a wedged old-binary box (rune), the deploy itself would have fired the restore trap BEFORE the STATBUS-039 takeover could run. On a HEALTHY mid-flight upgrade, the old stop interrupted it into a rollback too — harmful in every case it ever fired on a live upgrade.

WHY THE STOP WAS OBSOLETE — both historical rationales verified false post-039:
1. Mutex: pre-039 `./sb install` refused any live-upgrade flag, so deploy scripts stopped the service first. Post-039 (commit 5eacd6305), install REFUSES a genuinely-progressing upgrade (deploy reports failure, operator retries — correct) and TAKES OVER a crash-looping unit (NRestarts ≥ 3) with a SIGKILL-class quiesce — no handler runs, no rollback fires.
2. "text file busy": install.sh places the binary via curl to ~/sb.tmp + mv (install.sh:198-204, :249) — an atomic rename. The running process keeps executing its old inode; ETXTBSY is impossible regardless of service state. The stop was never needed for the binary swap.

THE FIX: stop_upgrade_service deleted from standalone.sh (function + both call sites), replaced by a tombstone NOTE documenting why no stop may ever return there; cmd_install_one's flow comment rewritten; install.sh's stale concurrency comment (:24-29) rewritten to the post-039 contract (refuse-or-takeover; never pre-stop; rename-atomic swap).

VERIFIED EDGES: (a) healthy in-flight upgrade + deploy → install refuses with wait-and-retry (dispatchInstallState LiveUpgrade arm; upgradeUnitCrashLooping is conservative-false on low NRestarts and on any probe failure) — strictly better than the old SIGTERM-interrupt; (b) binary swap under a running service → safe by rename-atomicity.

CONFIRMED SIBLING — NOT fixed here (own verify pass needed): cloud.sh has the same footgun — its own stop_upgrade_service (cloud.sh:90-92, `systemctl --user stop statbus-upgrade@${server}.service`) with THREE call sites (:497, :514, :534) on the multi-tenant niue deploy paths. Same SIGTERM→rollback class on a wedged cloud slot. Follow-up task needed; flagged to foreman/King rather than silently absorbed or deferred.

PURPOSE IN THE 039 ARC: this unblocks `./standalone.sh install no` as the Norway recovery command — the deploy now reaches rc.02's `./sb install`, which takes over rune's crash loop safely (AC#3) and upgrades it to the RC (AC#4).
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Removed the obsolete pre-install SIGTERM stop from standalone.sh: stop_upgrade_service deleted (function + 2 call sites), tombstone NOTE + rewritten flow comments document the post-039 contract; install.sh's stale mutex comment rewritten (refuse-or-takeover, never pre-stop, rename-atomic binary swap). Both edges verified in code: healthy in-flight upgrades now get a clean refusal+retry instead of a SIGTERM-induced rollback; the binary swap never needed the stop (sb.tmp + mv). bash -n green on both scripts. cloud.sh's identical footgun (3 call sites) flagged as a follow-up, not absorbed. Unblocks `./standalone.sh install no` as the rune/Norway recovery command.
<!-- SECTION:FINAL_SUMMARY:END -->
