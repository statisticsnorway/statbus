---
id: ca6dk5
title: "Employee totals count legal units and their establishments twice?"
state: "doing"
type: spike
priority: "medium"
assignee: ["rabbit"]
labels: []
group: ""
rank: "zzzzz"
created: 2026-11-21
updated: 2026-11-21
doing_since: "2026-11-24T11:13"
doing_with: "pkne34"
stage: "active"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus_test"
---

## Goal
We know whether no.statbus counts the same employees on a legal unit and on its establishments, and what the totals should show.

## Purpose
Erik (Slack 2026-11-18): Norway's enterprise employee total for Nov 2026 is about 7.3 million, more than Norway's workforce; he suspects LU + establishment employees are both counted. Owner 2026-11-20: this is a quality report, suspicious numbers between LU and establishment counts.

## Principle
A total adds each person once; where the register holds the same headcount at two levels, the rule for which level counts is explicit and shown.

## Relevant details
How it adds up today (doc/db, 2026-11-21): timeline_legal_unit stats_summary = the legal unit's own stats merged with its establishments' summaries (jsonb_stats_merge(esa.stats_summary, basis.stats_summary)); timeline_enterprise merges its legal units' summaries and its informal establishments'. In BRREG both the legal unit (enhet) and each establishment (underenhet) carry an employee count, usually the same people, so the LU total adds them twice. Erik suggested separate lu_employees and est_employees. Related: 217dx5 (configurable dashboard checks), xc0qyq (variable behaviour).

## Depends on

## Acceptance
- [ ] [Owner] Decides the counting rule (for example: an LU with establishments counts only the establishments' headcount) and whether a quality report flags LUs whose own count differs from the sum of their establishments; the answer is recorded here
- [ ] On a copy of the Norway data, the enterprise employee total for 2026-11 is measured before and after the rule and recorded here

## Notes


## History
- 2026-11-24T11:13 todo -> doing/active (take with pkne34)
