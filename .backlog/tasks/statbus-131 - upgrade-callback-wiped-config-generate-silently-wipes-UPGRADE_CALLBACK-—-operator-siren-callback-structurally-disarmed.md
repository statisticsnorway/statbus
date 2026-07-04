---
id: STATBUS-131
title: >-
  upgrade-callback-wiped: config generate silently wipes UPGRADE_CALLBACK —
  operator siren/callback structurally disarmed
status: In Progress
assignee:
  - mechanic
created_date: '2026-07-03 21:42'
updated_date: '2026-07-04 12:08'
labels:
  - upgrade
  - operator-ux
  - product
  - silent-loss
dependencies: []
references:
  - cli/internal/config/config.go
  - cli/internal/upgrade/service.go
  - cli/cmd/install.go
  - ops/notify-slack.sh
priority: high
ordinal: 132000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUND during the STATBUS-044 park-scenario build (mechanic's callback-marker injection workaround exposed it); VERIFIED first-hand by the architect (2026-07-03, overnight — for the King's morning review).

THE GAP (same silent-loss class as the doc-025 role GUCs — operator state living in a regenerated artifact instead of the durable home):
- `UPGRADE_CALLBACK` is READ from `.env` (service.go:5876 runCallback; install.go:2198 runInstallCallback) and `ops/notify-slack.sh` documents setting it (`UPGRADE_CALLBACK=./ops/notify-slack.sh`).
- `sb config generate` FULLY OVERWRITES `.env` (config.go:922) from `.env.example` + an ENUMERATED Set list; `UPGRADE_CALLBACK` appears in NEITHER (verified: zero refs in config.go, zero in .env.example), and there is no unknown-key passthrough from `.env.config`.
- config generate runs at EVERY install AND at applyPostSwap step 3.1 of EVERY upgrade — i.e. the callback key is wiped BEFORE the completion/failure/rollback callbacks would fire later in that same upgrade.

CONSEQUENCE: any operator who follows the documented setup loses the callback on the next install/upgrade — silently. URGENT-ADJACENT: STATBUS-046's PARK SIREN (STATBUS_EVENT=parked, the once-only degraded alert that replaces rune's loop-forever) rides runCallback → it is structurally DISARMED on any real box today. Why nobody noticed: production Slack notification rides SLACK_TOKEN, which IS in the enumerated set and survives — a different mechanism.

FIX SHAPE (architect): make UPGRADE_CALLBACK a first-class enumerated `.env.config` → `.env` key — config.go `gen("UPGRADE_CALLBACK", "")` + example.Set carry-through; document the key in the .env.config template; update ops/notify-slack.sh's header to say .env.config (the durable operator-owned home), not .env. Optionally the STATBUS-044 scenario then injects into .env.config instead of the post-kill .env timing workaround.

VERIFICATION: the park scenario's siren assertion is the natural oracle once the key survives config generate; plus a unit-level check that generateEnvContent carries the key.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 UPGRADE_CALLBACK set in .env.config survives sb config generate into .env (enumerated carry-through)
- [ ] #2 ops/notify-slack.sh header + deployment docs name .env.config as the home
- [ ] #3 the 046 park siren fires on a box whose callback was configured only in .env.config (scenario or arc evidence)
<!-- AC:END -->
