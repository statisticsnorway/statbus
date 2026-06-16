---
id: STATBUS-062
title: >-
  rc03-finalize: revert defer-checkout arc + cut a clean config-drift-only RC (3
  King decisions)
status: To Do
assignee: []
created_date: '2026-06-16 08:04'
labels:
  - upgrade
  - release
  - rc.03
dependencies: []
priority: high
ordinal: 62000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
THE IMMEDIATE NEXT ACTION after the overnight. Foreman drives once the King rules.

## State
Config-drift upgrade-crash wedge (the King's charge) is SOLVED + validated GREEN on real VMs (0-happy run 27582053054 on the config-drift-only commit 658c34ebd; 27582686118 full stack). rc.03 was cut (tag v2026.06.0-rc.03 on d0992498a) BUT it carries the defer-checkout arc, which testing showed has real PreSwap recovery bugs (not the charge).

## RECOMMENDATION (foreman + architect, source-verified): REVERT → ship clean config-drift RC
- KEEP (the charge, validated green): 7cc6c1b48 (unconditional config-regen) + 09ac1f7e4 (image-extract procurement).
- REVERT from the shippable RC: 2f52f3b7f (defer-checkout) + bb4848dd4 (its guard). They ship a real PreSwap schema/git-mismatch bug (recovery-boot checkout before boot-migrate advances schema→target but empty-backup rollback can't undo) + the pre-existing recoveryRollback prev:=d.version (service.go:2193) tree-restore-to-target.
- f29e03a60 (install.sh edge image-extract): likely INDEPENDENT/keepable — confirm with King.
- Clean state ≈ commit 658c34ebd (already 0-happy green → no re-proving of the charge needed).
- The defer-checkout / preswap-window closure + recovery fixes are REDONE PROPERLY in STATBUS-061 (rc.04).

## 3 KING DECISIONS (pending — get these first)
1. Approve REVERT + cut clean config-drift RC (one word from King: "revert + cut clean").
2. Raise the Hetzner project quota (servers + primary IPs) → unblocks the full comprehensive suite (STATBUS-025; max-parallel:8 > quota, stopgap :3 committed 9b7588596).
3. STATBUS-057 image-cleanup GC fix — green-light (still held).

## MECHANIC (on "revert + cut clean")
git revert 2f52f3b7f + bb4848dd4 (keep f29e03a60 unless King says otherwise) → go build/vet/test → foreman reviews → push origin <sha>:master → cut clean annotated RC tag (next number) on that commit → re-confirm 0-happy (operator, 1 VM); full comprehensive once the quota is raised.

## Acceptance
- [ ] King ruled on revert / quota / 057
- [ ] Clean config-drift-only RC cut + 0-happy green on it
- [ ] defer-checkout/preswap-recovery work tracked in STATBUS-061 (rc.04)
<!-- SECTION:DESCRIPTION:END -->
