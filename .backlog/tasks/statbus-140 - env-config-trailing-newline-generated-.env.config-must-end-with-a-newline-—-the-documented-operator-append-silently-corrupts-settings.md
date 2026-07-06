---
id: STATBUS-140
title: >-
  env-config-trailing-newline: generated .env.config must end with a newline —
  the documented operator append silently corrupts settings
status: In Progress
assignee:
  - mechanic
created_date: '2026-07-06 07:41'
updated_date: '2026-07-06 14:26'
labels:
  - config
  - operator-ux
  - product
  - silent-loss
dependencies: []
references:
  - cli/internal/config/config.go
  - ops/notify-slack.sh
  - doc/DEPLOYMENT.md
  - STATBUS-131
priority: medium
ordinal: 141000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: an operator following our own documentation must never corrupt their configuration. The documented way to enable the upgrade callback (and generally to add keys) is to append a line to .env.config — that must always be safe.

THE BUG (found live, park-oracle run r13, 2026-07-04): the config writer generates .env.config WITHOUT a trailing newline on the last line (observed: file ends with 'ADMINISTRATOR_CONTACT='). Any append — `echo 'KEY=value' >> .env.config`, exactly what ops/notify-slack.sh's header and doc/DEPLOYMENT.md now instruct — glues onto the last line, producing 'ADMINISTRATOR_CONTACT=KEY=value': the appended key never takes effect AND the existing setting is silently corrupted. Observed byte-for-byte on the r13 VM (.env.config line 29).

FIX: one line in the config writer (cli/internal/config/config.go, the .env.config generation path in loadOrGenerateConfig / its file-write) — guarantee the written file ends with '\n'. Add a unit test asserting the generated file's final byte.

NOTE: the park scenario already carries its own defensive tail-c1 newline guard (commit 0cfd9576b) so the VM oracle is independent of this fix — this ticket is purely the product-side guarantee for real operators.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Generated .env.config always ends with a newline (unit test on the final byte)
- [ ] #2 An append of KEY=value to a freshly generated .env.config lands on its own line and survives config generate into .env
<!-- AC:END -->
