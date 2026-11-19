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
- [x] A file with invalid UTF-8 bytes is refused at upload with a message naming the encoding problem; no row is staged; a test uploads such a file
- [x] A UTF-8 file whose text shows the read-as-Windows-1252 pattern (Ã followed by ˜, …, † and the like) is refused the same way, with the first offending line and value in the message; a test covers it
- [x] A correct UTF-8 file with Ø, Å and Æ imports unchanged; a test covers it
- [x] [Owner] Decides whether the 454,278 garbled rows on Norway are repaired (and how) or re-imported; the answer is recorded in the notes

## Notes


2026-11-19 owner decisions (design discussion):
- Refuse, during the upload: a file with invalid UTF-8 bytes or with the read-as-Windows-1252 pattern never reaches the import step; the upload's transaction rolls back, nothing is staged, the job stays waiting for a file.
- Where: on the server, in the upload route, on every byte as it streams to COPY (covers CSV and Excel, which the browser converts to CSV). A browser-side check at the preview adds nothing worth its cost today: the upload is fast, and the server check is the one that decides. Revisit only if a client-side upload with progress is built.
- Check 4: the 454,278 garbled rows on Norway are repaired by the repopulation of the instance in rabbit's task senzch (note added there), not here.
check 1: dcbad72ed: a Windows-1252 file uploaded through /api/import/upload on the local slot is refused with 400 'The file is not UTF-8: line 3 has bytes that are not valid UTF-8 (D8 52 53) in "RØ". Save the file as UTF-8...'; its upload table has 0 rows and the job stays waiting_for_upload (master: 500 'invalid byte sequence'). Unit tests upload-encoding.test.ts cover it in 1, 5 and 1000-byte chunks.
check 2: dcbad72ed: a UTF-8 file with '24T RÃ˜RSERVICE AS KONKURSBO' on line 3 is refused with 400 naming line 3, the value and what it was ('24T RØRSERVICE AS KONKURSBO'); 0 rows staged (master: 200 and the garbled row staged in import_job_19_upload). Unit tests cover Ø, Å, Æ, ø, å, ��, é garbled.
check 3: dcbad72ed: a UTF-8 file with RØRSERVICE, BLÅBÆR ÆRØ and SÃO PAULO uploads with 200 and its 3 rows are staged with the names unchanged (tmp/hug/e1z8va-e2e-db.out); unit tests pass it in chunks of 1 byte to whole file, with BOM and CRLF.
2026-11-19 timing: the check alone takes 0.12 s on a 58 MB file of 1,048,574 rows (Erik's file size), in 64 KB chunks (tmp/hug/e1z8va-timing.log). Full jest 488/488. The nine test jobs on the local Norway copy (import_job_14 to _22) were deleted after the test; none produced units.
## History
- 2026-11-19T16:39 todo -> doing/active (take)
