---
id: STATBUS-140
title: >-
  env-config-trailing-newline: generated .env.config must end with a newline —
  the documented operator append silently corrupts settings
status: Done
assignee:
  - mechanic
created_date: '2026-07-06 07:41'
updated_date: '2026-07-06 14:41'
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
- [x] #1 Generated .env.config always ends with a newline (unit test on the final byte)
- [x] #2 An append of KEY=value to a freshly generated .env.config lands on its own line and survives config generate into .env
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
NORTH STAR DELIVERED: an operator following our documentation can no longer corrupt their configuration by appending a key. SHIPPED 7054e7593 (2026-07-06): the fix landed at the shared seam — dotenv.File.Save() now always terminates the file with exactly one newline — covering .env.config, .env.credentials, and every other env-file writer (sb dotenv set, cert/upgrade/install writers) in one move; idempotent by construction. Architect verified all 14 Save call sites have no byte-exactness consumers and the roundtrip test keeps its full formatting pin. AC#1: unit test asserts the final byte. AC#2 observed literally on a real dev tree: the pre-fix .env.config ended without a newline; one `sb config generate` with the fixed binary later, both generated files end with one, and an appended key parses independently (test-pinned at the parser the generator reads with). Found in park-oracle run r13, where the append-glue corrupted ADMINISTRATOR_CONTACT on a live VM.
<!-- SECTION:FINAL_SUMMARY:END -->
