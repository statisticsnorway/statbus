---
id: f2gx3m
title: "Totals that do not add up on jo: a unit counted before its birth date"
state: "doing"
type: feature
priority: ""
assignee: ["rabbit"]
labels: []
group: ""
rank: "00000000000f"
created: 2026-11-26
updated: 2026-11-26
doing_since: "2026-11-26T22:22"
stage: "waiting"
model: "claude-opus-5-5"
branch: "counting/birth-date-and-lu-es-rollup"
worktree: "/Users/jhf/ssb/statbus_a"
waiting_on: "lobster's counting branch (counting/birth-date-and-lu-es-rollup in statbus_a)"
waiting_since: "2026-11-27T00:00"
waiting_asked_by: "rabbit"
---

## Goal
A legal unit's total counts only units that exist in the period, and imports refuse a birth date in a year after valid_from.

## Purpose
jo.statbus.org, Frame 2023, Drill Down Norway AS (establishment 89): the legal unit shows Employees 23 own and Σ 25, Turnover 20 023 own and Σ 20 066, but its one visible establishment holds Employees 0 and Turnover 23, so the sums do not reconcile. The owner's hypothesis: a unit counts as valid before it is born.

## Principle
Reproduce first: a test with jo's shape fails before the fix and passes after. A unit counts in a period only when both apply: its validity covers the period, and, if it has a birth_date, the period is on or after it (before death_date if set). Without a birth_date, validity alone decides, as today; birth and death only narrow counting, never extend it. Validate at import, never repair silently: a birth_date in a later calendar year than the row's valid_from is an error on that row; a birth_date later in the same year stays valid.

## Details
Owner request 1 (2026-11-26 21:15). Image paste-1540.png (jo.statbus.org/establishments/89/links?details=true, Frame 2023): 23 + 0 vs Σ 25 employees, 20 023 + 23 vs Σ 20 066 turnover. Cause (Notes 21:05): establishment 86 is valid from 2023-01-01 but born 2024-11-01, and its 2 / 20 are counted in 2023. The counting rule changes in the same function as s465ff (lu_es_rollup, timeline_legal_unit_def_for), so both land in one change.

## Depends on

