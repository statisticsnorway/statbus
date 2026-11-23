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
Owner 2026-11-22: a user often wants a file with only some columns; today every download has all columns in a fixed order, whatever the table shows.

## Principle
The full download stays the default; a subset keeps the export's column order and the same rows as the full download of the same filter.

## Details
Export: app/src/app/search/export (export-sql.ts exportColumns composes the COPY select from ExportColumnConfig; export-copy-stream.ts streams CSV, xlsx-stream.ts Excel). The table's shown columns live in tableColumnsAtom (atoms/search.ts). Today only the unit-type filter changes the columns (no unit_type when one type is chosen; establishments get no sector or legal form).

## Depends on

## Acceptance
- [ ] [Owner] Chooses (A) or (B); recorded here. (A) leads to reusing the table's Columns menu (tableColumnsAtom): an info icon on Download says the file holds the columns shown, and the menu offers Columns shown (default) and All columns. (B) leads to a new Customize columns picker inside Download, starting from all columns, separate from the table
- [ ] With the subset chosen, a CSV and an Excel download contain exactly the subset chosen in check 1 in export order and the same rows as the full download; a test asserts header and row count for both formats
- [ ] The full download is unchanged; the existing export tests pass

## Notes

2026-11-23 (Rabbit) Checked the code: the download never follows the table (exportColumns always writes the same ~45 columns). Options are in check 1; Rabbit proposed (A).

2026-11-23 (Rabbit) The Download label is done: 8aaf0262b (xz3jej), on master, not yet released.

2026-11-23 owner: (B) a Customize columns dialog, made easy rather than ticking every column: presets such as All, a minimal subset, or Custom. How it works is to be discussed, likely with a local prototype first.
