---
id: STATBUS-174
title: >-
  norway-ident-customization: hide non-tax external idents + rename
  tax_ident→"Org.Number" — reconciled with the live brreg loading it would break
status: To Do
assignee: []
created_date: '2026-07-13 12:08'
labels:
  - norway
  - data-model
  - import
  - not-install-upgrade
dependencies: []
priority: medium
ordinal: 175000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: no.statbus.org presents only the Norway-relevant identifier (the org number) in the UI — non-tax external_ident_types hidden, tax_ident labelled "Org.Number" — WITHOUT breaking the brreg data loading the box depends on.
> ORIGIN: captured from the fix-custom-scripts branch (Erik Søberg's custom/no.sql), King review 2026-07-13. The branch is retired once this ticket exists; the intent is preserved here so the investigation is never repeated.
> STAGE: Norway / data-model customization. COMPLEXITY: engineer — the customization itself is trivial SQL; the WORK is reconciling it with the live loading pipeline it currently conflicts with.
> DEPENDS ON: nothing.

THE CUSTOMIZATION (verbatim intent from custom/no.sql on fix-custom-scripts):
```sql
CREATE OR REPLACE PROCEDURE public.custom_setup_no() ... BEGIN
  -- only tax ident (org number) in Norway
  UPDATE external_ident_type SET enabled = FALSE WHERE id != 1;   -- hide all non-tax ident types
  UPDATE external_ident_type SET name = 'Org.Number' WHERE id = 1; -- relabel the tax ident
END; ... CALL public.custom_setup_no();
```

THE CRITICAL CONFLICT (King, 2026-07-13 — this is why it is NOT a minor change, and why the branch's script cannot be applied as-is): no.statbus.org runs on a LOT of live brreg data, loaded via `samples/norway/getting-started.sql` + the brreg import definitions (samples/norway/brreg/*), ALL of which are currently keyed on **tax_ident**. The branch's `custom_setup_no()` disables every external_ident_type except id=1 and was written against an OLD setup — applying it against the current pipeline would BREAK data loading on no.statbus.org (the King could no longer load brreg data). So this is a data-model change that must be reconciled with the live import path, not a script to port.

WORK TO DO (the real design):
1. Establish what "hide non-tax idents" must mean AGAINST the current brreg loading — which external_ident_types the 2024/2025 hovedenhet + underenhet + roller import definitions actually create/use, and whether disabling them breaks import or only the UI presentation. The customization may need to be presentation-only (UI hides them) rather than `enabled=FALSE` (which may gate import).
2. The rename tax_ident→"Org.Number" is likely the safe, wanted half — verify it doesn't break any code keyed on the type's name.
3. Modernize away the dead pattern: the branch's script uses `\ir ./reset.sql` (master DELETED custom/reset.sql in ea721b8c5) — any shipped form uses `SELECT public.reset(true,'getting-started')`, matching custom/ke.sql's current master pattern.
4. Prove it on a real Norway load: apply the customization, run the brreg getting-started + an import, confirm data still loads AND the UI shows only Org.Number.

SOURCE BRANCH (for archaeology, retired): fix-custom-scripts, tip 7b01c88cb, file custom/no.sql. custom/ke.sql on that branch is DEAD (master's ea721b8c5 superseded it + deleted the reset.sql it depends on) — do NOT port ke.sql; only no.sql's intent is live, and only after the reconciliation above.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The reconciliation is established: whether 'hide non-tax idents' must be presentation-only (UI) vs enabled=FALSE, decided against what the current brreg 2024/2025 import definitions actually create and use — with the answer that does NOT break brreg loading
- [ ] #2 tax_ident relabelled to 'Org.Number' with no code keyed on the type name broken
- [ ] #3 The customization uses the current pattern (public.reset('getting-started')), not the deleted \ir ./reset.sql
- [ ] #4 Proven on a real Norway load: brreg getting-started + an import still loads data AND the UI shows only Org.Number — the run is the oracle
- [ ] #5 fix-custom-scripts branch retired (its no.sql intent lives here; ke.sql confirmed dead)
<!-- AC:END -->
