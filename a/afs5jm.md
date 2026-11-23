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
- [ ] [Owner] Chooses (a) the columns shown in the table or (b) a separate picker; recorded here
- [ ] With the subset chosen, a CSV and an Excel download contain exactly those columns in export order and the same rows as the full download; a test asserts header and row count for both formats
- [ ] The full download is unchanged; the existing export tests pass

## Notes
