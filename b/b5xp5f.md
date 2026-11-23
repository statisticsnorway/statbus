---
id: b5xp5f
title: "Albanian register data in public test data: history and reporting"
state: "doing"
type: bug
priority: "highest"
assignee: ["rabbit"]
labels: []
group: ""
rank: "zzzzzzzzy"
created: 2026-11-23
updated: 2026-11-23
doing_since: "2026-11-23T14:39"
stage: "active"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus_test"
---

## Goal
The Albania test data exposure is contained, and the history, forks and reporting are decided and recorded.

## Purpose
Security review 2026-11-23 (Erik, Slack): test/data/318_albania_legal_units.csv (333 rows) and 318_albania_establishments.csv (8,439 rows) in the public statisticsnorway/statbus repository held values from Albania's register: firms' websites and e-mail addresses (including gmail, yahoo and arsimi.gov.al), phones and figures identifying businesses. Test 404 called it 'actual Albania client data'.

## Principle
Stop the spread first, then decide the irreversible steps with the people who own them; personal data is never copied anywhere while checking.

## Details
Contained 2026-11-23 in cfb49e73a: every identifying value replaced with generated values of the same shape; test 404 reproduces the same states and errors. Still exposed: added in cc13d63dd (2026-01-29), present in every later commit and in 368 tags up to v2026.11.6; the repository is public with 5 forks. Release assets (binaries, install scripts) do not include test/data. Spot checks (public business facts only): names are cut to four letters and tax identifiers shortened (A999999 instead of the 10-character NUIS), but websites and e-mails identify real firms such as a bank, a hospital and a supermarket chain. Rewriting history changes every commit SHA, which the upgrade system and every installation's checkout depend on; forks keep the old history regardless.

## Acceptance
- [ ] [Owner] Confirms with Erik where the files came from and whether the partner sent them as test data; recorded here (the answer shapes what the partner is told)
- [ ] [Owner] Decides with SSB's data protection officer whether this is reported as a breach and whether the Albanian partner is told; recorded here, and a report or message, if decided, is sent and noted here
- [ ] [Owner] Decides whether git history is rewritten (then a separate task plans the rewrite of all branches and tags, the GitHub cache purge and the fleet migration) or left with master clean (then nothing more is done in git), and whether the owners of the 5 forks are asked to update or the old history there is accepted; recorded here
- [x] Master and v2026.11.7-rc.01 contain no value from the original files: a script comparing the old and new files finds 0 original identifying values (cfb49e73a; the rc.01 tag holds the generated files, checked 2026-11-23)
- [ ] [Owner] Confirms with Erik whether the names and identifiers in test/data/340 and 341 are real Moroccan register entries; if real, they are replaced the same way and recorded here, if invented, the README says so

## Notes


check 4: cfb49e73a on master: old vs new comparison found 0 original identifying values left; no gmail, yahoo, gov.al or firm domains; test 404 ok (tmp/albania/404-after.log)
2026-11-23 (Rabbit) v2026.11.7-rc.01 (tag at 016928a38) is the first release with the generated Albania data; release workflow success, 9 assets.
2026-11-23 (Rabbit) Provenance, stated so a reviewer reads it right: the files committed on 2026-01-29 (cc13d63dd) were NOT raw register data. They came from the Albanian partner for testing and were already partially anonymised: names cut to four letters, tax identifiers shortened to seven characters (not the ten-character NUIS), street addresses and post codes replaced with placeholders, birth dates set to 1 January of invented years (up to 2315). What was left identifying: websites, e-mail addresses, phone numbers and figures. So the fault was incomplete anonymisation, not publishing raw data. Second step (this commit): test/data/318_albania_generate.py regenerates every identifying column and moves each unit's activity, region, legal form and sector set to another unit, so no unit keeps its own combination (13 of 299 units and 46 of 8,439 establishments keep theirs by chance); test/data/README.md records the provenance, the history and every column's treatment. Owner 2026-11-23: history is not rewritten unless prompted. Found while checking: test/data/340 and 341 (2026-01-21) hold 600 company names that look like real Moroccan register entries with stat and tax identifiers (no contacts or figures); to be checked with Erik.
## History
- 2026-11-23T14:39 todo -> doing/active (take)
