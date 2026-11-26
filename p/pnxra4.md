---
id: pnxra4
title: "Admin edits only custom definitional entries; built-in ones are read-only"
state: "dropped"
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "zzzzzzzzzzzy"
created: 2026-11-26
updated: 2026-11-26
dropped_reason: "duplicate of mna899"
dropped_at: "2026-11-26T10:34"
---

## Goal
Admins edit custom entries of definitional tables; built-in (non-custom) entries can only be switched on or off.

## Purpose
Owner 2026-11-26 during Hedda's review: he recalls a ticket for this and could not find it in effect on master; filed so it is not lost.

## Principle
The database enforces it (built-in rows refuse edits other than enabled); the admin pages show built-in rows without an edit form.

## Details
Tables with a custom flag: data_source, unit_size, status, legal_form, sector, activity_category, region? Check which have custom. Hedda's Customization pages (branch ui/fixes-and-improvements, merged 2026-11-26) list enabled first, then custom.

## Depends on

## Acceptance
- [ ] An UPDATE of a built-in entry's name or code is refused by the database; its enabled flag can still change
- [ ] The admin pages show built-in entries without an edit control, observed in a browser

## Notes

Duplicate of mna899 (Shipped classification rows can be enabled or disabled, not changed), which holds the owner's design from 2026-11-22: a read-only factory twin per shipped table with a foreign key over every column except enabled. Found via Hibiscus.


## History
- 2026-11-26T10:34 todo -> dropped (drop)
