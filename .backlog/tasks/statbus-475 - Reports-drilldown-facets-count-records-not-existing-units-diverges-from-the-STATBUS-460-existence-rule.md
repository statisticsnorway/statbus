---
id: STATBUS-475
title: >-
  Reports drilldown facets count records, not existing units (diverges from the
  STATBUS-460 existence rule)
status: To Do
assignee: []
created_date: '2026-10-08 16:00'
labels:
  - reports
  - data-model
dependencies: []
priority: medium
ordinal: 401204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: the Reports drilldown (statistical_unit_facet_drilldown) answers 'how many units exist' with the same canonical existence rule as the dashboard cards, the Statistical Units list and the Units-over-time chart (STATBUS-460). EVIDENCE: public.statistical_unit_facet_def groups statistical_unit by (valid_from, valid_to, valid_until, unit_type, facets) WHERE used_for_counting, and public.statistical_unit_facet_drilldown filters suf.valid_from <= valid_on AND valid_on < suf.valid_until. Neither looks at birth_date or death_date, so the drilldown counts RECORDS whose window covers the instant, which is exactly the predicate STATBUS-460 retires from the other screens. On dev at valid_on 2023-12-31 that means the drilldown counts the 13 demo establishments whose record window starts 2023-01-01 but whose birth_date is 2024-11-01 (the STATBUS-458 rows), so after 460 lands the drilldown total (24) and the dashboard card / chart (11) disagree visibly. WHY SEPARATE: the facet table pre-aggregates by validity window, so applying the rule needs the existence window (GREATEST(valid_from, birth_date), LEAST(valid_until, death_date)) carried into the facet grouping key or the facet derivation, plus a facet rebuild; that is a derivation change with its own performance budget, not a predicate swap. Cross-reference: STATBUS-460 (canonical rule, computed fields public.existence_from/existence_until).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 statistical_unit_facet (or its drilldown) counts a unit at valid_on iff it exists by the STATBUS-460 rule; the 458 demo rows are absent from the 2023 drilldown and present in 2024
- [ ] #2 On dev the drilldown total equals the dashboard card and the Units-over-time chart for 2023-12-31 and 2024-12-31
- [ ] #3 pg_regress covers a unit born after its record window starts and a unit that died inside its window, in the drilldown
- [ ] #4 Facet derivation time on the Norway dump is measured before and after and recorded in the ticket
<!-- AC:END -->
