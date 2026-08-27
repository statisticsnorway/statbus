---
id: STATBUS-278
title: >-
  tracked-file-test-output: a pg_regress test writes a tracked source file as a
  side effect — a raced or killed run can leave corruption one git add from
  shipping
status: To Do
assignee: []
created_date: '2026-08-27 15:03'
labels:
  - testing
dependencies: []
priority: medium
type: bug
ordinal: 271000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found during the rc.10 straggler-race forensics (2026-08-27): test/sql/016_generate_typescript_types_from_db.sql does \i on cli/sql/generate_database_types.sql, which carries `\o app/src/lib/database.types.ts` (line 1094) — a pg_regress test writing a TRACKED source file as a side effect. The straggler race corrupted it with 507,904 page-aligned NULs, and only the engineer's inspection stood between that and a commit: the NUL tripwire (dev.sh check_results_for_nul_corruption) covers test/results/ only; nothing guards tracked files a test writes.

Design question for the architect: extend the NUL tripwire to every tracked file the suite writes (enumerable — grep test/sql + included scripts for \o targets outside test/), or change 016 to write a results-side artifact and have ./sb types generate remain the only writer of the tracked file, or both. The engineer offered to draft; architect rules the shape.

WHAT IS ACHIEVED: no test run — raced, killed, or healthy — can leave a tracked source file corrupted without a loud refusal before it ships.
<!-- SECTION:DESCRIPTION:END -->
