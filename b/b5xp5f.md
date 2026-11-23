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
The Albania test data exposure is contained: master holds no real values, and the history, forks and reporting are decided and carried out.

## Purpose
Security review 2026-11-23 (Erik, Slack): test/data/318_albania_legal_units.csv (333 rows) and 318_albania_establishments.csv (8,439 rows) in the public statisticsnorway/statbus repository held values from Albania's register: firms' websites and e-mail addresses (including gmail, yahoo and arsimi.gov.al), phones and figures identifying businesses. Test 404 called it 'actual Albania client data'.

## Principle
Stop the spread first, then decide the irreversible steps with the people who own them; personal data is never copied anywhere while checking.

## Details
Contained 2026-11-23 in cfb49e73a: every identifying value replaced with generated values of the same shape; test 404 reproduces the same states and errors. Still exposed: added in cc13d63dd (2026-01-29), present in every later commit and in 368 tags up to v2026.11.6; the repository is public with 5 forks. Release assets (binaries, install scripts) do not include test/data. Spot checks (public business facts only): names are cut to four letters and tax identifiers shortened (A999999 instead of the 10-character NUIS), but websites and e-mails identify real firms such as a bank, a hospital and a supermarket chain. Rewriting history changes every commit SHA, which the upgrade system and every installation's checkout depend on; forks keep the old history regardless.

## Depends on

## Acceptance
- [ ] [Owner] Confirms with Erik where the files came from and whether the partner sent them as test data; recorded here
- [ ] [Owner] Decides with SSB's data protection officer whether this is reported as a breach and whether the Albanian partner is told; recorded here
- [ ] [Owner] Decides whether git history is rewritten (all branches and tags, GitHub cache purge, fleet migration plan) or left with master clean; recorded here
- [ ] Master and the next release contain no value from the original files: a script comparing the old and new files finds 0 original identifying values (done in cfb49e73a, recorded here)

## Notes


## History
- 2026-11-23T14:39 todo -> doing/active (take)
