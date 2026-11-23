---
id: b5xp5f
title: "Albanian register data in public test data: history and reporting"
state: "done"
type: bug
priority: "highest"
assignee: ["rabbit"]
labels: []
group: ""
rank: "zzzzzzzzy"
created: 2026-11-23
updated: 2026-11-23
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus_test"
done_at: "2026-11-23T16:20"
---

## Goal
Master and new releases hold no identifying Albanian data, and the history, forks and reporting are decided and recorded.

## Purpose
Data about firms in a partner country was public in our repository; it must stop spreading and be documented so a reader can tell what the test data is.

## Principle
Stop the spread first, then decide the irreversible steps with the people who own them; personal data is never copied anywhere while checking.

## Details
Found by a security review 2026-11-23: test/data/318_albania_legal_units.csv (333 rows) and 318_albania_establishments.csv (8,439 rows) in the public statisticsnorway/statbus repository held partially anonymised data from Albania's register; websites and e-mails (including gmail, yahoo and arsimi.gov.al), phones and figures still identified firms.

## Acceptance
- [x] [Owner] Confirms where the files came from and how they were anonymised when received; recorded in test/data/README.md
- [x] [Owner] Decides whether git history is rewritten (then a separate task plans the rewrite of all branches and tags, the GitHub cache purge and the fleet migration) or left with master clean (then nothing more is done in git), and whether the owners of the 5 forks are asked to update or the old history there is accepted; recorded here
- [x] Master and v2026.11.7-rc.01 contain no identifying value from the original files (tax identifiers, names, addresses, phones, e-mail, web address, figures): a script comparing the old and new files finds 0 such values; activity, region, legal form and sector codes are kept but moved between units
- [x] [Owner] Decides whether test/data/340 and 341 get the same treatment; if so they are replaced and recorded in test/data/README.md

## Notes


check 4: cfb49e73a on master: old vs new comparison found 0 original identifying values left; no gmail, yahoo, gov.al or firm domains; test 404 ok (tmp/albania/404-after.log)
2026-11-23 (Rabbit) v2026.11.7-rc.01 (tag at 016928a38) is the first release with the generated Albania data; release workflow success, 9 assets.
2026-11-23 (Rabbit) Provenance, stated so a reviewer reads it right: the files committed on 2026-01-29 (cc13d63dd) were NOT raw register data. They were received for testing and were already partially anonymised: names cut to four letters, tax identifiers shortened to seven characters (not the ten-character NUIS), street addresses and post codes replaced with placeholders, birth dates set to 1 January of invented years (up to 2315). What was left identifying: websites, e-mail addresses, phone numbers and figures. So the fault was incomplete anonymisation, not publishing raw data. Second step (this commit): test/data/318_albania_generate.py regenerates every identifying column and moves each unit's activity, region, legal form and sector set to another unit, so no unit keeps its own combination (13 of 299 units and 46 of 8,439 establishments keep theirs by chance); test/data/README.md records the provenance, the history and every column's treatment. Owner 2026-11-23: history is not rewritten unless prompted. Found while checking: test/data/340 and 341 (2026-01-21) hold 600 company names that look like real Moroccan register entries with stat and tax identifiers (no contacts or figures).
2026-11-23 Decision (owner): the regenerated data is sufficiently anonymised, and git history is not rewritten; the old commits keep the partially anonymised extract, which was undocumented until test/data/README.md (3d3013064 and the README update after it).
check 3: Owner 2026-11-23: history not rewritten; the forks keep the old history, accepted with it
landed 3d30130 on master 2026-11-23: test: Albania test data documented and fully generated; its provenance is in…
landed eba013d on master 2026-11-23: doc: test/data README records that the Albania extract was partially anonymised…
2026-11-23 (Rabbit) Morocco (test 341, 003384b83): 600 real-looking company and person names with stat and tax identifiers, meant to be anonymised. Owner 2026-11-23: same treatment. Replaced in 542a15b95 by test/data/341_duplicate_ident_generate.py (names 'Unit NNN', identifiers generated with the same digit count and the same duplicate groups); test 341 gives the same result (597 imported, rows 1, 232, 600 refused). Test 340's file is the invented demo set, unchanged. test/data/README.md records both files' provenance and the decision. Swept test/data, app/public/demo and samples: no personal e-mail or government domains except the public BRREG samples.
check 5: Owner 2026-11-23: the Moroccan names were meant to be anonymised; replaced in 542a15b95 with generated values, README updated, test 341 same result
check 1: Owner 2026-11-23: test data received for testing, already partially anonymised when received, the anonymisation undocumented; recorded in test/data/README.md
landed 542a15b on master 2026-11-23: test: test 341's Moroccan names and identifiers replaced with generated ones…
## History
- 2026-11-23T14:39 todo -> doing/active (take)
- 2026-11-23T16:20 doing/active -> done (done); was doing_since: 2026-11-23T14:39
