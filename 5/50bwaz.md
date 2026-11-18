---
id: 50bwaz
title: "Reset by Getting started steps; Getting started shows what is really set"
state: "doing"
type: bug
priority: ""
assignee: ["rabbit"]
labels: []
group: ""
rank: "zzx"
created: 2026-11-18
updated: 2026-11-18
doing_since: "2026-11-18T12:33"
stage: "active"
model: "claude-opus-5-5"
branch: "statbus-628-all-forms"
worktree: "/Users/jhf/ssb/statbus_test"
---

## Goal
A reset offers three scopes named after what the user sees: Units; Units and Getting started; Units, Getting started and Customisation. The middle scope undoes exactly the Getting started steps (country, activity category standard, custom activity codes, regions, custom sectors, custom legal forms) and nothing on /admin. After any reset the Getting started steps show what the database holds, and a step that needs an earlier one says which.

## Purpose
On a North Cyprus installation the owner reset 'Units and classifications', and Getting started still ticked country and NACE 2.1, so the custom activity code upload failed with 'Missing public.settings.activity_category_standard_id' (owner screenshot 2026-11-18 11:27). The same scope also removed /admin customisations (unit sizes, data sources, statuses and more), which a Getting started reset should keep.

## Principle
The reset scopes follow the user's own map of the app: the Getting started menu and the /admin Customisation section.

## Relevant details
public.reset(confirmed, scope reset_scope), scopes units|data|getting-started|all; the dialog (app/src/components/command-palette/reset-confirmation-dialog.tsx) offers data 'Units only', getting-started 'Units and classifications', all 'Units, classifications and customizations'. Today getting-started also deletes custom unit_size, data_source, status, foreign_participation, legal_reorg_type, power_group_type, legal_rel_type and custom import_definition; 'all' adds tag, stat_definition, external_ident_type. Stale ticks: the sidebar reads settingsAtomAsync and the count atoms (atomWithRefresh), and the dialog only resets gettingStartedUIStateAtom and selectedTimeFrameAtom, then router.push('/') without a reload. DB side reproduced on a scratch clone: tmp/reset-repro.log (settings 0, regions 0 after the reset). Hedda is changing /admin to have a separate Customisation section without Users (owner 2026-11-18). Journal 2026-11-18 11:30.

## Depends on

## Acceptance
- [ ] A pg_regress test runs each scope on a seeded database and asserts what remains: Units leaves Getting started and /admin data; Units and Getting started empties settings, custom activity codes, regions, custom sectors and custom legal forms and leaves every /admin customisation (unit sizes, data sources, statuses, statistical variables, external identifiers, tags); the third scope also resets the customisations, users kept
- [ ] The reset dialog names the scopes Units; Units and Getting started; Units, Getting started and Customisation
- [ ] After a reset the Getting started menu shows each step as the database holds it, without a page reload (headless: reset Units and Getting started, steps 1 to 6 show not done)
- [ ] The custom activity codes upload, with no activity category standard set, says to complete step 2 first instead of the database error (test)
- [ ] [Owner] Confirms on the North Cyprus installation after the release: reset Units and Getting started, then Getting started from step 1 through the custom activity code upload

## Notes


## History
- 2026-11-18T12:33 todo -> doing/active (take)
