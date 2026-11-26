---
id: ca6dk5
title: "A legal unit's total covers its establishments, as UN and EU registers count"
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
stage: "waiting"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus_test"
waiting_asked_by: "rabbit"
waiting_on: "lobster's counting branch (s465ff/f2gx3m)"
waiting_since: "2026-11-27T00:00"
---

## Goal
A legal unit counts the larger of its own value and its establishments' sum, so totals count each person once; two quality checks flag gaps.

## Purpose
Norway's Reports show 7.3 M employees for 2026, about twice the register's figures (Erik, 2026-11-18), because StatBus adds a legal unit's own value to its establishments'. Under the UN Guidelines on Statistical Business Registers and the Eurostat Business Registers Recommendations Manual an enterprise consists of its local units and its employment equals their sum; Norway's data has the same shape (68,384 of 72,453 legal units with values on both levels report the same total).

## Principle
One rule for every installation, no per-variable setting: a legal unit's value covers its establishments. Enterprises and power groups keep adding their legal units, which do not overlap. Mismatches between the levels are quality findings, not counting variants. A unit shows where its counted value comes from.

## Relevant details
Rule (covers): legal unit total = greatest(own value, sum of its establishments' values); missing levels count as absent, so LU only -> own; establishments only -> their sum; both -> the larger. Applies to values that are summed; how stock, flow and ratio variables combine is xc0qyq. Today: timeline_legal_unit stats_summary = jsonb_stats_merge(establishments' summaries, own stats), i.e. added. Quality checks: (a) establishments sum to more than their legal unit (parts exceed the whole); (b) legal unit larger while every establishment has a value (nothing explains the gap; under the UN/EU model usually a missing establishment such as the head office). Not flagged: LU larger while some establishments have no value (the LU covers them). Display: own 7,397; establishments 6,878 from 117 of 120; counted 7,397. Norway local copy (BRREG, 2026-11-24, tmp/ca6dk5/): added 7,317,939; covers 3,892,227; LU only 412, establishments only 28, both equal 68,384, LU larger 3,667 (3,662 with establishments lacking a value, 5 with all valued), establishments larger 17. A per-variable 'adds' setting was considered and dropped: no UN/EU source describes it (only a UK reporting-unit residual), and check (a) would reveal data that means 'adds'. Related: 217dx5, xc0qyq.

## Depends on

## Acceptance
- [x] A SQL regression test builds legal units for each pattern (LU only, establishments only, both equal, LU larger, establishments larger) and asserts each legal unit's employee total is the covers value (the larger of its own value and its establishments' sum) and its enterprise's total is the sum of its legal units' totals
- [x] On the local Norway copy the Reports' legal unit and enterprise employee total for 2026 is 3,892,227 (from 7,317,939); recorded here with the query
- [x] Quality check 'establishments above their legal unit' lists exactly the legal units where the establishments' sum exceeds the legal unit's value (17 on the Norway copy at 2026-11-24), and its dashboard card's count equals its list
- [x] Quality check 'legal unit above its establishments' lists exactly the legal units larger than their establishments' sum while every establishment has a value (5 on the Norway copy at 2026-11-24), and its dashboard card's count equals its list
- [x] doc/METHODOLOGICAL_GUIDELINE.md explains how a legal unit's values relate to its establishments (covers), with references to the UN Guidelines on Statistical Business Registers and the Eurostat Business Registers Recommendations Manual, and the statistical variables admin page and the import of statistical variables link to that explanation
- [ ] The next release candidate after v2026.11.7-rc.01 contains the covers rule and both quality checks; its tag and commit are recorded here

## Notes


