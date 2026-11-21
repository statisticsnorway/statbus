---
id: whn7tk
title: "Disabling a statistical variable fails on no.statbus.org"
state: todo
type: bug
priority: "medium"
assignee: []
labels: []
group: ""
rank: "zzzzzq"
created: 2026-11-21
updated: 2026-11-21
---

## Goal
An administrator on Norway can disable turnover or stat_ident in Admin, Statistical variables, as works on demo.

## Purpose
Erik (Slack 2026-11-11 13:38): on no.statbus.org only, saving Enabled off for Turnover (and stat_ident) in the edit dialog does not take; on demo it works. Norway has about 3M statistical units.

## Principle
Every failure is diagnosed: a save that does not take shows its error to the user.

## Relevant details
Likely the regeneration a variable change triggers is too slow on Norway's size and times out (yq9mws: the change should return at once and the worker regenerates). Not reproduced yet; the error the dialog got is unknown.

## Depends on

## Acceptance
- [ ] [Owner] Reproduces on Norway or allows a read-only check of its logs; the error and its cause are recorded here
- [ ] After the fix, disabling turnover on Norway takes effect and the dialog shows it; the result is recorded here

## Notes
