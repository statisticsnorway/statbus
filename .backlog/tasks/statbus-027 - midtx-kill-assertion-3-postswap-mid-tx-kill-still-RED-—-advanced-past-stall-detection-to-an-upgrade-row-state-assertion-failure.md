---
id: STATBUS-027
title: >-
  trust-flag-on-pending-upgrade: ./sb install --trust-github-user is a silent
  no-op when a scheduled upgrade is pending
status: To Do
assignee:
  - mechanic
created_date: '2026-06-11 07:48'
updated_date: '2026-07-08 21:47'
labels:
  - install-recovery
  - harness
dependencies: []
ordinal: 27000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: the operator's trust flag works on every install path.
> BENEFIT: `./sb install --trust-github-user X` stops being a silent no-op on a box with a pending scheduled upgrade — exactly the situation where an Albania operator needs it; today they hit "no trusted signers configured" with no clue the flag was ignored.
> STAGE: Stage 1.
> COMPLEXITY: mechanic-simple (ruled fix: move the pre-flight before dispatchInstallState) with architect eyes on the dispatch reorder; a small test pins it.
> DEPENDS ON: nothing.

---

Run 27306718138 @ cd2f5d51f: 3-postswap-mid-tx-kill FAIL. The mechanic's tonight fix (new wait_for_midtx_stall_ready polling pg_stat_activity for the parked migration backend, since the inline dispatch path has no migrate subprocess for pgrep, + an || true fence on the masking pipeline) cleared the stall-not-firing layer, but the scenario then failed at a LATER assertion: "rc=1 at assertions.sh:50" reading the upgrade row state (SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1). HARNESS, 0 product. Investigate: did the SIGKILL of the host-side docker-exec PID actually kill the in-container migration backend (docker-exec signal forwarding), and what state did the upgrade row end in vs what the scenario asserts? May need to assert against the actual post-recovery state on the inline path. Does NOT block the RC cut.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
COMMITTED 82c3fd7ff (pushed). Foreman verified: assert_upgrade_row_state was the one SSH-based assertion missing 016's gzip-t INFRA-skip; the fix adds `local _rc=0` + `|| _rc=$?` + skip-on-nonzero (matches assert_db_migration_max_version_unchanged). A genuine wrong-state still fails; only a transport failure skips. HARNESS-only. Bonus: also hardens the new 4-rollback-restore-watchdog scenario, which calls this assertion 3x. GREEN pending the comprehensive matrix run.

VERIFIED COMPLETE (mechanic evidence, foreman accepted). Original red WAS a transport failure, not a state mismatch: run 27306718138's trace is `rc=1 at assertions.sh:50: tr -d ' '` — set -e firing on the SSH/psql PIPELINE ASSIGNMENT (line 50), ~7s after pg_terminate_backend, with the DB mid-recovery (a transient psql-connect blip). A state mismatch would instead fail later at the `if [ "$actual" = "$expected" ]` comparison with a different message. So the INFRA-skip (skip on transport rc≠0) is the correct + complete remedy; a genuine wrong-state still fails at the comparison. 3-postswap-mid-tx-kill expected GREEN on the comprehensive run; no deeper fix needed.

Open Q (secondary): should the scheduled-upgrade inline-dispatch path also honor --trust-github-user? Today it doesn't — the signer must already be in .env.config.

CONFIRMED ROOT + FIX (mechanic+foreman, 2026-06-18). Order in runInstall: dispatchInstallState (install.go:374) handles StateScheduledUpgrade via ExecuteUpgradeInline and returns handled=true BEFORE the --trust-github-user pre-flight (install.go:383-402) ever runs. So `./sb install --trust-github-user X` is a SILENT NO-OP on any box with a pending upgrade → loadTrustedSigners finds none → mandatory signature check fails before migrate → mid-tx park never fires (900s wedge). REAL Albania bug (operator applying a pending upgrade with --trust-github-user hits "no trusted signers configured"). FIX (both): (product) move the --trust-github-user block to BEFORE dispatchInstallState at install.go:374 so the flag works on the scheduled-upgrade path; (harness) stop the scenario's `cp /tmp/env-config .env.config` from clobbering UPGRADE_TRUSTED_SIGNER_jhf (don't overwrite the signer, or re-stamp after). To be folded into the engineer's recovery-path batch. Awaiting King nod.

CLOSED-OBSOLETE (foreman, 2026-06-19): the .env.config-overwrite / dropped-signing-key bug is avoided by design in the STATBUS-071 5d mid-tx arc reshape (register/schedule preserves the signed key; the arc never overwrites .env.config). No separate fix needed.

REVERTED the 2026-06-19 close-as-obsolete (foreman) — that was WRONG. 027 was misclassified: its TITLE is about the harness .env-overwrite, but its BODY carries an UNFIXED REAL PRODUCT BUG (CONFIRMED 2026-06-18): `./sb install --trust-github-user X` is a SILENT NO-OP on a box with a pending scheduled upgrade (dispatchInstallState handles StateScheduledUpgrade + returns handled=true BEFORE the --trust-github-user pre-flight at install.go:383-402). Albania-relevant. FIX (awaiting King nod): move the --trust-github-user block BEFORE dispatchInstallState. The 071-5d arc reshape avoids the TEST's .env-overwrite but does NOT fix this product bug. STAYS To Do (real bug pending). NEEDS A CLARITY REWRITE: split the misleading title from the buried product bug.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-06 16:13
---
RETITLED (2026-07-06, board sweep): the old title described the harness .env-overwrite symptom, which the 071 arc reshape made obsolete; the ticket's real content is the UNFIXED product bug its notes confirmed on 2026-06-18 — the trust flag is silently ignored when dispatchInstallState handles a pending scheduled upgrade before the pre-flight runs. The ruled fix (move the --trust-github-user block before dispatchInstallState) still awaits the King's nod; it is in the buildable-now queue.
---

author: foreman
created: 2026-07-08 21:47
---
PROCEEDING WITHOUT A SEPARATE NOD (2026-07-08, frame doctrine): the 'awaiting King nod' marker predates the King's standing rule that decisions are pre-filtered through production reality. This one dissolves in that frame: an operator's explicit flag is silently ignored on exactly the path an Albania operator needs it (applying a pending upgrade), and there is no argued cost — the flag is a deliberate trust statement either way, and making it apply where it was silently dropped lowers no bar. The set-but-ignored class was ratified twice already (STATBUS-146's refuse-loudly ruling; the general fail-fast doctrine). Fix as ruled on this ticket: move the --trust-github-user pre-flight BEFORE dispatchInstallState so the flag works on the scheduled-upgrade path; a test pins it. Engineer builds; architect reviews the dispatch reorder before commit.
---
<!-- COMMENTS:END -->
