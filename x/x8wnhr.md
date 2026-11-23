---
id: x8wnhr
title: "Retire the hand-run country SQL files in custom/"
state: todo
type: chore
priority: "low"
assignee: []
labels: []
group: ""
rank: "zzzzzzzzq"
created: 2026-11-23
updated: 2026-11-23
---

## Goal
custom/ holds no country setup file that nothing runs; each country's setup is done in the app or by a migration.

## Purpose
custom/al.sql, jo.sql, ke.sql, ma.sql, ug.sql and customize_countries.sql define procedures (custom_setup_ma() and others, Erik, Oct 2025) that are run by hand; the installer does not use them, and the admin pages now cover external identifiers and statistical variables, so they may be stale copies of what the databases hold.

## Principle
A country's setup lives in its database, made through the app (Getting started, Admin); a file is kept only if something still runs it.

## Details
rg finds no caller of custom/*.sql outside the folder. Mozambique (mz) is set up through the app instead, with no custom file.

## Depends on

## Acceptance
- [ ] [Owner] Confirms with Erik which files, if any, are still used and how; recorded here
- [ ] The files nobody uses are deleted in one commit, and rg finds no reference to them

## Notes
