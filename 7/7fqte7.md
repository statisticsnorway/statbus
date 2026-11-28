---
id: 7fqte7
title: "An Excel upload picks the sheet with the expected columns and says which"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "zzzzzzzzzzzz"
created: 2026-11-28
updated: 2026-11-28
---

## Goal
An Excel upload uses the one sheet whose header fits the upload, names it, and refuses a workbook with no or several such sheets.

## Purpose
Today every Excel upload silently takes the first sheet (app/src/lib/excel-to-csv.ts SheetNames[0]). A statistics office's workbook often holds several sheets (codes, notes, other lists); if the regions are not first, the upload reads the wrong sheet and fails on its columns, or stores the wrong data.

## Principle
The browser reads the whole workbook and decides before anything is sent; other sheets cost nothing on the server. A sheet is chosen by its header matching the upload's columns, never by position alone. The person sees which sheet was used. No guess: no match or several matches is a refusal that lists the sheets and what each header holds.

## Details
Paths: getting-started uploads (upload-excel.ts fileAsCsvText -> convertExcelToCsvBlob) and the import job upload (import-job-upload.tsx inspectFile/convertExcelToCsvBlob), both SheetNames[0]. Owner 2026-11-28: reject the whole thing, or ignore the others and say which sheet is used. Raised while reviewing Uganda's failed region upload (7dw69p); their file's type is unknown until their screenshots.

## Depends on

## Acceptance
- [ ] A workbook with notes on sheet 1 and the regions on sheet 2 uploads, and the check step says it read sheet 2 by name; jest with a generated workbook
- [ ] A workbook where no sheet has the expected columns is refused, naming each sheet and its first-row columns
- [ ] A workbook with two sheets that both match is refused, naming both
- [ ] The import job upload follows the same rule for its definition's columns

## Notes
