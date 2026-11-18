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
- [ ] A reset of the third scope restores every system default a user edited on /admin to its shipped value (name, enabled, priority and other columns), and removes custom rows; a test edits a default unit size, status, data source and statistical variable, resets, and asserts the shipped rows
- [ ] A Getting started reset (and the third scope) restores the activity category standards as shipped, including code_pattern; a test changes NACE's code_pattern to digits, resets, and asserts dot_after_two_digits
- [ ] System default priorities on /admin (external identifiers, statistical variables, statuses) start at 10 in steps of 10, so 1-9 are free for users; person_ident is disabled by default, also after a reset; a test asserts the shipped rows on a fresh database and after the third-scope reset
- [ ] Priority is unique only among enabled rows in each /admin table with a priority (external_ident_type, stat_definition, status); a test enables two rows with the same priority and gets a clear error, and keeps a disabled row's priority without conflict
- [ ] A forward migration moves an existing installation's system rows to the new priorities and person_ident's default, leaving rows a user created or re-prioritised as they are; tested on rows written before the migration

## Notes


2026-11-18 11:48-12:02 owner decisions: (1) three scopes, the database values match the dialog: 'units' deletes the units and the import jobs that made them (a finished job cannot be re-run, so keeping jobs leaves a screen that disagrees with the data); 'getting-started' adds the six Getting started steps (Activity Category Settings counts as step 2); 'customisation' adds the /admin Customisation section and never touches users. The old values data, getting-started, all and units are replaced; test 305 follows. Re-running finished import jobs for testing would be its own ticket. (2) Owner addenda: a full reset restores the system defaults a user edited on /admin (e.g. a renamed unit size, a disabled status), not only deletes custom rows; and a reset restores the activity category standards as shipped, including code_pattern (e.g. NACE back to dot_after_two_digits). Finding: the defaults are seeded by migrations from dbseed/*.csv (unit_size, data_source via \copy) and literal INSERTs (status, standards), which reset cannot read at runtime, so the shipped defaults need one stored copy in the database that both the seed and reset use.
2026-11-18 13:21 owner addendum, same migration: system default priorities start at 10 so users can use 1-9 freely; person_ident disabled by default; priority unique only among enabled rows; for every /admin table with a priority. Findings (tmp/50bwaz-priority.log): /admin tables with priority are external_ident_type (UNIQUE(priority)), stat_definition (UNIQUE(priority)) and status (no uniqueness). Shipped values today: tax_ident 1, stat_ident 2, person_ident 10 (disabled); employees 1, turnover 2; active 1, passive 2. person_ident is disabled on fresh installs since 20260326160507, but reset('all') re-inserts it with enabled = true. Plan: shipped priorities 10, 20, 30 ...; replace the UNIQUE(priority) constraints with partial unique indexes WHERE enabled (and add one to status); a forward migration moves existing system rows whose priority the user has not changed (still 1/2) to the new values without colliding with user rows.
## History
- 2026-11-18T12:33 todo -> doing/active (take)
