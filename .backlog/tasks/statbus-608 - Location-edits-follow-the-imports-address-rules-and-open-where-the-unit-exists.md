---
id: STATBUS-608
title: Edits and imports are judged by the same rules
status: To Do
assignee: []
created_date: '2026-11-10T21:24:00Z'
updated_date: '2026-11-10T21:27:00Z'
labels:
  - ui
  - edit
  - location
dependencies: []
priority: high
type: bug
ordinal: 522204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## North Star
A value is valid or not by one set of rules, wherever it enters StatBus. An edit in the form, a write through the API and an import row are judged by the same rules, give the same messages on the same fields, and the database refuses what no rule allows.

## Zoom out
Owner testing on Norway (v2026.11.4-rc.01, 2026-11-10 21:21-21:26), adding a physical location to establishment 0404 GRUE TRAVKLUBB (org no. 933130436):
- With Region 03 Oslo and Country Åland Islands, and Valid From set to 2026-11-07, the save succeeded. Norway now stores location 2312602: physical, region 03, country AX, from 2026-11-07. An import refuses that row ("Region can only be supplied for the domestic country.").
- With Address part 1 only, or with Region 03 Oslo and no Country, the form refused with only "failed to parse form data for location". The import accepts both: region implies the domestic country, and no region and no country defaults to the domestic country.
- The country cannot be removed so that the region implies the domestic country (see STATBUS-610 for clearing selects).

The rules today live in three places that disagree:
1. Import analysis: import.analyse_location (dynamic SQL, migration 20260520141309) holds the region/country rules and their messages.
2. The edit form: locationSchema (app/src/app/legal-units/[id]/general-info/validation.ts) requires country_id and knows nothing else; its field messages do not reach the form.
3. The database: public.location has no rule for region versus country (only coordinate, altitude, postal and region_version checks).

Rows that break the import's rule (region with a non-domestic country), checked 2026-11-10 read-only: Norway 1 (2312602, the owner's test above), local statbus_local 1 (2315129, region 18 with TZ, edit comment "Jeg tester", 2026-05-09), dev/demo/et/jo/ma/mw/ug 0. All come from the edit form; no import produced one.

## Zoom in (to discuss with the owner before building)
- Where the rules live so that one definition serves all paths. Candidates: a database function per table that returns {field: message} for a candidate row, called by import analysis and by the edit path (an RPC the form calls before saving, and a trigger for the backstop); or table constraints for the hard rules with the messages mapped from the constraint name. The app stops carrying its own copy (no ad hoc rules).
- Which rules are hard (the database refuses) and which are warnings (stored, flagged), mirroring the import's fatal versus non-fatal split.
- The same treatment for the other temporal tables the form edits (contact, activity, stat_for_unit, the units' own columns), after location.
- Repair of the existing impossible rows in a forward migration before a hard rule lands (owner to decide: keep the region and set the domestic country, or drop the region).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 [Owner] Chooses where the shared rules live and which are hard versus warnings, after a walk-through of the candidates. The answer is recorded in this ticket's notes and becomes the build plan.
- [ ] #2 Location rules (region implies domestic; no region and no country defaults to domestic; region with a foreign country refused; postal needs no region) are defined once and used by both import analysis and the edit path; tests through each path assert the same outcome per rule
- [ ] #3 The database refuses a location with a region and a non-domestic country, whichever path writes it; a test inserts one through the API path and asserts the refusal
- [ ] #4 Existing impossible rows are repaired by a forward migration before the rule lands, as the owner decides; a test seeds one and asserts the repaired row
- [ ] #5 Each problem is shown on its own form field, all at once, with the same text the import gives; a test asserts the messages
- [ ] #6 [Owner] On Norway after the release carrying this, adds a physical location with Address part 1 and Region 03 Oslo to 0404 GRUE TRAVKLUBB (933130436), and tries Region 03 Oslo with a foreign country. The answer is recorded in this ticket's notes: yes closes the ticket; no gives the error to investigate.
<!-- AC:END -->
