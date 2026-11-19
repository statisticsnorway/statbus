---
id: e1z8va
title: "An import upload refuses a file that is not UTF-8"
state: "doing"
type: bug
priority: "medium"
assignee: ["hibiscus"]
labels: []
group: ""
rank: "zzzh"
created: 2026-11-18
updated: 2026-11-18
doing_since: "2026-11-19T16:39"
stage: "active"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus"
---

## Goal
An import upload whose file is not valid UTF-8, or is UTF-8 that was once read as Windows-1252 (Ø stored as Ã˜), is stopped before any row is imported, with a message that names the problem and how to save the file as UTF-8.

## Purpose
On 2026-11-13 two Norway legal unit imports (import_job_10 and _11, 1,048,575 rows each, Excel's row limit) wrote names like '24T RÃ˜RSERVICE AS KONKURSBO': 454,278 legal_unit rows (227,139 units) on no.statbus.org now carry Ø, Å and Æ as two garbled characters. Nothing checked the file's encoding (owner 2026-11-18).

## Principle
Check at the upload, the earliest point, and refuse rather than guess or convert: the user fixes the file and uploads again. Repairing the rows already written is a separate decision for the owner.

## Relevant details
Upload route: app/src/app/api/import/upload/route.ts (COPY into the job's _upload table); no encoding check there or in app/src/app/import today. Garbled pattern seen: 'Ã' followed by ˜ … † ¥ ¦ ¸ © ¤ ¶ (UTF-8 bytes c3 83 cb 9c for Ø). Count query: tmp/hug/mojibake-count.sql (same counts on rune, read only). All 454,278 rows have edit_by_user_id = Erik Søberg, edit_at 2026-11-13.

## Depends on

## Acceptance
- [ ] A file with invalid UTF-8 bytes is refused at upload with a message naming the encoding problem; no row is staged; a test uploads such a file
- [ ] A UTF-8 file whose text shows the read-as-Windows-1252 pattern (Ã followed by ˜, …, † and the like) is refused the same way, with the first offending line and value in the message; a test covers it
- [ ] A correct UTF-8 file with Ø, Å and Æ imports unchanged; a test covers it
- [ ] [Owner] Decides whether the 454,278 garbled rows on Norway are repaired (and how) or re-imported; the answer is recorded in the notes

## Notes


## History
- 2026-11-19T16:39 todo -> doing/active (take)
