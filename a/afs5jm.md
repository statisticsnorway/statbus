---
id: afs5jm
title: "Search Download can give only a chosen subset of columns"
state: todo
type: feature
priority: "medium"
assignee: []
labels: []
group: ""
rank: "zzzzzzzz"
created: 2026-11-23
updated: 2026-11-23
---

## Goal
From /search a user downloads either every column, as today, or only a chosen subset of columns, in CSV or Excel.

## Purpose
Owner 2026-11-22: /search should say Download and allow an optional subset of columns. The label is done (8aaf0262b, xz3jej, on master, not yet released); every download today has all columns in a fixed order, whatever the table shows.

## Principle
The full download stays the default; a subset keeps the export's column order and the same rows as the full download of the same filter.

## Details
Export: app/src/app/search/export (export-sql.ts composes the COPY select from ExportColumnConfig; export-copy-stream.ts streams CSV, xlsx-stream.ts Excel). The search table's shown columns live in tableColumnsAtom (atoms/search.ts). Options for the subset: (a) the columns shown in the table, chosen with its existing Columns menu, as a Download menu item 'Only the columns shown'; (b) a separate column picker in the Download menu.

## Depends on

## Acceptance
- [ ] [Owner] Chooses: (A) Download follows the table: an info icon says the file holds the columns shown, changed with the Columns menu; the menu has Columns shown (default, from tableColumnsAtom) and All columns; or (B) a Customize columns dialog on Download, starting from all columns, separate from the table; recorded here, and checks 2 and 3 test the chosen one
- [ ] With the subset chosen, a CSV and an Excel download contain exactly those columns in export order and the same rows as the full download; a test asserts header and row count for both formats
- [ ] The full download is unchanged; the existing export tests pass

## Notes

2026-11-23 (Rabbit) Checked the code: the download never follows the table. exportColumns (app/src/app/search/export/export-sql.ts) always writes the same ~45 columns in a fixed order; only the unit-type filter changes it (no unit_type when one type is chosen; establishments get no sector or legal form). Owner 2026-11-23 named two ways: (a) a 'Customize columns' dialog on Download, or (b) an info icon saying the download holds the columns shown, adjusted with the table's Columns menu, and Download respects that. Rabbit proposed (b) with two menu items: 'Columns shown' (default, with the info icon) and 'All columns'. Awaiting the owner's pick (check 1).
