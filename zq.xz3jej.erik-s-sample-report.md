---
id: xz3jej
title: "Data quality: legal units whose primary establishment has another activity"
state: "doing"
type: feature
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
The dashboard's Data quality section shows how many legal units have a primary establishment whose primary activity differs from the legal unit's, and links to the search listing exactly those units, for the selected time frame.

## Purpose
A legal unit's activity usually follows its primary establishment; when they differ, one of the two is likely wrong. Erik asked this question in PR #328 (https://github.com/statisticsnorway/statbus/pull/328, rsbssbno, 2026-11-15) as a standalone HTML page.

## Principle
Built into StatBus, not beside it (owner 2026-11-18): it lives in the app, uses the signed-in session's JSON web token like every other page, and sits with the existing data-quality cards. No standalone pages, no API keys in local files, no ad hoc code under doc/integration. PR #328 is closed, not merged; its question is what is kept.

## Relevant details
Existing pattern: app/src/app/dashboard/page.tsx, section 'Data quality', with MissingRegionCard and MissingActivityCategoryCard (app/src/app/dashboard/missing-*-card.tsx): each counts legal units and establishments existing at the selected frame's date (lib/unit-existence.ts) through getBrowserRestClient, and links to /search with a filter. The new card needs a search filter that lists the same units, so the comparison must be computable in the database (a column or a function), not in the browser.

What the run of PR #328 showed on the Norway restore (local, 2026-11-18): 10,129 legal units have more than one establishment; 1,826 of them have a largest establishment with another activity (ties broken by lowest unit id). The rule for ties matters: 1,911 legal units have two or more establishments tied for the most employees, and 1,749 have a largest establishment with 0 employees. The page also fetched only 5,000 legal units and compared activities by name.

Design (owner 2026-11-18 01:47, replacing the computed field of 00:54): a separate, hard-coded report table, derived after statistical_unit, linked to it by a NOT ENFORCED temporal foreign key so PostgREST embeds it as an ordinary relationship. No general report system before three instances.
- Rule (approved, check 1): a legal unit's primary activity category differs from that of its primary establishment (timeline_establishment.primary_for_legal_unit) valid at the statistical_unit row's valid_from; compared by id, a missing activity on one side counting as a difference. Uses the primary as recorded and never picks one (choosing the primary is 2gpcs7). Covers every legal unit with a primary establishment; narrowing is a URL filter on existing columns, e.g. &included_establishment_count=gt.1 for Erik's variant.
- Table public.primary_establishment_activity_differs (name to confirm), one row per flagged statistical_unit row: unit_type, unit_id, valid_from, valid_until, valid_range (as statistical_unit has it), legal_unit_activity_category_id, primary_establishment_id, primary_establishment_activity_category_id. Primary key (unit_type, unit_id, valid_from). COMMENT ON the table states the rule.
- Link: FOREIGN KEY (unit_type, unit_id, PERIOD valid_range) REFERENCES statistical_unit (unit_type, unit_id, PERIOD valid_range) NOT ENFORCED (PostgreSQL 18). Metadata only: no triggers or checks, so derive rewrites statistical_unit as before; PostgREST reads it as a relationship. Without it PostgREST needs a computed relationship, which it counts with EXISTS per statistical_unit row (4.4 s on Norway); with it the count is a join from the report rows (111 ms).
- Derived: a _def view holds the rule; public.primary_establishment_activity_differs_derive() MERGEs it into the table; worker.derive_used_tables calls it after statistical_unit_flush_staging, beside the *_used tables. Between a flush and that step a changed row drops out of the inner join instead of showing wrong data.
- Read access like activity_category_used: RLS, regular_user and authenticated read, admin_user manage.
- Use: /rest/statistical_unit?select=name,...,primary_establishment_activity_differs!inner(primary_establishment_id)&unit_type=eq.legal_unit&existence_from=lte.<d>&existence_until=gt.<d>; the card counts the same with limit=0 and Prefer: count=estimated.
- On the Norway restore: 753,145 legal units have a primary establishment; 11,010 of them differ (tmp/hug/xz3jej-primary.sql). Full rebuild by one join 6.0 s; derive_used_tables averages 3.4 s today, derive_statistical_unit 219 s.
- App: app/src/app/dashboard/primary-establishment-activity-card.tsx, a copy of missing-activity-category-card.tsx, in page.tsx's Data quality section, linking to the search with a URL filter that adds the inner embed. The search learns that one filter the way Rabbit's unmerged STATBUS-625 card does for physical_location (statbus_test 09c52b2a1); whichever lands second follows the first.
- Not here: configurable reports (217dx5), user-made reports (rws25b), fixing what the check finds (xhxnsy).

Build plan, on branch statbus-xz3jej-primary-est-activity, each step its own commit with the Model: trailer; master after the owner's review:
1. Prototype on Norway: rebuild cost of the MERGE, a changed row dropping out and coming back, regular_user access and the app's real search request with the embed.
2. SQL test in test/sql/306_load_demo_data.sql after block 1: the report rows on the demo data and the embed's count. RED before the migration.
3. Migration with up and down: table, foreign key, view, derive function, RLS and grants, derive_used_tables calling it. GREEN; fast suite; ./dev.sh generate-doc-db; ./sb types generate.
4. Card and search filter, with a jest test that the URL filter reaches the query; lint, format, tsc, jest, build.
5. Check on the local Norway data: the card's count equals the SQL count for the Live frame; the link lists the same legal units.

