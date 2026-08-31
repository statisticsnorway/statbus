---
id: STATBUS-322
title: >-
  malawi-install: new cloud installation for Malawi at mw.statbus.org (DNS
  already in place)
status: Done
assignee:
  - operator
created_date: '2026-08-31 11:04'
updated_date: '2026-08-31 11:43'
labels:
  - ops
  - cloud
dependencies: []
priority: high
type: task
ordinal: 315000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: Malawi's statistical office gets a production StatBus at mw.statbus.org, born the same way Ukraine and Ghana were — the standard creation path, no bespoke steps. King's directive 2026-08-31: DNS for mw.statbus.org is already in place.

THE PATH, same as Ghana's (which was 'based on Ukraine' and proved the template): ops/create-new-statbus-installation.sh via the fleet tool — `./cloud.sh create mw Malawi v2026.08.0` (verify the exact arg shape against the script before running: code, name, version; it verifies DNS, creates the Linux user, configures SSH access, picks the next free port offset, declares UPGRADE_ROLE=production → stable channel). Born at the current stable v2026.08.0.

LESSONS FROM GHANA'S BIRTH, applied not relearned: (1) the users-gate halts the script by design — resume means the SCRIPT, not a direct install, or the root-side Caddy tail is skipped and the front door stays dark; (2) NO placeholder admin users, ever — the operator waits at the users-gate and the King supplies .users.yml content through an unpersisted channel (admin details never touch the board, git, or any artifact — standing privacy rule); if a bootstrap user is unavoidable it is neutralized immediately and deleted through the 309 door once born (v2026.08.0 has the door, so this time deletion is available from day one); (3) add statbus_mw to cloud.sh's SERVERS in the same sitting (the roster gains every new slot the day it is created — bf0016503's rule, learned from ua/gh being invisible).

VERIFY AT BIRTH: front door serves at mw.statbus.org, upgrade service running with channel=stable derived from role, slot visible in ./cloud.sh status, King logs in with his own users.

WHAT IS ACHIEVED: Malawi is live on the stable, on the standard path, visible to the fleet tool, with zero product deviations — the third August-born slot and the cleanest.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Birth defect found and fixed mid-birth (5c012d1eb):** the create path never threaded the trusted signer — cloud.sh's install paths pass --trust-github-user via trust_flag, but create-new-statbus-installation.sh invoked the curl'd bootstrap bare, and every newborn box dies at the install verb's deliberate no-default trusted-signers refusal (observed live at Malawi's users-gate resume). The operator refuted the first proposed fix with the correct mechanism (the signer store is the install verb's own, NOT .env.config, and the curl'd script carries no environment — so persisting the key on the box could never reach it). Patch mirrors cloud.sh's resolution: CLOUD_TRUST_KEY_USER env → box-persisted value → early refusal naming the exact re-run command. Malawi's create re-running with the patched script; Ghana/Ukraine were born before this gate existed in their path or with the flag supplied by hand, which is why the gap survived until now.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
MALAWI IS BORN (2026-08-31): mw.statbus.org live at v2026.08.0, all 16 install steps green, front door serving, upgrade service active with channel=stable derived from UPGRADE_ROLE=production, role/channel form verified (1/0), roster line landed at a6affe3a7. The birth followed the standard path with zero placeholder users — the King edited .users.yml on the box himself at the users-gate, and the resume was THE SCRIPT (Ghana's lesson held). One product defect surfaced and died mid-birth: the create path never threaded the trusted signer (fixed at 5c012d1eb after the operator refuted the first proposed fix with the correct mechanism — the signer store is the install verb's own, and the curl'd bootstrap carries no environment). The fourth August-born slot and the cleanest yet; the next country's create needs no hands beyond DNS, the users-gate, and the roster line. Remaining outside this ticket: the King logs in with his own users when he chooses.
<!-- SECTION:FINAL_SUMMARY:END -->