## Acceptance
- [ ] ~~Verify Counting issue in jo.statbus.org~~ (not relevant: replaced by checks 2-5 from the owner's request 1, rabbit, 2026-11-26)
- [x] [Owner] plays the ticket back and approves the plan before work starts; answer recorded in Notes
- [x] A SQL test reproduces jo's case for both Employees and Turnover: it fails on master and passes after the fix
- [x] An import row whose birth_date is in a later year than its valid_from is refused with an error naming both dates; a birth_date later in the same year is accepted
- [ ] On a copy of jo's data, Drill Down Norway AS's legal unit total equals its own value plus its existing establishments' values for Frame 2023

## Requests
- 2026-11-26T21:15 request 1 by jhf:
  The issue here is twofold. One, if you look at the count in the image, you will see that they don't add up. And the question is why. And I think it is because something is valid that isn't born, and then thus the counting has to have a mistake. We have to fix the test, have it fail, and then the counting will be correct. However, I think we can catch it with a validation. The team asked for birth date has to be after valid has to be before valid from. That is invalid. But I think birth date can't be more than a year in the future from valid from. Meaning if you are valid from a year, then you have to be born in the same year, not a later year, and we shall do it during validation. All of this must be played by me when this ticket is due. It is not yet.
  resolved 2026-11-26T21:15 by rabbit:
    Ticket rewritten from the request: title, goal, purpose (the jo numbers that do not add up: 23+0 vs Σ 25, 20 023+23 vs Σ 20 066), principle (reproduce with a failing test first; count a unit only where it exists; at import refuse a birth_date in a later year than valid_from, allow later in the same year; wait for the owner's play-back), details, and four acceptance checks starting with the owner's approval. Not started: the ticket is not yet due.

## Notes

file:paste-1540.png (169473 bytes, sha256:f4f591fe) pasted from the clipboard in hug tui


2026-11-26 21:05 investigated read-only on jo (tmp/f2gx3m/jo-unit.sql, .out). Legal unit 89 (Statistics Norway o, born 1924) in Frame 2023: own Employees 23, Turnover 20 023. Its establishments: 89 Drill Down Norway AS (born 2023-11-01) 0 / 23, and 86 Statbus Norway O (born 2024-11-01, but valid from 2023-01-01) 2 / 20. Σ 25 = 23 + 0 + 2 and Σ 20 066 = 20 023 + 23 + 20: jo's release adds the legal unit's own value and every establishment, including establishment 86 a year before its birth date. The owner's hypothesis holds. Also: the Links tree under the legal unit shows only establishment 89, not 86, so the visible numbers cannot add up. Next steps for the owner's play-back: (1) import validation refuses birth_date in a later year than valid_from; (2) counting includes a unit only from its birth date, decided together with s465ff (sum or max per variable); (3) the Links tree shows every establishment counted in a total.
check 2: Owner 2026-11-26 21:21: go ahead now; import validation and the counting fix to the helper in statbus_a, the Links tree and the visuals to rabbit.
Owner 2026-11-26 21:24: counting needs both: valid_from (validity) and, where a birth_date exists, the birth_date. No birth_date: validity decides.
Owner 2026-11-26 21:46, design for counting (one source of the rule): (1) birth_date and death_date are timepoints, so timeline rows split there; (2) used_for_counting in each timeline means 'counts in this period' = status flag AND within unit_existence_from(valid_from, birth_date) .. unit_existence_until(valid_until, death_date), written once as one function; (3) the legal unit's and enterprise's Σ and the report facets read only used_for_counting; the facets drop their own existence expression. Sent to lobster (branch counting/birth-date-and-lu-es-rollup).
Owner 2026-11-26 23:58: the later-year birth_date rule stays an error. Demo rows are fixed (13 establishments get valid_from 2024-01-01 and keep birth 2024-11-01), plus one dedicated test that a later-year birth_date row is refused. Sent to lobster.
check 3: test/sql/415 (branch counting/birth-date-and-lu-es-rollup, aa4fac490): jo's shape LU-JO; on master (RED, tmp/415_counting.RED.out) LU 2023..inf showed 23/20023 for the whole period with ES-JO-86 (born 2024-11-01) never split; GREEN: 23/20023 until ES-JO-89's birth 2023-11-01, 23/20046 to 2024-11-01, 25/20066 from 2024-11-01 for legal unit and enterprise. No birth date: whole validity (13). Born before valid_from: from valid_from (10 then 13). 415.3b: report facets' establishment count and employees equal the totals' included establishments and added employees at four dates. 351 (STATBUS-460) passes.
check 4: test/sql/416: RED on master (tmp/416_import.RED.out: all 4 rows processed); GREEN: row born 2024-11-01 with valid_from 2023-01-01 is error/skip with a message naming both dates under birth_date_raw and valid_from_raw; same-year (2023-11-01), earlier-year and no-birth rows import. 350 (STATBUS-461) and 369 (STATBUS-580) keep their behaviour; C13/F02 now refused as later-year.
Norway copy on slot a: 0 establishments and 0 legal units have a birth or death date strictly inside their validity, so the birth/death split adds 0 timeline rows there and the existence rule changes no unit's count or totals (tmp/norway-rollup.txt). Check 5 (jo copy) not done: no jo copy on slot a.
## History
- 2026-11-26T21:15 request 1 by jhf
- 2026-11-26T21:15 request 1 delivered to rabbit (session_rabbit_1788255452439_e2c96135756f0328)
- 2026-11-26T21:15 request 1 acknowledged by rabbit
- 2026-11-26T21:15 request 1 in progress by rabbit: hug task set f2gx3m
- 2026-11-26T21:15 resolved request 1 by rabbit
- 2026-11-26T22:22 todo -> doing/active (take)
- 2026-11-26T22:24 handed to rabbit: lobster's session went silent (last seen 2026-11-19 16:38)
- 2026-11-27T00:00 doing/active -> doing/waiting (wait)
- 2026-11-27T01:10 handed to rabbit: lobster's session went silent (last seen 2026-11-19 16:38)
