---
id: STATBUS-174
title: >-
  norway-ident-customization: hide non-tax external idents + rename
  tax_ident→"Org.Number" — reconciled with the live brreg loading it would break
status: To Do
assignee: []
created_date: '2026-07-13 12:08'
updated_date: '2026-07-23 15:54'
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
- [x] #1 The reconciliation is established: whether 'hide non-tax idents' must be presentation-only (UI) vs enabled=FALSE, decided against what the current brreg 2024/2025 import definitions actually create and use — with the answer that does NOT break brreg loading
- [ ] #2 tax_ident relabelled to 'Org.Number' with no code keyed on the type name broken
- [ ] #3 The customization uses the current pattern (public.reset('getting-started')), not the deleted \ir ./reset.sql
- [ ] #4 Proven on a real Norway load: brreg getting-started + an import still loads data AND the UI shows only Org.Number — the run is the oracle
- [x] #5 fix-custom-scripts branch retired (its no.sql intent lives here; ke.sql confirmed dead)
- [ ] #6 DESIGN CONSTRAINT (King, 2026-07-13): reference external_ident_type by its semantic CODE ('tax_ident'), NEVER by a hardcoded id — no magic numbers. Erik's branch used `WHERE id != 1`; the shipped form works in a semantical, clear world: `WHERE code = 'tax_ident'` / `WHERE code <> 'tax_ident'`. (Verified seeded codes: 'tax_ident', 'stat_ident'.)
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-13 12:15
---
DESIGN DIRECTIVE (King, 2026-07-13): do NOT carry Erik's hardcoded id — work by semantic code. Verified against the seed: external_ident_type codes are 'tax_ident' and 'stat_ident' (samples/norway/getting-started.sql + migrations), so Erik's `id = 1` was merely the tax_ident row's physical id. The shipped customization references the CODE:
```sql
-- only the org number (tax_ident) visible in Norway
UPDATE external_ident_type SET enabled = FALSE WHERE code <> 'tax_ident';
UPDATE external_ident_type SET name = 'Org.Number'  WHERE code =  'tax_ident';
```
No magic numbers, self-describing, stable if row ids ever shift. This is a general principle for the port, not just these two lines — semantic codes over physical ids everywhere the customization touches. (The enabled=FALSE-vs-presentation-only reconciliation from AC#1 still governs whether these run as-is or become a UI-only hide — the code-not-id rule applies to whichever form ships.)
---

author: foreman
created: 2026-07-13 12:20
---
RECONCILIATION RESOLVED by investigation (foreman-verified against doc/db + samples/norway, 2026-07-13) — AC#1 answered, the customization IS feasible and safe for Norway. TWO HALVES:

1. RENAME (name→'Org.Number') = UI-ONLY, safe. The import path keys on `code` EVERYWHERE (import_analyse_link_* JOIN xit.code; import_analyse_legal_relationship `WHERE code='tax_ident'`; import_get_statistical_unit_data_partial `jsonb_object_agg(eit.code,...)`). `name` is a pure display label — nothing functional reads it. The King's insight confirmed: renaming while retaining the code touches nothing but the UI.

2. HIDE (enabled=FALSE WHERE code<>'tax_ident') = affects import, but harmless for Norway. `enabled` is NOT cosmetic — the import iterates the VIEW `external_ident_type_enabled` (import_generate_external_ident_data_columns, import_analyse_external_idents, import_helper_process_external_idents all loop/join it), so enabled=FALSE removes a type from the import's active set. BUT Norway's brreg import loads ONLY tax_ident (samples/norway/brreg: organisasjonsnummer→tax_ident, overordnetEnhet→legal_unit_tax_ident — still the tax type; no stat_ident, no other type). Disabling the only other seeded type (stat_ident) removes something Norway never loads → breaks nothing, correctly hides it.

HONEST BOUNDARY (must be a comment at the shipped site): the customization is safe BECAUSE Norway's import is org-number-only. If a future Norway import adds stat_ident or another type, enabled=FALSE on it would then gate THAT import — safety is coupled to Norway's import scope. So it's still a genuine data-model op (not literally UI-only), but for the current Norway pipeline it is effectively a presentation change with zero load impact. Ship it by code (AC#6), modernize the reset pattern (AC#3), prove on a real Norway load (AC#4).
---

author: foreman
created: 2026-07-13 12:39
---
BRREG SPELLING CORRECTION (King directive, checked against the official brreg guide, 2026-07-13): the label is NOT the anglicized 'Org.Number'. Official terms — Norwegian: **'Organisasjonsnummer'** (one word, the official brreg term; 75 occurrences in samples/norway as `organisasjonsnummer`); English (brreg's own docs, data.brreg.no): 'organisation number' (British spelling); standard abbreviation: 'Org.nr.' (5 occurrences in-repo). no.statbus.org is Norwegian, so the shipped label is **'Organisasjonsnummer'** (or 'Org.nr.' if a compact UI label is wanted — the King's pick). The rename UPDATE becomes: `UPDATE external_ident_type SET name = 'Organisasjonsnummer' WHERE code = 'tax_ident';`. Supersedes the 'Org.Number' in the earlier comments/AC.
---

author: foreman
created: 2026-07-23 15:54
---
AC#5 DONE (2026-07-23): fix-custom-scripts is retired from origin — verified absent by ls-remote. Per this ticket's own plan ('the branch is retired once this ticket exists'): the no.sql intent lives verbatim in the description (source tip 7b01c88cb recorded for archaeology), ke.sql confirmed dead against master. The King confirmed in chat today that this ticket is where the Norway-customization decision + pending state live; the branch question on STATBUS-035 is closed by this retirement. Remaining here: AC#1's reconciliation is checked; ACs #2-#4 + #6 are the build — unscheduled, parallel lane.
---
<!-- COMMENTS:END -->