Reproduced on the local Norway copy (BRREG, statbus slot, read-only; scripts and logs tmp/ca6dk5/). Reports 2026 (statistical_history): employees sum establishments 3,426,406, legal units 7,317,939, enterprises 7,317,939 (report-totals.log) = Erik's ~7.3 M. Registered values: 72,480 legal units carry an employee count (sum 3,891,533), 116,147 establishments (sum 3,426,406). Per legal unit (where-reported.log): LU only 412 (438,024); establishments only 28 (356); both and equal 68,384 (1,984,713 each, so counted twice); both, LU more 3,667 (LU 1,463,269 vs est 1,435,472); both, LU less 17. Added together 7,317,939; taking the larger of LU and its establishments 3,892,227. LU-more cases almost all have establishments without a value (3,662 of 3,667, difference 27,408), so the LU number covers establishments the register gives no count. LU-less 17 cases (338 people). Examples in examples.log (ISS 7,397 vs 6,878 over 117 establishments; Posten 10,413 = 10,413 over 124).
Literature (2026-11-24, web): the standard model is COVERS with a consistency check. Eurostat Business Registers Recommendations Manual (2010): the enterprise consists of one or more local units, and its employment should equal the sum of its local units' employment. UN/UNECE Guidelines on Statistical Business Registers (2015): employment must be attachable to every local unit; enterprise and local unit are recorded as separate units even when there is one local unit. UK ONS (Business Structure Database guide, IDBR): local units forming a reporting unit have employment that sums to the reporting unit, and some employment is accounted for by the reporting unit itself, i.e. a residual held above the local units (ADDS-like for that part). Statistics Canada: the location is the lowest unit, with employment at minimum. Statistics Norway's register (VoF/CRE) takes employees per establishment from a-ordningen; its enterprise statistics treat a legal unit as an enterprise. No source found that declares the rule per variable; registers fix one model (covers) and treat level mismatches as register quality work, with a residual where employment cannot be placed on a local unit. Supports: COVERS as default for headcounts, ADDS where a variable holds only the residual, and the two quality checks.
2026-11-24 owner: settled without Erik's confirmation: covers is the UN/EU standard and Norway's numbers show it; the per-variable adds setting is dropped. Both quality checks are wanted (owner: suspicious when the legal unit is not covered by its establishments, and when it is lower than its establishments).
2026-11-24 owner: rc.01 is not promoted; the next release candidate carries everything on master since rc.01 (pkne34, rwavxg, dwt9kd) plus this rule, both quality checks and the documentation, so installations get the new counting together with the reports that explain it.
Covers rule implemented (migration 20261124114235, public.jsonb_stats_covers). Test 410 RED under adding (tmp/ca6dk5/test-410-red.out: LU-EQUAL 18, LU-MORE 26, LU-LESS 12, totals 73), GREEN after (test-410-green.out: 9, 20, 7, totals 53; enterprises equal). Prototype on Norway copy read-only: covers 3,892,227 vs added 7,317,939 (tmp/ca6dk5/covers-perf.log). Fast suite: 6 expected outputs change only in stats summaries (no sum rose, none disappeared; diffs in tmp/ca6dk5/diff-*.txt): 302/303/309/310 totals drop where LU and establishments reported the same values; 109/306 sums unchanged, count/mean change because a legal unit no longer adds its establishments' zero values. 016 needed ./sb types generate for the new function.
check 1: test/sql/410_legal_unit_covers_its_establishments: five patterns, legal unit totals 10/7/9/20/7 and enterprise totals equal (= sum of their legal units), 53 both; RED under adding 73 (tmp/ca6dk5/test-410-red.out), GREEN with migration 20261124114235.
check 5: Commit: doc/METHODOLOGICAL_GUIDELINE.md section 3.2.3 'How Statistical Variables Add Up Between Legal Units and Establishments' with references 1 (UN Guidelines on SBR, unstats.un.org PDF, HTTP 200) and 2 (Eurostat Business Registers Recommendations Manual, HTTP 200); StatisticalVariableCounting shown on Admin > Statistical Variables and the Legal Units and Establishments import pages, linking to that section.
2026-11-24 owner: before push, an independent agent reviews only the changed pg_regress expected files, and someone reviews the whole change (commits 6561172b7, 0651e5592).
check 2: Norway copy (BRREG dump 2026-11-23, test slot) after migrations 20261124114235/115435 and the full recalculation the migration schedules (59 min): statistical_history 2026 employees legal_unit 3,892,227 and enterprise 3,892,227 (from 7,317,939), establishments unchanged 3,426,406, power groups 860,540 (from 1,280,422). Before the recalculation the stored totals were still 7,317,939 (tmp/ca6dk5/norway-after-migrate.log), which is why the migration now ends with worker.enqueue_derive_statistical_unit_all(). After: tmp/ca6dk5/norway-after-derive.log, query tmp/ca6dk5/norway-after.sql.
check 3: Norway copy after recalculation: quality_establishments_above_legal_unit 17 rows, all current (norway-after-derive.log); dashboard card 'Establishments Above Legal Unit' exact 17 = list total 17 with chip 'Quality Establishments above legal unit' (tmp/ca6dk5/cards-vs-lists-quality-norway.log). Test 410.4 lists exactly LU-LESS (own 5, establishments 7).
check 4: Norway copy after recalculation: quality_legal_unit_above_establishments 5 rows, all current; card 'Legal Unit Above Establishments' exact 5 = list total 5 (cards-vs-lists-quality-norway.log). Test 410.5 lists exactly LU-GAP (own 12, establishments 4+3 both valued); LU-MORE (one establishment without a value) not listed.
Norway copy, all dashboard cards vs lists, live frame (tmp/ca6dk5/cards-vs-lists-norway.log): Enterprises 1,134,475; Legal Units 1,134,475; Establishments 823,767; Missing Region 2; Missing Activity Category 161,571; Missing Physical Location 22,445; Establishment Activity Differs 11,009; Establishments Above Legal Unit 17; Legal Unit Above Establishments 5; each card = list.
Review findings resolved in a39ff9730: shared derive (73 s -> 14 s on Norway, same 17/5), narrowed comparison view, derive_quality weight 3, down of the covers migration recalculates too, Eurostat citation precise (ch. 5, variable 3.8), example dated, duplicate card removed. Fast suite 146/146. Expected-output review: all OK (tmp/ca6dk5/review-expected.md).
landed 6561172 on master 2026-11-24: db: a legal unit's stats cover its establishments, counting each person once…
landed 0651e55 on master 2026-11-24: quality: legal unit vs establishments checks, cards, and how stats add up…
landed a04b30c on master 2026-11-24: db, app: the covers migration recalculates stored totals; quality link helper is…
landed a39ff97 on master 2026-11-24: quality: one pass for both legal unit checks; review fixes (ca6dk5)
landed e97e86f on master 2026-11-24: app: a failed "are there units" check no longer shows unit cards as an exact 0…
Pushed 6561172b7..e97e86f58 to master. CI green at e97e86f58 (Fast Tests, Go Test, app build & lint, Images, Harness Selftest, Push on master). ./sb release check: all preflight checks pass at e97e86f58 (local fast/types/tsc/build/doc stamps at e97e86f58). Waiting for the owner's look on the Norway copy before ./sb release prerelease (check 6).
Design agreed with owner 2026-11-24 19:19 (merges 217dx5 for Data quality): one database catalogue of quality checks (code, plain name, explanation shown by an ⓘ, on-dashboard switch). Per summed statistical variable two checks: '<Variable>: establishments add up to more than the legal unit' and '<Variable>: legal unit has more than its establishments, all of which have numbers'. Switched off = hidden from the dashboard and the Quality filter; the Data quality section says 'N checks switched off' with an Edit link (admins) to the admin page. New installations: all checks on, Employees and Turnover alike. Catalogue rows follow stat_definition through the existing lifecycle_callbacks trigger; failing units are computed in the derive pipeline's derive_quality step, one row per unit and variable. Report cards join the same catalogue later (owner's coming standard-reports ticket); this change covers Data quality only.
2026-11-24 20:22 design prototype for the catalogue (rolled back; tmp/ca6dk5/catalogue/prototype-finding.sql/.log, Norway copy): one quality_finding table with every check's units and their existence dates, built from statistical_unit and the three current quality tables: 2,307,685 rows, 202 MB (missing activity category over all history rows is most of it), 16.3 s to fill + 3.8 s for the (rule, stat_definition_id, existence_from, existence_until) index. One grouped query gives every Data quality card's number at 2026-11-24 in 45 ms, equal to today's cards: missing region 2, missing activity 161,571, missing location 22,445, activity differs 11,009, establishments above legal unit (employees) 17, legal unit above establishments (employees) 5. Today those six cards are six statistical_unit counts of 0.1-4 s each. Design sent to the owner for review: quality_rule enum, quality_check view over enum x enabled summed stat_definition, quality_check_switched_off table (rows only for off), one quality_finding table.
2026-11-24 20:31 owner approved the quality-check catalogue design; built under 05pe0x (taken with this task: ships in the same rc.02). Check 6 (rc.02) waits for 05pe0x.
## History
- 2026-11-24T11:13 todo -> doing/active (take with pkne34)
- 2026-11-27T00:00 doing/active -> doing/waiting (wait)
