---
id: STATBUS-029
title: >-
  stage-a-seed-restore-red: 5-install-stage-a-killed-migrate RED (pre-existing)
  — pg_restore rolled back (likely STATBUS-018 root)
status: In Progress
assignee:
  - architect
created_date: '2026-06-11 07:48'
updated_date: '2026-06-15 14:11'
labels:
  - install-recovery
  - harness
dependencies: []
priority: medium
ordinal: 29000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Run 27306718138 @ cd2f5d51f: 5-install-stage-a-killed-migrate FAIL (pre-existing red, not attempted tonight). Log: "✗ psql zombie still present (count=1)" + "Seed restore failed — will run all migrations" + pg_restore reported transaction rolled back (exit status 1). The seed-restore failure likely shares the root with STATBUS-018 (pg_restore --clean fails on sql_saga updatable-view triggers when restoring onto a populated DB → falls back to full migrations). The zombie-still-present assertion is the over-strict-zombie-assertion the architect flagged (D bucket). HARNESS, 0 product. Cross-link STATBUS-018. Does NOT block the RC cut.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ESCALATED to architect (foreman, 2026-06-15) — mechanic's relax-to-diagnostic fix HELD uncommitted. The mechanic's mechanism is right (checkSessionsClean's 5-min gate, install.go:1211, means a FRESH psql INSERT-statistical zombie is never detected → cleanOrphanSessions never triggered → zombie survives). BUT foreman found a GATE/ACTION ASYMMETRY: cleanOrphanSessions Phase 1 (install.go:1345-1355) kills `query ILIKE '%statistical_history%'` UN-AGED — the action WOULD kill the fresh zombie, but the gate (5-min) never triggers it. So either (A) the gate is intentionally conservative (multi-context healthy-migrate protection) → the scenario tests an impossible-by-design case AND the relax-to-diagnostic guts its stated purpose ('Validates Phase 1 cleanup of psql migrate-zombies') → re-design to test a realistic orphan (aged >5min / advisory-lock holder via un-aged Phase 2 / statbus-migrate-sql app); or (B) a real recovery GAP — at install/recovery time there's no concurrent healthy migrate, so the gate should detect the obvious fresh migrate-zombie the action already kills (a lock-holding orphan survives recovery) → fix checkSessionsClean. Architect to adjudicate + propose the minimal correct fix. On the critical path for the comprehensive-green; get it right over fast.
<!-- SECTION:NOTES:END -->
