---
id: STATBUS-274
title: >-
  test-isolation-prefix: isolation is keyed to the 4xx/5xx filename prefix,
  which also excludes a test from fast — the either/or is invisible until hit
status: Done
assignee:
  - '@architect'
created_date: '2026-08-27 13:51'
updated_date: '2026-08-28 22:35'
labels:
  - testing
dependencies: []
priority: low
type: enhancement
ordinal: 267000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Filed from the 265 gate-test review (architect, 2026-08-27). A pg_regress test gets database-per-test isolation ONLY via its numeric filename prefix (4xx/5xx, dev.sh:1031) — and that same prefix excludes it from the fast tier. So "isolated AND fast" is impossible, and nothing says so: the 094 exemption test needed both, took fast, and mitigated the shared-database hazard by hand (proven cleanup with a fresh-session assertion). The next test needing both will hit the same invisible either/or.

Fix: decouple isolation from the numeric prefix (e.g. an explicit marker the runner reads), so tier and isolation are independent choices. Small change in dev.sh's runner; the 094 file can then opt into isolation without leaving the gate.

WHAT IS ACHIEVED: a test chooses speed tier and isolation independently, and the constraint that forced 094's hand-mitigation is gone.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CLOSED at 6fc04ccc1 (dev.sh +69, 094's sql+out +17/−2 each). Built exactly to the architect's proposal, King-ratified via the finish-directive: isolation = 4xx/5xx prefix OR in-file marker; tier rule untouched; runner prints its decisions with reasons (or an explicit none); unrecognised marker value REFUSES loudly naming file/found/known — the typo-means-no-isolation failure the marker exists to prevent cannot happen silently. 094 opted in at the top of its file, keeps its cleanup (stakes changed, not hygiene), stays in fast, and is PROVEN live running from its own per-run database. Craft on the record: pg_regress echoes input, so both comment edits were mirrored into the .out BY HAND hunk-for-hunk (never --update-expected) and verified byte-identical; one line of 094's own prose corrected where the change made it untrue. Demo transcript shows all three arms against the shipped decision block extracted verbatim. bash -n clean, shellcheck delta zero. Also on the record: the engineer's 'starting 274 now' was followed by an idle hour of nothing — owned plainly in his report; the foreman's status check caught it.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-28 10:18
---
**PROPOSAL for the King's review.**

A test that needs its own database cannot also be a fast test, and nothing says so — you find out by having corrupted your neighbours. This proposes one small change to the test runner that separates those two questions, changes nothing that exists today, and makes the runner say out loud what it decided.

## What is actually wrong

The test filename carries **two unrelated facts at once**, and they are welded together.

A number in the 4xx or 5xx range means *"this is a large import test"* — so `./dev.sh test fast` skips it. The same number **also** means *"give this test its own database"* instead of sharing one with everything else. Those coincide for large imports, which are both slow and need privacy. They are not the same question.

So a test that is **cheap but must not share a database** has nowhere to live. Test 094 is exactly that: it switches the whole database to read-only to prove the upgrade guard behaves, which would wreck every test sharing that database with it — but it runs in 19 milliseconds and belongs in the fast tier. It was written as an ordinary fast test with a page of careful hand-cleanup holding the line. **That cleanup is currently load-bearing for the entire suite.**

## The change

A line inside the test file, which the runner reads before deciding how to run it:

```sql
-- test-isolation: database-per-test
```

The runner's rule becomes: *a test gets its own database if its number is 4xx/5xx **or** it carries that line.* The fast/slow rule is untouched.

That is the whole mechanism. A cheap test can now also be a private one, which today is impossible.

## Why the marker goes in the file, and not in a list

A list of isolated tests kept somewhere else is a second place that has to agree with the first. Rename or move a test and it silently loses its privacy — and the punishment is that it quietly corrupts its neighbours on the next run. **A file cannot fall out of step with itself.** Anyone reading the test sees the declaration next to the code that needs it.

And not a new filename convention: the filename is already overloaded with two meanings, which is the problem. Adding a third would be more of the same.

## Nothing existing changes

Every current test behaves exactly as it does now. The 4xx/5xx rule keeps working; the marker only adds a second way to ask for the same treatment. No test is renamed, no run changes, until someone opts in.

## The runner says what it did

Today the decision is invisible — that is really the complaint. The runner should print, at the start of a run, which tests it is giving their own database and why:

```
isolated: 094 (marker), 401 (prefix), 402 (prefix), …
```

One line. It makes a silent decision checkable, and a test that meant to opt in but is missing from the list is visible immediately.

**And a mistyped marker must refuse, not be ignored.** If the runner sees a `-- test-isolation:` line it does not recognise, it should stop and say so. A typo that silently means "no isolation" would reproduce the exact failure this fixes.

## Test 094 opts in, and keeps its cleanup

It gets the marker and stays in the fast tier. **Its cleanup stays** — a test should leave the world as it found it regardless. What changes is the stakes: today a cleanup failure in 094 would leave the shared database read-only and fail every test after it; afterwards it can only affect itself.

One thing to check when opting it in: 094 reconnects mid-test, and its expected output must not start containing the per-run database name. It was already written carefully to avoid that, so this is a verification, not expected work.

## Cost and risks, honestly

- **Cost:** each marked test adds one database clone — seconds, using the same cloning the 4xx/5xx tests already do.
- **Risk:** someone marks a test and mistypes it. Handled by the refuse-on-unrecognised rule and the printed list.
- **Not solved by this:** it does not stop a test from needing isolation without knowing it. It gives an author who *does* know a way to say so — which today they do not have.

## What is achieved

A test can be both fast and private, which is impossible today; the runner states which tests it isolated rather than deciding silently; and 094's careful hand-cleanup stops being the only thing protecting the rest of the suite.
---
<!-- COMMENTS:END -->
