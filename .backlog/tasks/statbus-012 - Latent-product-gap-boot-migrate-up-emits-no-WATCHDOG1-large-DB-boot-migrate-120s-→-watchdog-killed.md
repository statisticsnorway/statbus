---
id: STATBUS-012
title: >-
  Latent product gap: boot-migrate-up emits no WATCHDOG=1 (large-DB boot-migrate
  >120s → watchdog-killed)
status: To Do
assignee: []
created_date: '2026-06-07 23:57'
labels:
  - upgrade
  - recovery
  - product
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - ops/statbus-upgrade.service
priority: medium
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Architect surfaced this during the archivebackup-resume diagnosis (it is NOT the cause of that failure — a separate latent product gap, found en route).

cli/internal/upgrade/service.go:1644 boot-migrate-up runs `./sb migrate up` with writer=io.Discard + onAdvance=nil, in the ACTIVE phase, BEFORE the applyPostSwap gated ticker arms (service.go:3734) — so it emits NO WATCHDOG=1 heartbeat. A large-DB boot-migrate exceeding WatchdogSec=120s would be watchdog-killed with no heartbeat. Invisible in tests (test boot-migrate is a fast no-op). The unit comment ops/statbus-upgrade.service:87 assumes boot-migrate is safely active-phase — only true if it finishes <120s.

Relevant for large external/standalone DBs (the upgrade-hardening-for-external-customers arc; rune/Norway). PRODUCT fix: emit WATCHDOG=1 during boot-migrate (an onAdvance heartbeat, or arm a heartbeat ticker before boot-migrate). Flagged for the King's review — recovery code, no autonomous change overnight. Full diagnosis: tmp/architect-archivebackup-resume-diagnosis.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Confirm boot-migrate-up runs active-phase with no WATCHDOG=1 before the gated ticker arms
- [ ] #2 Decide + implement the heartbeat (onAdvance WATCHDOG=1, or a ticker armed before boot-migrate)
- [ ] #3 A boot-migrate >120s no longer gets watchdog-killed (verify, e.g. an injected slow boot-migrate scenario)
<!-- AC:END -->
