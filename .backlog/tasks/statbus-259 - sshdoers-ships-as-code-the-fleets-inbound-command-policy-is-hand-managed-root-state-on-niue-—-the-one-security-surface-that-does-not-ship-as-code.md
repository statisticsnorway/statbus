---
id: STATBUS-259
title: >-
  sshdoers-ships-as-code: the fleet's inbound-command policy is hand-managed
  root state on niue — the one security surface that does not ship as code
status: To Do
assignee: []
created_date: '2026-08-19 20:06'
labels:
  - ops
  - security
dependencies: []
priority: medium
type: chore
ordinal: 252000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/etc/sshdoers on niue — the byte-pinned allowlist every inbound CI ssh command is checked against — is root-owned, hand-edited host state. The repo carries a copy (ops/niue/sshdoers, whose own header says "Managed by hand"), and nothing syncs or verifies repo↔host: the live policy can drift from the reviewed copy silently, in either direction.

The allowlist SHAPE is correct (least privilege on an inbound credential door). What violates doctrine is the management: every other fix reaches a box through code + the box's own install; the access policy alone reaches it through a person editing a root file over SSH — the exact pattern the fleet-channel correction (STATBUS-254) just removed from configuration.

Surfaced during the King's 2026-08-19 pushback on STATBUS-258 ("an allowlist seems unprincipled"); the architect ruled the diagnosis is precisely this, and that it deserves its own ticket whichever shape 258 takes. Sequencing note: 253/Wave D shrinks this file (deploy entries die with the deploy key); the durable mechanism should land on whatever remains (the notify entrypoints, the pg_regress runner, and any 258 observation door).

WHAT IS ACHIEVED: the live inbound-command policy is provably the reviewed one — drift either fails loudly or is impossible, and the last hand-managed security surface joins the ships-as-code doctrine.
<!-- SECTION:DESCRIPTION:END -->