## Depends on

## Acceptance
- [x] [Owner] Approves the rule: compare a legal unit's primary activity with its primary establishment's (primary_for_legal_unit), every legal unit with one, narrowing by URL filter; the answer is recorded in the notes
- [ ] A SQL test asserts, on the demo data in 306, which legal units the report table lists after derive, and that the search's embed counts the same units
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
2026-11-18 00:48: related tasks created by the owner's wish: configurable reports 217dx5 (which checks the dashboard shows), user-made reports rws25b (is a report just a saved query; spike), Workflows xhxnsy (fixing what a check finds through a reviewed import job).
2026-11-18 00:54 owner: likes the design (primary-establishment rule, computed field, card + search filter) and asks for it to be built by morning. Built on a branch, not master, so it stays out of the release candidate under discussion; the owner reviews in the morning, then it lands.
2026-11-18 01:19 owner decisions tonight, and a throwaway prototype for the morning (nothing kept; the local table and function were dropped again).

Decisions (owner 01:05-01:17): a per-row function is a lookup per legal unit (not inlined: the plan shows a Filter calling the function, a correlated subquery per row). PostgREST cannot compare two columns in a URL, so some function is needed either way. Do not generalise before three instances: for this check, a separate hard-coded table with its own columns is fine, joined from the search; no unified report table yet. Report SQL lives in migrations, not as stored user SQL.

Measured on the Norway restore (local, 2,190,793 statistical_unit rows, 1,134,475 legal units existing on 2026-11-18):
1. Today's per-row computed field (uncommitted migration 20261118005627, reading timeline_establishment): exact count 11,010 in 4.4-5.4 s through the REST API; estimated count 262,057 (24x too high) and no faster; search first page 59 ms.
2. Separate report table (prototype tmp/hug/xz3jej-proto-api-up.sql): public.<report>(unit_type, unit_id, valid_from, valid_until, legal_unit_activity_category_id, primary_establishment_id, primary_establishment_activity_category_id), PK (unit_type, unit_id, valid_from). Built by one set-based join in 6.0 s, 11,010 rows, 1.1 MB. Reachable from the search only through a PostgREST computed relationship (a SETOF function on statistical_unit), because statistical_unit's temporal key is not a foreign-key target: PGRST200 without it. With it, /rest/statistical_unit?select=name,<report>!inner() works; first page ordered by name 52 ms; but the count is still 4.4 s, because PostgREST evaluates the embed as EXISTS per statistical_unit row (1,134,475 index probes). Starting from the report table instead, the same count is 117 ms (tmp/hug/xz3jej-proto-plan2.sql).
3. Columns on statistical_unit (primary_establishment_id and its activity, filled in derive) plus a two-column computed field: not prototyped; expected near the 0.8 s base count since the comparison reads one row with no lookup.

So for a fast card: either the card counts from the report table itself (117 ms) and the link uses the embed for the list (52 ms first page), or the comparison lives on statistical_unit's own row. The owner decides in the morning. Uncommitted on branch statbus-xz3jej-primary-est-activity: the migration and a 306 test step (the step must move after 306's block 1, where legal units with establishments exist).
2026-11-18 01:42 owner asked whether a function can fake the connection for PostgREST. Two ways, both prototyped on the Norway restore (throwaway, dropped again):
1. Computed relationship (a SETOF function on statistical_unit, as before): PostgREST's own SQL, captured from pg_stat_monitor, counts with EXISTS (SELECT 1 FROM report_fn(statistical_unit)). PostgreSQL does not inline it, so it probes once per legal unit: 1,134,475 loops, 4.2 s. The same EXISTS written out as a plain join runs as a nested loop from the 11,010 report rows: 149 ms.
2. A NOT ENFORCED temporal foreign key (PostgreSQL 18): FOREIGN KEY (unit_type, unit_id, PERIOD valid_range) REFERENCES statistical_unit (unit_type, unit_id, PERIOD valid_range) NOT ENFORCED. It is only metadata (no triggers, no checks), so derive can still rewrite statistical_unit, and PostgREST reads it as a normal relationship with no function. Through the REST API, with select=name,<report>!inner(...): exact count 11,010 in 111 ms, estimated count 144 ms (now exact), name ilike *bygg* 627 rows in 196 ms, included_establishment_count=gt.1 2,451 rows in 115 ms, order=name 141 ms. The report table needs valid_range (copied from statistical_unit), because a temporal key must use PERIOD. Scripts: tmp/hug/xz3jej-fake-fk-up.sql, tmp/hug/xz3jej-proto-filters.sh.
Shared by every report-table design: the table is rebuilt after derive, and rows whose statistical_unit row has changed drop out of the inner join until the rebuild.
## History
- 2026-11-18T00:59 todo -> doing/active (take)
- 2026-11-18T01:37 doing/active -> doing/waiting (wait)
- 2026-11-18T01:54 answered waiting: "the owner reviews the design and rule in Relevant details (check 1) in the morning" -> "I approve this design. Hibiscus, can you get it done by morning.", by jhf, for hibiscus (doing/waiting -> doing/active)
- 2026-11-18T01:54 hibiscus read the answer
