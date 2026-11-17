---
id: r39dqb
title: "Norway unit coordinates reach the Norway installation without entering git"
state: todo
type: feature
priority: ""
assignee: []
labels: []
created: 2026-11-18
updated: 2026-11-18
---

## Goal
The Norway installation gets coordinates for its legal units and establishments from Erik's data (PR #326) without the large CSV files entering the repository.

## Purpose
Coordinates let units be shown on a map (z2qt08). Erik's PR https://github.com/statisticsnorway/statbus/pull/326 (rsbssbno, 2026-11-14) adds them as files under samples/norway: about 1M legal units and 792K establishments, +1,841,178 lines, about 100 MB.

## Principle
No huge data files in the repository (owner 2026-11-17). The coordinates are specific to the Norway installation and come from the register, so they travel the way Norway's other data does (an import), not inside the code.

## Relevant details
Files: samples/norway/legal_unit/statistical_units_legal_coords.csv and samples/norway/establishment/statistical_units_estab_coords.csv (tax_ident, name, physical_latitude, physical_longitude), samples/norway/regions/norway-regions-2026.csv. Erik's note: name is required today and may go once import can match on tax_ident alone. The column names assume PR #327's rename. The owner has ideas on how to handle this and expects to adapt the work.

## Depends on

- kvbebr
## Acceptance
- [ ] [Owner] Decides where the coordinate files live and how Norway loads them; the answer is recorded in the notes
- [ ] Norway's units carry the coordinates after the agreed load, shown by a count of units with physical coordinates on the Norway database
- [ ] PR #326 is closed on GitHub with a comment that links this task and says where the data went

## Notes
