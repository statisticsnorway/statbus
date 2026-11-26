---
id: f69jcx
title: "Download menu states the row count once; a finished download is a notification"
state: "doing"
type: feature
priority: ""
assignee: ["rabbit"]
labels: []
group: ""
rank: "zzzzzzzzzzzn"
created: 2026-11-26
updated: 2026-11-26
doing_since: "2026-11-26T11:50"
doing_with: "ca6dk5"
stage: "active"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus"
---

## Goal
Download menus state the row count once with CSV and Excel as equal choices, and a finished download is a toast.

## Purpose
Owner's review 2026-11-26 08:52: the CSV item shows the row count and the Excel item does not, though both download the same rows; and 'Downloaded N rows in 9s' stays in the toolbar after the download is done.

## Principle
One statement of what is downloaded (the rows), formats as equal choices. Progress and Cancel stay at the button while running; a completed download is an event, so it is a toast like the app's other confirmations. Errors stay at the button until dismissed, since they must be read.

## Details
Search: app/src/app/search/components/search-export-csv-link.tsx and export/use-statistical-unit-export.ts. Same pattern: components/statistical-unit-details/unit-history-export-button.tsx, components/progress-download-button.tsx (import data). Toast from @/hooks/use-toast.

## Depends on

## Acceptance
- [x] On /search the Download menu shows the row count once above CSV and Excel (.xlsx), observed in a driven browser on the Norway copy
- [x] After a completed download a toast says 'Downloaded N rows in Ts' and the Download button carries no completion text
- [ ] Unit history and import data downloads show the same menu shape and the same toast

## Notes


check 1: Owner approved in Firefox 2026-11-26 12:25 on the Norway copy (local slot): search Download shows '11 010 rows' once above CSV and Excel (.xlsx).
check 2: Owner approved 12:25: CSV download ends with a toast 'Downloaded N rows in Ts' (download-menu-text.test.ts 6/6), the button carries no completion text.
## History
- 2026-11-26T11:50 todo -> doing/active (take with ca6dk5)
