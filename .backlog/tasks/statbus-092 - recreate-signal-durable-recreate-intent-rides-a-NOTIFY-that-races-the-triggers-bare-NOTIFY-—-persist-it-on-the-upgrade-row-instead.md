---
id: STATBUS-092
title: >-
  recreate-signal-durable: --recreate intent rides a NOTIFY that races the
  trigger's bare NOTIFY — persist it on the upgrade row instead
status: To Do
assignee: []
created_date: '2026-06-18 15:40'
labels:
  - upgrade
  - phase-2-followon
  - post-rc.04
dependencies: []
priority: low
ordinal: 92000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FLAGGED by the engineer during STATBUS-086 (P6, not in 086 scope). RunSchedule's explicit `NOTIFY upgrade_apply ':recreate'` races the public.upgrade trigger's bare `NOTIFY upgrade_apply`. If executeScheduled claims the row between the two NOTIFYs, the recreate intent can be LOST → a --recreate upgrade silently runs as a normal (non-recreate) upgrade.

IMPACT: dev/demo-only (--recreate is not used on production upgrades); tiny window (both NOTIFYs fire within ms; executeScheduled is poll-driven). Low severity, but a real correctness gap.

FIX (no trivial version): persist the recreate intent DURABLY on the public.upgrade row — a `recreate boolean` column set at schedule time, read by executeScheduled — replacing the racy out-of-band ':recreate' NOTIFY payload. This is a MIGRATION (post-rc.04 migration discipline applies — new forward migration, doc/db + types regen). Follow-on; not blocking 086 or the framework.
<!-- SECTION:DESCRIPTION:END -->
