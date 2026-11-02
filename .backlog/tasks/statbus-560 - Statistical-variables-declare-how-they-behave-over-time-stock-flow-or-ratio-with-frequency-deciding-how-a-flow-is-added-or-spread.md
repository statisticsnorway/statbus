---
id: STATBUS-560
title: >-
  Statistical variables declare how they behave over time: stock, flow or ratio,
  with frequency deciding how a flow is added or spread
status: To Do
assignee: []
created_date: '2026-11-02T21:15:00Z'
updated_date: '2026-11-02T21:24:00Z'
labels: []
dependencies: []
type: feature
ordinal: 483204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## North Star
Every statistical variable says how it behaves over time, so each report combines it correctly: a stock is read at a date, a flow is added over the period it covers, a ratio is recomputed from its parts. jsonb_stats stays the one generic, variable-agnostic summary.

## Zoom out
A stat_for_unit value holds for its validity interval, and every derivation reads it as true at every instant of that interval. That is right for a stock: employees = 12 for 2025 means 12 people at every date. It is wrong for a flow: turnover = 12,000,000 for 2025 is an amount over the year, so the history repeats it in all 12 months and adding the months gives 144 million. It is wrong for a ratio: margin = 0.2 must never be summed, yet jsonb_stats sums it and its mean is unweighted. This is invisible today only because every variable is yearly and valid from 1 January.

## Zoom in
- stat_definition (2026-11-02): code, name, description, type (int/float/string/bool picks the value_* column and the jsonb_stats agg type), frequency (daily to yearly; read by no derivation; the admin UI always inserts yearly, every country seed says yearly), priority, enabled. Only priority and enabled have comments.
- stat_for_unit: one value per variable, unit (legal unit or establishment) and validity interval, merged by temporal_merge; stat = stat(value).
- statistical_unit: variable boundaries become timepoints; stats holds the unit's own values per segment; stats_summary merges included units (establishment to legal unit to enterprise).
- Agreed direction (owner, 2026-11-02): each stat_definition declares stock, flow or ratio. For a flow, frequency gives the reporting period, so a derivation knows when to add (periods at or above the frequency) and when it would have to spread (finer periods). The behaviour only decides when and over which time span values enter a jsonb_stats merge.
- Out of scope: owning level. Countries report on legal units, establishments or both, by their own practice; never assume double counting. statistical_unit already shows a unit's own values next to its included units; a report making the difference easy to check is a separate ticket. STATBUS-558 (facet reduce speed) is separate.

## Closing review
Confirm every derivation that combines a variable over time applies its behaviour, the owner decisions below are recorded in this ticket, and the meaning of frequency and behaviour is in COMMENT ON at their definitions.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 stat_definition declares each variable's time behaviour (stock, flow, ratio), documented with COMMENT ON, with frequency's meaning for a flow defined
- [ ] #2 A test loads a flow of 12,000,000 valid for one year: the yearly history shows 12,000,000, and the 12 months together never exceed 12,000,000 (shown per the owner's decision on finer periods)
- [ ] #3 A test with a ratio variable: the rolled-up value equals the ratio of the rolled-up parts, not the sum or unweighted mean of the units' ratios
- [ ] #4 [Owner] Decide how a yearly flow appears in monthly views: proportional share by days, or only at yearly resolution. Recorded in this ticket's notes; proportional changes the history derivation to spread values, yearly-only hides flows below their frequency.
- [ ] #5 [Owner] Decide frequency's exact role for a flow (reporting period that sets add versus spread, or more). Recorded in this ticket's notes; it fixes the COMMENT ON for frequency and the rule the derivations apply.
- [ ] #6 [Owner] Decide whether string and bool variables get a fourth behaviour (state: count units per value at a date) or are implied by type. Recorded in this ticket's notes; a fourth value adds it to the behaviour enum, otherwise type decides.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-02 PROPOSITIONS (owner not committed yet):
1. Finer periods: a flow appears from its own frequency upwards; a coarser view combines finer values: a flow adds them up (four quarters make the year), a stock shows the last value in the period (the level at its end). Proportional spreading into finer periods only as an explicit, labelled estimate.
2. Frequency is the reporting period of a variable. Owner's intent: it guides edits, so an interactive update is snapped to the nearest period of that frequency (a yearly turnover edit covers a whole year) instead of creating sub-period slices; it also sets the finest resolution a flow is shown at. The validity interval says what span a value covers, so a part-year value (unit born in July) is the turnover for that part; the import can warn when an interval is longer than the frequency.
3. Behaviour (stock, flow, ratio) is chosen only for numeric variables; string and bool follow from type and behave like a stock of counts per value.
<!-- SECTION:NOTES:END -->
