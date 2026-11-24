---
id: ca6dk5
title: "A statistical variable declares how a legal unit's value relates to its establishments"
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
Each statistical variable declares covers or adds, so totals count each person once and quality checks flag what the rule finds suspicious.

## Purpose
Norway's Reports show 7.3 M employees for 2026, about twice the register's own figures (Erik, 2026-11-18): reporters put headcounts on the legal unit, on its establishments or on both, and StatBus always adds the two levels. Numbers users cannot trust undo the register's purpose.

## Principle
One declaration per statistical variable decides both the counting and the quality checks; nothing is specific to a country. Enterprises and power groups keep adding their legal units, which do not overlap. A unit shows where its counted value comes from.

## Relevant details
Rule, declared per statistical variable (setting next to stock/flow/ratio, see xc0qyq). COVERS: the legal unit's own value is the whole unit and the establishments are parts of it; the legal unit's total is the larger of its own value and its establishments' sum. ADDS: the legal unit's own value is the rest beyond its establishments; the total is own + establishments (today's behaviour for every variable). Under COVERS every reporting pattern counts once: LU only -> its value; establishments only -> their sum; both -> the larger; some establishments plus the rest on the LU -> the LU value. Quality checks under COVERS: (a) establishments sum to more than their legal unit; (b) the legal unit is larger while every establishment has a value (nothing explains the gap). Not flagged: LU larger while some establishments have no value. Under ADDS: LU value equal to its establishments' sum looks like a total reported twice. Display: own 7,397; establishments 6,878 from 117 of 120; counted 7,397. Today's aggregation: timeline_legal_unit stats_summary = jsonb_stats_merge(establishments' summaries, own stats). Norway (local copy, BRREG, 2026, tmp/ca6dk5/): added 7,317,939; COVERS 3,892,227; patterns LU only 412, establishments only 28, both equal 68,384, LU larger 3,667 (3,662 with establishments lacking a value), LU smaller 17. Literature on how statistical business registers treat this: see notes. Related: 217dx5 (configurable dashboard checks), xc0qyq.

## Depends on

## Acceptance
- [ ] [Owner] Decides the counting rule (for example: an LU with establishments counts only the establishments' headcount) and whether a quality report flags LUs whose own count differs from the sum of their establishments; the answer is recorded here
- [ ] On a copy of the Norway data, the enterprise employee total for 2026-11 is measured before and after the rule and recorded here
- [ ] [Owner] Erik confirms that Norway's employee counts mean COVERS (the legal unit's count includes its establishments): yes -> employees is declared COVERS; no -> it stays ADDS and the double counting is fixed in the data instead; the answer is recorded here
- [ ] [Owner] Decides which quality checks ship: (a) establishments sum above their legal unit, (b) legal unit larger while every establishment has a value; each chosen check becomes a Quality option and dashboard card, a dropped one is noted here
- [ ] A statistical variable carries the declaration (covers or adds), editable by an administrator, defaulting to adds so existing installations count as before
- [ ] On the local Norway copy with employees declared covers, the Reports' legal unit and enterprise employee total for 2026 is 3,892,227 (from 7,317,939); recorded here with the query
- [ ] Each chosen quality check lists exactly the legal units the rule flags on the Norway copy (17 for a, 5 for b at 2026-11-24), and its dashboard card's count equals its list

## Notes


Reproduced on the local Norway copy (BRREG, statbus slot, read-only; scripts and logs tmp/ca6dk5/). Reports 2026 (statistical_history): employees sum establishments 3,426,406, legal units 7,317,939, enterprises 7,317,939 (report-totals.log) = Erik's ~7.3 M. Registered values: 72,480 legal units carry an employee count (sum 3,891,533), 116,147 establishments (sum 3,426,406). Per legal unit (where-reported.log): LU only 412 (438,024); establishments only 28 (356); both and equal 68,384 (1,984,713 each, so counted twice); both, LU more 3,667 (LU 1,463,269 vs est 1,435,472); both, LU less 17. Added together 7,317,939; taking the larger of LU and its establishments 3,892,227. LU-more cases almost all have establishments without a value (3,662 of 3,667, difference 27,408), so the LU number covers establishments the register gives no count. LU-less 17 cases (338 people). Examples in examples.log (ISS 7,397 vs 6,878 over 117 establishments; Posten 10,413 = 10,413 over 124).
## History
- 2026-11-24T11:13 todo -> doing/active (take with pkne34)
