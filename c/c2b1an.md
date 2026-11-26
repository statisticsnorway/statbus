---
id: c2b1an
title: "Search table: names stored double-encoded show garbled (010 IDÃ‰LAB)"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "zzzzzzzzzzzx"
created: 2026-11-26
updated: 2026-11-26
---

## Goal
Unit names show as registered, e.g. 010 IDÉLAB, not 010 IDÃ‰LAB.

## Purpose
Seen 2026-11-26 in the search on the Norway copy: '010 IDÃ‰LAB HENRIK ALFHEIM' and '0-100GOLF-TRENER HÃ...MO'. Either the source file was double-encoded or an import path misread it; the upload check (e1z8va) now refuses such files, but rows already stored stay garbled.

## Principle
Find where the text went wrong before repairing it; repair stored data with a forward migration or a re-import, never by hand.

## Details
Norway copy in statbus_test slot. Check BRREG's own value for org 928148424, and whether other installations have such rows (SELECT count(*) WHERE name ~ 'Ã').

## Depends on

## Acceptance
- [ ] The cause of the garbled names is recorded with evidence
- [ ] Stored garbled names are repaired or a re-import plan is approved

## Notes
