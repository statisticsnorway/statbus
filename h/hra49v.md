---
id: hra49v
title: "Spike: Excel files beyond one sheet's row limit, streamed both ways"
state: todo
type: feature
priority: "low"
assignee: []
labels: []
group: ""
rank: "zzzzzzzzzzzu"
created: 2026-11-28
updated: 2026-11-28
---

## Goal
Measure whether StatBus can download and upload more than 1,048,575 rows as one Excel workbook split over sheets, streamed with flat memory.

## Purpose
Excel's limit is per worksheet (1,048,576 rows), not per workbook. Today a larger Excel export is refused ('Use CSV instead'), and an upload reads only the first sheet, so a workbook split by its owner is cut silently (Erik's legal-unit file lost about 86,000 rows at the limit). If both directions can stream, people who live in Excel get every row.

## Principle
A spike: measure, then decide; no product commit until the owner chooses. Memory stays flat in both directions or the option is dropped. Rows are split evenly over the fewest sheets that hold them (2.1 M rows as 2 x 1.05 M, not 1.05 M + 1), so each sheet loads at a similar speed. A split is always announced: in the download's name or first sheet, and in the upload's check step.

## Details
Download: app/src/app/search/export/xlsx-stream.ts already streams one sheet with flat memory (1,048,575 rows in 17.5 s in Chromium under a 64 MB heap, inlineStr, no sharedStrings, fflate ZIP with native deflate-raw). Splitting means closing sheetN.xml at a row boundary and opening sheetN+1, plus N entries in workbook.xml; the route needs the total count up front (it already counts for the 413). Hard cap: fflate writes no ZIP64, so the whole workbook stays under 4 GiB (refusal code zip64). Upload: SheetJS (vendor xlsx) reads the whole workbook into memory and so does ExcelJS's in-memory reader in app/api/import/upload; a streaming reader means unzipping one sheet entry at a time (fflate Unzip) and a SAX pass over its XML, resolving sharedStrings, which Excel-written files use (unlike ours). Owner 2026-11-28: one ticket; measure complexity and memory; split evenly; reading one sheet at a time may not help if the whole file is unpacked.

## Depends on

## Acceptance
- [ ] Measured: a 2.1 M row export written as 2 even sheets, its peak JS heap and time in headless Chromium, and that Excel/LibreOffice opens it
- [ ] Measured: a streaming read of a 2-sheet, 2 M row Excel-written workbook (with sharedStrings), its peak heap and time against SheetJS's whole-file read of the same file
- [ ] A written recommendation with the complexity found (files and lines touched, risks), for the owner to choose build or drop; the choice recorded

## Notes
