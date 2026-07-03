---
id: STATBUS-092
title: >-
  recreate-signal-durable: --recreate intent rides a NOTIFY that races the
  trigger's bare NOTIFY — persist it on the upgrade row instead
status: Done
assignee: []
created_date: '2026-06-18 15:40'
updated_date: '2026-07-03 10:59'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-03 10:59
---
DONE — COMMITTED 6e7d1d70b + behaviorally exercised (King D6 GO, 2026-07-03). The --recreate intent is now durable: a recreate boolean on public.upgrade, written at every promote-to-scheduled, read ATOMICALLY at both claim sites (RETURNING), carried to the on-disk flag; the volatile d.pendingRecreate field and the racing ':recreate' NOTIFY protocol are DELETED (clean break; legacy suffix stripped defensively). Proof stack: foreman-reviewed diff; structural test pinning field-gone/payload-not-built/RETURNING-at-both-claims (per the package's documented live-claim convention); EMPIRICAL exercise on dev — `sb upgrade schedule <sha> --recreate` → row shows recreate=true persisted through the real CLI path, no daemon interference, dev restored to exact pre-state and verified clean. Bonus observation: recreate=true on a superseded row is inert (never claimed; every promote re-sets it) — no staleness path. TWO RESIDUALS noted, not blockers: (1) the full end-to-end flag-carry (a real recreate upgrade) = a CANDIDATE recreate-arc under STATBUS-071, not yet committed; (2) UX gap surfaced: NO CLI verb to unschedule/dismiss a scheduled upgrade (the exercise cleanup needed manual restoration) — promote to a task if operator pain confirms.
---
<!-- COMMENTS:END -->
