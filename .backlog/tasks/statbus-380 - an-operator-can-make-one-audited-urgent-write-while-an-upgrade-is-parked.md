---
id: STATBUS-380
title: An operator can make one audited urgent repair while an upgrade stays parked
status: To Do
assignee: []
created_date: '2026-09-21 12:03'
updated_date: '2026-09-24 18:45'
labels:
  - upgrade
  - recovery
  - cli
dependencies: []
priority: low
type: task
ordinal: 22
---

## Description

`./sb upgrade repair --file <sql> --reason <reason> --operator <name>` applies exactly one reviewed SQL statement while a genuinely parked upgrade remains parked. The same transaction records operator, reason, connection, and repair marker in `public.upgrade_state_log`. Client writes remain held throughout.

## Evidence, 2026-09-24

The repair command is merged at `cli/cmd/upgrade_repair.go:78-153` at master `7a9cf707e`. Its SQL requires a parked row, locks that row, writes the audit record, and runs the reviewed statement in one transaction (`cli/cmd/upgrade_repair.go:130-153` at master `7a9cf707e`). The parked window is a client hold rather than an administrator capability boundary (`doc/upgrade-recovery-model.md:60-74` and `doc/read-only-upgrade-window.md`, “Maintenance writes” section, at master `7a9cf707e`). The historical fixture commit is not asserted without a permitted primary record. Owner confirmation of this policy remains open.

## Acceptance Criteria

- [ ] #1 `cli/cmd/upgrade_repair_test.go::TestParkedRepairSQL_AuditsAndKeepsOneTransaction` proves one transaction contains the parked-row check, audit fields, and reviewed statement.
- [ ] #2 `cli/cmd/upgrade_repair_test.go::TestParkedRepairSQL_RejectsMetaCommandsAndTransactionVariants` proves multi-statement, transaction-control, and meta-command inputs are refused.
- [ ] #3 `cli/cmd/upgrade_repair_test.go::TestUpgradeRepairRequiresAuditInputs` requires file, reason, and operator.
- [ ] #4 `new: test/install-recovery/scenarios/7-parked-upgrade-audited-repair.sh` parks a real upgrade, performs one repair, observes one matching audit record, unchanged parked state, and continued client-write hold.
- [ ] #5 `new: doc/upgrade-repair-policy.md::owner-decision` records owner confirmation or the replacement policy before completion.
