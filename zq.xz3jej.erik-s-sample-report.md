---
id: xz3jej
title: "Erik's sample report: legal units whose top establishment has another activity"
state: "doing"
type: docs
priority: ""
assignee: ["hibiscus"]
labels: []
created: 2026-11-18
updated: 2026-11-18
doing_since: "2026-11-18T00:59"
stage: "active"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus"
---

## Goal
Erik's sample report from PR #328 is reviewed and lands in a form the owner approves: an HTML page listing legal units whose largest establishment (by employees) has a different activity category than the legal unit, with sorting, search and the establishments on expand.

## Purpose
A worked example of reading StatBus through its REST API for a real analysis question, which countries can copy (PR https://github.com/statisticsnorway/statbus/pull/328, rsbssbno, 2026-11-15).

## Principle
Erik's work is the starting point; the owner decides what lands. A sample stays outside the product: no app or schema change. Credentials stay out of git (config.js is ignored, config.example.js is the template).

## Relevant details
PR #328: doc/integration/javascript/legal_units.html (+~300 lines) and doc/integration/javascript/config.example.js; CI all green on 2026-11-15. Its own test plan: copy config.example.js to config.js with API URL and key, open the page, check loading, sorting, search and expand.

## Depends on

## Acceptance
- [ ] The page loads data from the local slot with an API key and shows legal units whose top establishment's activity differs, checked against a SQL query on the same database
- [ ] [Owner] Reviews the page and the code and decides: merge as is, merge with changes (made and shown again), or close; the answer is recorded in the notes
- [ ] The PR is merged or closed on GitHub as decided, with a comment that links this task

## Notes


2026-11-18 00:00 code review of PR #328 (head 2e1f3df23, one commit):
- What it does: one /rest/statistical_unit call for legal units with included_establishment_count > 1 and used_for_counting, ordered by establishment count, limit 5000; then the establishments in batches, region and activity names; the top establishment is the one with the most employees (stats_summary.employees.sum); a row is listed when the legal unit's activity NAME differs from the top establishment's.
- Safe rendering: cells use textContent, so unit names cannot inject HTML.
- Finding 1 (key leak): config.example.js and the page say config.js is gitignored, but on master nothing ignores doc/integration/javascript/config.js (git check-ignore: not ignored). The ignore rule came with PR #325 (map/), not this PR. Following the instructions would commit an API key.
- Finding 2: the page comment points at map/config.js, a leftover from PR #325; it loads ./config.js.
- Finding 3: limit=5000 caps the legal units silently; on Norway (1.18M legal units) the page shows only the first 5000 by establishment count and says nothing about the cap.
- Finding 4: no time frame: statistical_unit holds every period, so a unit can appear once per valid period; the query does not pick valid_on or the live frame.
- Finding 5: activities are compared by display name, not by id; a tie in employees picks whichever establishment comes first.
- Fits beside doc/integration/python and doc/integration/r (both read the API with a key from a local file).
2026-11-18 00:02 run on the local slot (Norway restore of 2026-11-16, headless Firefox-free Chromium via tmp/hug/328-run.mjs, API key from create_api_key, 1 hour): the page loads and says 'Found 1240 legal units with different activity on top establishment', 1240 rows. Reference SQL on the same database (tmp/hug/328-reference.sql): 10,129 legal units with more than one establishment; 1,826 whose top establishment (most employees, ties broken by unit id) has another activity. The gap is how ties are broken, not missing data: 1,911 of the 10,129 have two or more establishments tied for the most employees, 750 of those ties decide the answer (some tied establishments share the legal unit's activity, some do not), and 1,749 have a top establishment with 0 employees, so the 'top' is arbitrary there (tmp/hug/328-name.sql). The page keeps the first establishment it meets in a tie; the SQL keeps the lowest unit id. All 80,751 establishments were fetched (no periods repeat in statistical_unit on this database), and 10,129 is under the page's limit of 5000? No: it exceeds it. See finding 3.
2026-11-18 00:02 correction to the note above (its last sentence was wrong): the cap explains the gap. The page fetches only the first 5000 of the 10,129 legal units with more than one establishment (limit=5000, ordered by establishment count), and says nothing about it. On those same 5000 (tmp/hug/328-capped.sql), the reference finds 1,242 whose top establishment has another activity; the page lists 1,240. The 2 left are ties on employees, which the page breaks by the order establishments arrive and the SQL by lowest unit id. So the page's logic is right; its result is incomplete on a register of Norway's size, silently.
## History
- 2026-11-18T00:59 todo -> doing/active (take)
