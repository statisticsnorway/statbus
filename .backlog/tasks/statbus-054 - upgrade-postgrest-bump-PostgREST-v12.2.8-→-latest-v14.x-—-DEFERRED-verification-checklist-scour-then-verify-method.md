---
id: STATBUS-054
title: >-
  upgrade-postgrest: bump PostgREST v12.2.8 → latest (v14.x) — DEFERRED;
  verification checklist + scour-then-verify method
status: To Do
assignee: []
created_date: '2026-06-15 11:47'
updated_date: '2026-07-12 21:43'
labels:
  - upgrade
  - postgrest
  - dependencies
  - deferred
dependencies: []
references:
  - docker-compose.rest.yml
  - docker/compose/upgrade-sandbox.yml
  - 'https://github.com/PostgREST/postgrest/blob/main/CHANGELOG.md'
ordinal: 54000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: stay current on PostgREST (v12→v14) without breaking a single query.
> BENEFIT: we get off an aging pinned version (v12.2.8) onto the supported line — future security patches and features reachable — with the one known breaking change (#4075 aliased-embed filters) scoured and verified BEFORE the bump instead of discovered in production.
> STAGE: post-Norway parallel lane. (110's role exemption is version-independent — nothing blocks on it.)
> COMPLEXITY: mixed, King-specified split — operator scours app/src and reports candidates (stage 1); architect/engineer verify each (stage 2); mechanic bumps the two compose tags; tester runs the suite + smoke.
> DEPENDS ON: nothing — deferred by the King's explicit "stabilize first" call, not by a ticket.

---

King decision 2026-06-15: FILE NOW, DO LATER — "we'll do that later; now we need to stabilize what we have." This item captures BOTH the bump and exactly what to check beforehand so we know whether it can fail.

## The bump (mechanical — one line)
We are pinned to `postgrest/postgrest:v12.2.8` (docker-compose.rest.yml:5; also docker/compose/upgrade-sandbox.yml). Latest stable = PostgREST 14.x (v13 is a dev line — PostgREST releases only even majors). The change itself is the image tag in those two files.

NB: bumping to v14 does NOT get us the `postgrest --ready` CLI healthcheck flag — that is only in PostgREST's unreleased dev branch (PR #4269). So the reason to bump is "stay current," not the STATBUS-032 healthcheck.

## What to check to know if it CAN fail or CANNOT fail (verify against the real CHANGELOG, not this summary)
PRE-CLEARED (foreman checked our docker-compose.rest.yml env against the v13/v14 changelog):
- Removed/renamed config we do NOT set: `db-pool-timeout` (→ db-pool-max-idletime), `jwt-cache-max-lifetime` (→ jwt-cache-max-entries), `log-query` (now boolean), admin `/config` endpoint + `admin-server-config-enabled`. Our compose sets only: PGRST_DB_URI, DB_SCHEMAS, DB_ANON_ROLE, DB_USE_LEGACY_GUCS=false, JWT_SECRET, APP_SETTINGS_ACCESS/REFRESH_JWT_EXP, DB_AGGREGATES_ENABLED, JWT_AUD, OPENAPI_SERVER_PROXY_URI, DB_CONFIG, DB_PRE_REQUEST — none of the removed/renamed ones. ✓
- Dropped PostgreSQL EOL versions (13, and earlier 9.6/10/11): we run PostgreSQL 18. ✓

OPEN — code-level risk that needs the scour (this is "the dropped feature of the alias" the King named):
- #4075: "the name of an embedded table can no longer be used in filters if it has an alias." Our frontend leans hard on the `/rest` API, so the real question is: DO WE EVER build a PostgREST query that aliases an embedded resource AND then filters/orders on that alias? If yes, those calls break on v14 and need rewriting first.

PASSIVE behavior changes to be AWARE of (note, likely fine, confirm during the test run):
- All responses now carry a `Vary` header (#4609).
- Schema-cache failures no longer stop request serving (best-effort) (#4873) — arguably an improvement.
- Automatic transaction retries on serialization failures removed (#3673) — confirm we don't rely on PostgREST retrying serialization failures.

## The check METHOD (King-specified, 2026-06-15) — two stages, do NOT collapse them
STAGE 1 (operator, cheap legwork — REPORT, do not decide): scour the source for the #4075 pattern. Primary target: app/src (the Next.js frontend, where `/rest` queries are constructed — PostgREST select/embed strings, supabase-style query builders, raw `?select=...` URLs). Look for an aliased embed (e.g. `alias:related_table(...)` in a select) used together with a filter or order on that alias. REPORT every candidate location (file:line) where this pattern appears OR where there is DOUBT — do not judge whether it actually breaks. Also flag any spot relying on serialization-retry behavior.
STAGE 2 (architect/engineer — verify): go over each reported candidate and confirm whether it is genuinely an aliased-embed-in-filter that #4075 breaks; list the ones needing a rewrite.

## Then (when we actually do it, later)
- Rewrite any confirmed #4075 sites.
- Bump the tag in docker-compose.rest.yml + docker/compose/upgrade-sandbox.yml.
- Test locally: restart the rest container on v14, run the test suite, smoke-test the app (the real test is "do all our queries still return the same thing," not "does it boot").
- Confirm the exact latest v14 patch version at upgrade time.

DEFERRED — not now. Stabilize the current install/upgrade surface first.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 STAGE 1 done: an operator has scoured app/src (+ any other /rest query construction sites) and REPORTED every candidate location (file:line) of an aliased-embed-used-in-a-filter/order (#4075), plus any serialization-retry reliance — surfacing doubt, not deciding
- [ ] #2 STAGE 2 done: a smarter agent (architect/engineer) verified each candidate and produced the definitive list of sites that #4075 actually breaks (or confirmed none)
- [ ] #3 Any confirmed #4075 sites rewritten to not alias-then-filter
- [ ] #4 PostgREST bumped to the confirmed latest v14.x tag in docker-compose.rest.yml + docker/compose/upgrade-sandbox.yml; rest container restarts clean on v14
- [ ] #5 Tested: full suite green + app smoke-test passes on v14 (queries return the same results); passive behavior changes (Vary, schema-cache best-effort, serialization-retry) confirmed harmless
<!-- AC:END -->



## Comments

<!-- COMMENTS:BEGIN -->
author: operator (relayed by foreman)
created: 2026-07-12 21:43
---
STAGE 1 SCOUR COMPLETE (operator, 2026-07-12 night). Scope: app/src, 445 TypeScript files. ONE confirmed PostgREST #4075 breaking-change risk found:

app/src/atoms/import.ts:240-242 — `.select("*, import_definition!inner(*)")` followed by `.eq("import_definition.mode", mode)`: the filter references the aliased embed name, which PostgREST v14 (#4075) forbids. Required fix direction: drop the alias modifier from the embed used in the filter, or restructure so the filter does not target the aliased name.

Clean findings: no reliance on the removed automatic serialization-failure retry; no other #4075 patterns (other FK embeds either carry no alias modifier or never filter on the alias); all other query patterns v14-compatible.

Stage 2 = verify the one site against v14 semantics and rule/execute the rewrite.
---
<!-- COMMENTS:END -->
