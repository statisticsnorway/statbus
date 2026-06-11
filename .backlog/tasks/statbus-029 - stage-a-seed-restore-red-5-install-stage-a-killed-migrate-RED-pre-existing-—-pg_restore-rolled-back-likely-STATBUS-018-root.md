---
id: STATBUS-029
title: >-
  stage-a-seed-restore-red: 5-install-stage-a-killed-migrate RED (pre-existing)
  — pg_restore rolled back (likely STATBUS-018 root)
status: To Do
assignee: []
created_date: '2026-06-11 07:48'
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
