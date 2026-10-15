---
id: STATBUS-380
title: An operator can make one audited urgent repair while an upgrade stays parked
status: In Progress
assignee: []
created_date: '2026-09-21 12:03'
updated_date: '2026-10-15 20:09'
labels:
  - release-bug
  - upgrade
  - recovery
  - cli
dependencies: []
priority: low
type: task
ordinal: 22
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
An operator can make one deliberate, reviewed repair to a parked StatBus database, and the box records who did it and why, while the upgrade stays parked and clients stay held.

### Zoom out
A parked upgrade freezes clients by holding the database read-only for them. That hold is a client hold at the `default_transaction_read_only` level, not an administrator boundary, because recovery itself needs maintenance writes. So an administrator can always write, and the only question is whether that write is sanctioned and recorded. Before this ticket the choices were raw admin psql with the read-only exemption (undocumented, easy to get wrong, no audit trail) or `./sb install`, which un-parks and retries immediately and so is no repair pause at all.

The product answer is one verb, `./sb upgrade repair --file <sql> --reason <reason> --operator <name>`. It checks the row is genuinely parked, locks it, writes the audit record and runs exactly one reviewed statement, all in one transaction. It refuses multiple statements, transaction control and psql meta-commands, and the upgrade stays parked.

### Zoom in
- **Origin, 2026-09-21:** reviewing the `c-rollback-resurrection` arc's fixture repair (`feae0fccf`), which wrote during B's parked window with `PGOPTIONS=-c default_transaction_read_only=off`, the owner asked whether that circumvents the invariant. It does not (`doc/upgrade-recovery-model.md`, `doc/read-only-upgrade-window.md`), but it exposed the missing operator path.
- **Shipped (v2026.09.3):** `4e8899f05` (the audited verb), `4069671b3` (fail closed on repair SQL), `a0781aab7` (refuse a bare `END`). `cli/cmd/upgrade_repair.go`. Documented as the sanctioned path in `doc/upgrade-recovery-model.md` (park section) and `doc/read-only-upgrade-window.md` ("Maintenance writes").
- **Proof, unit:** `TestParkedRepairSQL_AuditsAndKeepsOneTransaction`, `TestParkedRepairSQL_RejectsMetaCommandsAndTransactionVariants`, `TestUpgradeRepairRequiresAuditInputs` (`cli/cmd/upgrade_repair_test.go`), green 2026-10-15.
- **Not on a real box:** no scenario or arc parks a real upgrade and runs `./sb upgrade repair`; the park arcs (`postswap-health-park-arc.sh`, `un-park-to-completion-arc.sh`) do not use it.

### Closing review
- **Memory:** none needed.
- **Documentation:** done; the two docs above name the verb.
- **Cleanup:** the former criterion asking for a test that a policy document records the owner's decision was dropped as a text-presence check; the decision itself is the last criterion.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 One transaction holds the parked-row check, the audit fields and the reviewed statement (`TestParkedRepairSQL_AuditsAndKeepsOneTransaction`)
- [x] #2 Multiple statements, transaction control and psql meta-commands are refused (`TestParkedRepairSQL_RejectsMetaCommandsAndTransactionVariants`)
- [x] #3 File, reason and operator are required (`TestUpgradeRepairRequiresAuditInputs`)
- [ ] #4 A real parked upgrade receives one repair through `./sb upgrade repair`, with one matching audit record, the row still parked, and client writes still held
- [ ] #5 [Owner] Confirm `./sb upgrade repair` as the approved policy for writing to a parked database, and decide whether AC4's real-box run is required; record both in Implementation Notes. AC4 not required: remove it, check this and set Done.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1-3:** green in Go Test `36503468493` (v2026.09.3); re-run locally 2026-10-15.
- **AC4:** open; no scenario or arc uses the verb.
- **AC5:** open.
<!-- SECTION:NOTES:END -->
