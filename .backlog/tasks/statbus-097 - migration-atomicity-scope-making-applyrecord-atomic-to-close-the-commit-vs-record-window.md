---
id: STATBUS-097
title: >-
  migration-atomicity: scope making apply+record atomic to close the
  commit-vs-record window
status: In Progress
assignee: []
created_date: '2026-06-18 21:36'
updated_date: '2026-06-20 10:54'
labels:
  - upgrade
  - migration
  - design-scoping
dependencies: []
priority: high
ordinal: 97000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
▶ DRIVE DECISION + STATUS (King, 2026-06-20): DRIVE NOW (King: "right now"). This is the principled fix for the after-commit-before-recorded recovery finding — a migration that commits but is killed before it is recorded is a torn state that is UNDETECTABLE from the ledger (indistinguishable from never-applied), so the box can certify 'completed' on it; atomic apply+record makes the torn state UNREACHABLE. STATUS: In Progress. AC#1 DONE (operator: 359/362 transactional, 3 non-tx ALTER TYPE ADD VALUE). AC#2 (architect recommendation) NEXT → AC#3 King policy decision → product change. NO product change until the King's AC#3 policy decision (the task gates it). Product change sequences AFTER the STATBUS-102 channel-bless simplification (both touch migrate.go).

----

From the King's no-residual rule (2026-06-18), applied to the one residue the fingerprint/kill reshape leaves behind.

THE WINDOW: when a migration commits, there is a ~millisecond gap before the system records that it ran (the db.migration INSERT, done in Go after psql returns). If the process dies in that gap, the migration is applied-but-unrecorded — a torn state. It is too small to hit by external timing, so it is the one crash point the NOTIFY-handshake / external-kill approach cannot reproduce.

THE CLEAN FIX (the King's rule): make "apply" and "record" ONE atomic step — fold the db.migration INSERT into the migration's own transaction — so the torn state CANNOT exist. Then there is nothing to test and no hook needed.

THE WRINKLE: some migrations legitimately cannot run in a single transaction (CREATE INDEX CONCURRENTLY, some ALTER TYPE, VACUUM). For those the window is intrinsic.

SCOPE THIS (read-only first, no product change yet):
1. Count how many real migrations in migrations/ cannot run in one transaction (concurrent index builds, etc.) — with the list.
2. Recommend: make apply+record atomic for the transactional majority (removes the window for them); for the non-transactional exceptions, either keep ONE minimal inject hook for that window or accept it untested. Present the count so the King decides the policy.

Source: King, 2026-06-18 — asked whether to open this as its own entry; opened. Now driven (King, 2026-06-20).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A count + list of migrations in migrations/ that cannot run in a single transaction
- [x] #2 A written recommendation: atomic apply+record for the transactional majority, and a proposed policy for the non-transactional exceptions (minimal hook vs accept-untested)
- [ ] #3 The King's policy decision recorded BEFORE any product change is made
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-06-20 10:35
---
King directed 2026-06-20: drive this NOW. It is the principled fix for the after-commit-before-recorded recovery finding (the box can certify 'completed' on a committed-but-unrecorded migration because the torn state is undetectable from the ledger; atomic apply+record makes the torn state unreachable). Starting AC#1 scoping (count + list non-transactional migrations) now -> AC#2 recommendation -> AC#3 King policy decision -> product change.
---

author: foreman
created: 2026-06-20 10:38
---
AC#1 DONE (operator, 2026-06-20). 362 total migrations. NON-TRANSACTIONAL = 3 (~0.8%), all ALTER TYPE ... ADD VALUE: 20260218215337_add_legal_relationship_import.up.sql:10; 20260326161813_add_edge_upgrade_channel.up.sql:5; 20260325114130_add_interrupted_state_for_crash_recovery.up.psql:12. TRANSACTIONAL majority = 359 (99.2%). 4 false-positives (comments/strings) ruled out. The 3 already use the add-then-use split (two transactions). NOTE for AC#2: PG18 CAN run ALTER TYPE ADD VALUE inside a tx (the restriction is USING the new value in the same tx) — but these 3 migrations USE the value, hence the split → they are genuinely multi-tx in practice. AC#2 (architect recommendation) next.
---

author: foreman
created: 2026-06-20 10:52
---
AC#2 DONE (architect, 2026-06-20). RECOMMENDATION: make apply+record atomic for the 359 single-tx migrations (99.2%) — inject the db.migration INSERT as the LAST statement inside the migration's OWN transaction, just before its closing END/COMMIT. KEY correctness point: the closing-END locator MUST be dollar-quote-aware (a function body's `$$ BEGIN…END $$` must not be mistaken for the close) — small tokenizer, tested against all 359. No migration rewrites; performance-neutral (one fewer psql round-trip). 097 is NOT a one-liner — it's a real tx-ownership change.
THE 3 NON-TX (ALTER TYPE ADD VALUE, multi-tx add-then-use): window is INTRINSIC, atomicity can't dissolve it. IDEMPOTENCY-ON-RERUN (foreman-verified from the files): 20260218215337 (IF NOT EXISTS) + 20260326161813 (IF NOT EXISTS) recover cleanly on re-run; 20260325114130 ('interrupted', NO IF NOT EXISTS) does NOT — re-run CONFLICTS → forces the rollback path.
AC#3 (King's call): (a) keep ONE minimal inject-hook to test the multi-tx partial-recovery rollback (architect leans this; the 1 non-idempotent + any future non-IF-NOT-EXISTS need it); vs (b) accept untested (3/362=0.8%, ~ms window). Foreman add: a CONVENTION requiring IF NOT EXISTS on future ALTER TYPE ADD VALUE → future ones idempotent → only the 1 legacy needs the hook/accept. Brought to the King for AC#3.
---

author: foreman
created: 2026-06-20 10:54
---
AC#3 REFINEMENT (architect + foreman, 2026-06-20): the IF-NOT-EXISTS convention should be ENFORCED, not just documented — a documented convention drifts (a future migration forgets it, silently re-introduces the non-idempotent window). Per the King's own principles (gate the output with intent; always add constraints): add a CHECK at `./sb migrate new` scaffolding AND/OR the release-cut gate that any `ALTER TYPE ... ADD VALUE` carries `IF NOT EXISTS`, else fail with an actionable message. Cheap (regex-level lint over migration SQL). CONSEQUENCE: with enforcement, ALL future ALTER-TYPE migrations are GUARANTEED idempotent → the hook-vs-accept question collapses to the ONE existing legacy migration (20260325114130). So AC#3 = (1) enforce the convention (recommended), + (2) for the single legacy: (a) one cheap test-hook for its rollback path (architect+foreman lean) vs (b) accept untested.
---
<!-- COMMENTS:END -->
