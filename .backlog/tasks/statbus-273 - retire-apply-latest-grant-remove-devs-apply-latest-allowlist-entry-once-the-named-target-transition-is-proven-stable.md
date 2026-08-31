---
id: STATBUS-273
title: >-
  retire-apply-latest-grant: remove dev's apply-latest allowlist entry once the
  named-target transition is proven stable
status: Done
assignee:
  - '@operator'
created_date: '2026-08-27 13:23'
updated_date: '2026-08-31 19:48'
labels:
  - ops
  - security
dependencies: []
priority: low
type: chore
ordinal: 266000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Deferred from STATBUS-259's endgame (architect's sequencing rule b): dev's apply-latest grant in ops/niue/sshdoers deliberately COEXISTS with the new named-target apply entry through the transition, so a deploy-to-dev.yaml revert cannot strand the canary with no apply door. Once the named-target path has proven itself over real cuts (rc.10's chain run at minimum, ideally a few), remove the apply-latest entry as its own reviewed commit + Stage 8 re-run. Demo's apply-latest entry is PERMANENT (correct verb for a channel-following box) — do not touch it. Least-privilege payoff: dev's door then permits exactly one verb shape, commit-addressed.
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
COMPLETE, end to end (2026-08-31 evening). Repo: dev's apply-latest line removed from ops/niue/sshdoers at 35fc6b316; demo's entry untouched (permanent, the 248 auto-apply door); the named-target entry's coexistence comment rewritten from a promise of the removal into the record of it. Operator prepared the diff and the Stage 8 procedure (line-numbered, demo-confirmation, commit-addressed recipe); foreman applied, committed, then ran Stage 8 live on niue under the root grant: fetched setup-ubuntu-lts-24.sh at the exact commit, SKIP_STAGES="0 1 2 3 4 5 6 7" (stage 8 is the final stage — verified in source before running), SSHDOERS_HOST defaulted from FQDN to niue. VERIFIED: live /etc/sshdoers sha256 = 70b0a06c7655bfdc180d1198b9073ccaa2faf5c0f157911c99dbe2d656285e98 = the committed file's hash exactly; /etc/sshdoers.sha256 republished matching; statbus_dev's doors are now exactly {upgrade apply <sha>, ci-notify.sh, ci-deploy-status.sh} — one apply verb shape, commit-addressed, the 259 least-privilege payoff realized. Noted, not actioned: the script epilogue's "reboot required" banner (almost certainly pre-existing unattended-upgrades state, not this stage's doing) — reported to the King rather than rebooting a nine-slot host on banner say-so.
<!-- SECTION:FINAL_SUMMARY:END -->
