---
id: j3sdc8
title: "Norway: 464 244 legal unit names stored double-encoded (BÃ…TSFJORD)"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "zzzzzzzzzzzv"
created: 2026-11-27
updated: 2026-11-27
---

## Goal
Legal unit names on Norway read as written, and the upload path reads or refuses files whose encoding it would misread.

## Purpose
On the Norway copy restored 2026-11-26, 464 244 of 2 190 793 legal unit names carry UTF-8 bytes read as Latin-1 (Å stored as 'Ã…'), all written by import jobs 10 and 11 (legal_unit_job_provided, 2026-11-13, 1 048 575 rows each). Establishments have none. Search, reports and exports show the garbled names.

## Principle
Find which step decoded the file wrongly before repairing data; repair Norway's rows only after the owner decides, and make the upload path refuse or correctly read such files (as bysgyd did for the demo CSV).

## Details
Measured on my slot: legal_unit.name LIKE '%Ã%' 464 244 rows, all edit_at 2026-11-13; proper ÆØÅ names 11 794 (2026-11-08..13). Check whether no.statbus.org has the same, and the uploaded file's encoding (BRREG export, ISO-8859-1 vs UTF-8). Related: bysgyd (demo CSV encoding), demo-files-upload.test.ts.

## Depends on

## Acceptance
- [ ] On the Norway copy, no legal unit name contains UTF-8 decoded as Latin-1 ('Ã' sequences)
- [ ] An upload test with a UTF-8 file declared or detected as Latin-1 shows the names correctly or refuses the file with a message naming the encoding

## Notes
