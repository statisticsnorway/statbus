---
id: STATBUS-268
title: >-
  install-ukraine: new cloud installation for Ukraine on niue, following the
  established multi-tenant pattern
status: To Do
assignee: []
created_date: '2026-08-27 12:56'
labels:
  - ops
  - cloud
  - installation
dependencies: []
priority: high
type: feature
ordinal: 261000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The King (2026-08-27): multiple countries are waiting eagerly for new installations; Ukraine is first, to be installed on niue following the established cloud installation pattern (doc/CLOUD.md, ops/create-new-statbus-installation.sh — slot code, port offset, subdomain, per-slot Linux user, database, cookie names per the deployment-slots scheme).

Execution notes to settle with the architect at planning:
- Slot code (presumably `ua`) and port offset — offset 2 is recorded as reserved-for-future-use on niue since Norway's migration to rune (doc/CLOUD.md:37); confirm whether it is reusable or a fresh offset is cleaner.
- This is the FIRST new slot since the recent doctrine landings, so it exercises them: the box's channel comes from UPGRADE_ROLE (STATBUS-254 durable mechanism — an ordinary installation is production/stable, declared explicitly); any CI door grants for the new slot are a reviewed commit to ops/niue/sshdoers + a Stage 8 re-run (STATBUS-259 — never a hand-edit of /etc/sshdoers).
- The installation must land on a NAMED release (canonical-commit-naming), and the box then follows its channel.
- Remaining countries: names pending from the King — each gets its own ticket on this pattern.

WHAT IS ACHIEVED: Ukraine's statistical office has a running StatBus on niue, installed entirely through the established pattern with zero hand-managed state, and the path is warm for the countries behind it.
<!-- SECTION:DESCRIPTION:END -->
