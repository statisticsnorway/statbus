---
id: STATBUS-278
title: >-
  tracked-file-test-output: a pg_regress test writes a tracked source file as a
  side effect — a raced or killed run can leave corruption one git add from
  shipping
status: In Progress
assignee:
  - '@architect'
created_date: '2026-08-27 15:03'
updated_date: '2026-08-28 10:16'
labels:
  - testing
dependencies: []
priority: medium
type: bug
ordinal: 271000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: no test run — raced, killed, or healthy — may leave a TRACKED source file corrupted without a loud refusal before it can ship. Today one test writes a tracked file as a side effect, and nothing checks what it wrote.

THE EXPOSURE, verified at current line numbers (2026-08-28): test/sql/016_generate_typescript_types_from_db.sql does \i on cli/sql/generate_database_types.sql (016:2), which carries `\o app/src/lib/database.types.ts` (generate_database_types.sql:1094) — so a pg_regress test writes a tracked source file every run. The NUL tripwire (dev.sh:808 check_results_for_nul_corruption) covers test/results/ ONLY; tracked files a test writes are unguarded.

WHY IT MATTERS, demonstrated not hypothesized: during the rc.10 straggler-race forensics (2026-08-27), exactly this file was corrupted with 507,904 page-aligned NULs — the 286 signature — and only the engineer's manual inspection stood between that corruption and a commit. 282's single-writer machinery has since closed the leading producer, but the EXPOSURE is independent of any particular producer: a tracked file writable by a test is one git add from shipping whatever the last run left in it.

TWO FIX SHAPES, architect to rule (the engineer offered to draft either):
(a) WIDEN THE TRIPWIRE: extend the NUL check to every tracked file the suite writes. The set is enumerable — grep test/sql plus included scripts for \o targets outside test/ — and the check runs where the results check already runs.
(b) REMOVE THE EXPOSURE: 016 writes a results-side artifact instead, and `./sb types generate` remains the ONLY writer of the tracked file. The test then compares its artifact against the tracked file (drift detection stays) without ever holding the pen.
Or both. (b) removes the hazard by construction rather than alarming on it — but must not lose what 016 exists to prove (that generation from a live schema matches the committed types).

WHAT IS ACHIEVED: a corrupted or killed run can no longer leave poison in a tracked file that the next git add would ship; the only writer of generated source is the generator.
<!-- SECTION:DESCRIPTION:END -->
