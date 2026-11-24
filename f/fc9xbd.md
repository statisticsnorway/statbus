---
id: fc9xbd
title: "Dashboard count requests exhaust the API pool on large registers"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "zzzzzzzzzzzv"
created: 2026-11-24
updated: 2026-11-24
---

## Goal
On a 2 M-unit register the dashboard shows every card's number within seconds, and its count requests never make other API requests fail.

## Purpose
On the Norway copy (2.19 M statistical_unit rows) the dashboard fires about a dozen count requests at once (unit cards and Data quality cards, each estimate then exact). They run 20-90 s each, fill PostgREST's connection pool, and every other request then fails with 504 PGRST003; cards stay at '-' for minutes and the app reports errors.

## Principle
Counts the dashboard shows come from data already derived where possible (statistical_history countable_count, quality table sizes) rather than from count(*) on statistical_unit per page view; a count that cannot be answered quickly does not block other requests.

## Details
Observed 2026-11-24 14:56 on the test slot with the BRREG copy: 12 active PostgREST queries 'WITH pgrst_source ... pgrst_source_count AS (SELECT 1 FROM statistical_unit WHERE unit_type ... existence ... used_for_counting)' running 20-90 s; browser console 504 x many, 'Failed to refresh legalUnits', 'Error fetching initial worker statuses'. One such count alone takes 2.9 s (parallel index-only scan, 1.1 M rows). Prefer: count=estimated still issues the exact count when PostgREST's planned rows are under its threshold? Check PostgREST db-max-rows/planned-count behaviour. Related: dwt9kd (data version), ca6dk5 (two more quality cards).

## Depends on

## Acceptance
- [ ] On the Norway copy, a cold dashboard load shows every card's number within 10 s, measured with a Playwright test, and no API request returns 504 during it
- [ ] The number of concurrent long count queries a dashboard load starts is bounded and recorded here with the measured load

## Notes
