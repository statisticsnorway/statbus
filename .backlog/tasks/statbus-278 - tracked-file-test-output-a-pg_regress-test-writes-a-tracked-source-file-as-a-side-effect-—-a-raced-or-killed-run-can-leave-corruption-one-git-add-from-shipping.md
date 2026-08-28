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
updated_date: '2026-08-28 10:18'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-28 10:18
---
**RULING: (b), and NOT (a). But (b) understates itself — it is not "remove the exposure", it is correcting a category error. Plus one guard that is not a widened tripwire.**

## A test must not write a tracked file, corruption or no corruption

A test observes and asserts. Writing `app/src/lib/database.types.ts` makes 016 a **mutator of the repository**: running the suite edits source, every developer's `git status` depends on whether they ran tests, and a tracked artifact sits inside the blast radius of anything that goes wrong mid-run. **The corruption is what made this visible; it is not what makes it wrong.** That is why (b) is the fix even if the NUL mechanism were solved tomorrow.

## (b) does not weaken what 016 proves — it STRENGTHENS it

This is the part worth being precise about, because the ticket frames it as something to protect.

**Today the proof is a side effect.** 016 overwrites the tracked file; if live-schema generation disagreed with the committed types, the evidence is that the working tree is now dirty — and someone has to notice. Nothing fails. It is proof by leftover.

**Under (b) it becomes an assertion.** Generate to a results-side artifact, diff against the tracked file, fail on mismatch. The suite reports the disagreement instead of quietly embodying it — and `./sb types generate` remains the single writer, which is the property that should have held all along.

**So the requirement "must not lose what 016 proves" is satisfied twice over: (b) proves the same thing, and proves it loudly.**

## Why NOT (a)

Widening the tripwire to every tracked file the suite writes **accepts the premise that the suite writes tracked files** and adds detection around it. That is defensive cover over a path that should not exist — and it grows: every future test that writes a tracked file must be remembered and added. Remove the class instead of instrumenting it.

## The guard that SHOULD be added — and it is not a tripwire

Removing 016's write fixes today. Nothing stops the next test from doing the same thing next month, and the failure is silent again.

**A `\o` grep is the wrong guard.** It catches one write mechanism while `\copy … TO`, `COPY … TO`, and `\!` are all still available — a partial check that would read as total, which is the defect I have flagged three times this week.

**Guard by observation instead, which is mechanism-independent:** snapshot `git status --porcelain` before the suite, compare after, and **fail if any tracked file gained a modification during the run.** It cannot be spelled past, it needs no enumeration of write syntaxes, and it catches a mechanism nobody has thought of yet. Compare before-and-after rather than requiring a clean tree, so a developer's own uncommitted work does not trip it.

## Do this first

**Enumerate the tracked-file writers before assuming 016 is alone** — `\o`, `\copy … to`, `COPY … TO`, `\!` across `test/sql/`. If others exist they take the same treatment; if 016 is the only one, say so in the commit, because that sentence is what makes the observation guard's scope credible afterwards.

## Who

**Mechanic.** The design above is complete and the work is mechanical: redirect one `\o`, add a comparison, add a before/after tree check. The engineer is on 279's runs and 286 surveillance and should stay there.
---
<!-- COMMENTS:END -->
