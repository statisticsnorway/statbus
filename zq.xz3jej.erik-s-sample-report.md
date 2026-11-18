---
id: xz3jej
title: "Data quality: legal units whose largest establishment has another activity"
state: "doing"
type: feature
priority: ""
assignee: ["hibiscus"]
labels: []
created: 2026-11-18
updated: 2026-11-18
doing_since: "2026-11-18T00:59"
stage: "waiting"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus"
waiting_asked_by: "hibiscus"
waiting_for: "jhf"
waiting_on: "the owner reviews the design and rule in Relevant details (check 1) in the morning"
waiting_since: "2026-11-18T01:37"
---

## Goal
The dashboard's Data quality section shows how many legal units have a largest establishment (most employees) whose primary activity differs from the legal unit's, and links to the search listing exactly those units, for the selected time frame.

## Purpose
A legal unit's activity usually follows its main establishment; when they differ, one of the two is likely wrong. Erik asked this question in PR #328 (https://github.com/statisticsnorway/statbus/pull/328, rsbssbno, 2026-11-15) as a standalone HTML page.

## Principle
Built into StatBus, not beside it (owner 2026-11-18): it lives in the app, uses the signed-in session's JSON web token like every other page, and sits with the existing data-quality cards. No standalone pages, no API keys in local files, no ad hoc code under doc/integration. PR #328 is closed, not merged; its question is what is kept.

## Relevant details
Existing pattern: app/src/app/dashboard/page.tsx, section 'Data quality', with MissingRegionCard and MissingActivityCategoryCard (app/src/app/dashboard/missing-*-card.tsx): each counts legal units and establishments existing at the selected frame's date (lib/unit-existence.ts) through getBrowserRestClient, and links to /search with a filter. The new card needs a search filter that lists the same units, so the comparison must be computable in the database (a column or a function), not in the browser.

What the run of PR #328 showed on the Norway restore (local, 2026-11-18): 10,129 legal units have more than one establishment; 1,826 of them have a largest establishment with another activity (ties broken by lowest unit id). The rule for ties matters: 1,911 legal units have two or more establishments tied for the most employees, and 1,749 have a largest establishment with 0 employees. The page also fetched only 5,000 legal units and compared activities by name.

Design (2026-11-18, for the owner's review): a PostgREST computed field, the pattern the owner built for unit existence (STATBUS-460, a64f4ad38: public.existence_from(statistical_unit) / existence_until(statistical_unit), filtered as existence_from=lte.<d>). A function on the row type, unnamed parameter so it is not an RPC, is a virtual column: the card counts with it, the search filters with it, and an AI or a person can write the URL: /rest/statistical_unit?unit_type=eq.legal_unit&activity_differs_from_main_establishment=is.true&existence_from=lte.<d>&existence_until=gt.<d>.
- public.activity_differs_from_main_establishment(statistical_unit) RETURNS boolean, LANGUAGE sql, STABLE. NULL for any row that is not a legal unit with more than one included establishment; otherwise true when none of its main establishments has the legal unit's primary activity category (compared by id).
- Main establishments: those, valid at the legal unit row's valid_from, with the most employees (stats_summary employees sum), when that most is above 0. Ties are not broken at random: if any tied main establishment shares the activity, the legal unit is not flagged. With 0 employees everywhere there is no main establishment and the result is NULL (not flagged).
- On the Norway restore this rule flags 1,461 of the 8,380 legal units that have a main establishment (tmp/hug/xz3jej-rule.sql); the PR's page found 1,240 of its first 5,000.
- App: app/src/app/dashboard/main-establishment-activity-card.tsx, a copy of missing-activity-category-card.tsx (estimated count, exact on request, selected frame through existence_from/until), placed in page.tsx's Data quality section and linking to /search?unit_type=legal_unit&activity_differs_from_main_establishment=true. The search learns that one filter the way Rabbit's unmerged STATBUS-625 card does for physical_location (statbus_test 09c52b2a1: url-search-params.ts, atoms/search.ts, useSearchUrlSync.ts, SearchResults.tsx); whichever lands second follows the first.
- Not here: making reports configurable (which cards a country shows) and a way for others to add their own reports, both owner ideas 2026-11-18, each its own task.

Build plan, after the owner approves the rule (check 1), each step its own commit with the Model: trailer:
1. SQL test first (test/sql/, next free number): legal units with one main establishment of another activity (flagged), same activity (not), a tie with one match (not), all establishments at 0 employees (NULL), a single establishment (NULL), an establishment of a later period (ignored). RED before the migration.
2. Migration with up and down: the function, COMMENT ON stating the rule, grants as existence_from has. GREEN; fast suite; ./dev.sh generate-doc-db; ./sb types generate.
3. Card and search filter, with a jest test that the URL filter reaches the query; tsc, lint, jest, build.
4. Check on the local Norway data: card count equals the SQL count for the Live frame; the link lists the same legal units. Show the owner in Firefox before pushing.

## Depends on

## Acceptance
- [ ] [Owner] Decides the rule: which establishments count (all, or only those with employees), how ties on employees are broken, and whether the legal unit is compared with its largest establishment or with the activity most of its employees work in; the answer is recorded in the notes
- [ ] A SQL test asserts, for a fixed set of units, which legal units the rule lists, including a tie and an establishment with 0 employees
- [ ] The Data quality section shows the card with the count for the selected time frame, and its link opens a search listing exactly those legal units (checked against the SQL on the local Norway data)
- [ ] PR #328 is closed on GitHub with a comment that thanks Erik, says why (integrated in the app instead), and links this task


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
2026-11-18 00:08 owner: PR #328 is the wrong shape: an ad hoc JavaScript page under doc/integration, outside the app, not using the session's JSON web token. The question belongs in the app as a card in the dashboard's Data quality section, beside Units Missing Region and Units Missing Activity Category (owner screenshot of https://local.statbus.org:3011 dashboard, Norway data: 101,680 missing region, 186,347 missing activity category). Task rewritten to that; type feature.
2026-11-18 00:36 plan for the owner's morning review: design and build plan are under Relevant details. Waiting for the owner (check 1, the rule). Agreed with the owner: no comment on PR #328 yet; in the morning, after hug's new release, the improved design goes in this task and the PR gets a comment linking it; the PR is closed later. Two more tasks to create when the owner says: configurable reports, and a way for others to add their own reports. Erik's page server on :8328 stopped.
## History
- 2026-11-18T00:59 todo -> doing/active (take)
- 2026-11-18T01:37 doing/active -> doing/waiting (wait)
