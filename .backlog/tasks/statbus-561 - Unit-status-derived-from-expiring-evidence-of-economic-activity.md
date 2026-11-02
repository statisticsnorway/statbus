---
id: STATBUS-561
title: Unit status derived from expiring evidence of economic activity
status: To Do
assignee: []
created_date: '2026-11-02T21:33:00Z'
updated_date: '2026-11-02T21:45:00Z'
labels: []
dependencies: []
type: feature
ordinal: 484204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
North Star: a unit's status, and with it whether it is counted, follows from evidence that it is economically active (a VAT return, a payroll, reported turnover), each piece valid for a set time, instead of only being typed in.

Today public.status is a plain reference list (code, name, assigned_by_default, used_for_counting, priority, enabled). A unit's status_id is set by import or edit and nothing derives it. Status decides used_for_counting, so this feeds directly into who is counted in every report.

Owner's draft model (2026-11-02):
  economic_activity_type(id, code, duration, status_id, description), e.g. VAT, 12 months, active
  economic_activity(id, legal_unit_id | establishment_id, type_id, observed_on, expires_on, note, source), e.g. 2026-01-03, 2027-01-03, VAT, 'Sent VAT report'
[observed_on, expires_on) is a validity interval (evidence of activity holds until it expires), so it fits the temporal model: overlapping observations merge into continuous active periods.

Two ways to link to status, which can coexist:
a) by type: each activity type maps to a status, and the latest valid observation decides it. Fits offices that receive event markers.
b) by statistical variable: each stat_definition gets a default evidence duration, so a reported value (turnover for 2025) is evidence of activity. Fits offices that only receive counted figures. This touches STATBUS-560 (variable behaviour); the duration is not the same as frequency.

Open: what offices actually receive (event markers, counted figures or both) decides which link comes first.

Closing review: the derived status agrees with entered statuses on a country's real data, the combination of entered and derived status is documented, and used_for_counting changes are visible in the reports.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 [Owner] Decide, with country input, what evidence offices receive (event markers, counted figures, or both). Recorded in this ticket's notes; markers lead to option a first, figures to option b, both to a combined derivation.
- [ ] #2 [Owner] Decide how an entered status and a derived status combine (derived only, entered overrides, or derived as suggestion). Recorded in this ticket's notes; it sets whether status_id stays editable.
- [ ] #3 A test: a unit with a VAT observation on 2026-01-03 of a 12-month type is active from 2026-01-03 until 2027-01-03 and not after, unless a later observation extends it
<!-- AC:END -->
