---
id: ep47vn
title: "The primary notice names only what flows to the other unit"
state: "doing"
type: bug
priority: ""
assignee: ["hibiscus"]
labels: []
group: ""
rank: "zzzzh"
created: 2026-11-20
updated: 2026-11-20
stage: "active"
doing_since: "2026-11-21T09:33"
doing_with: "64ae2w"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus"
---

## Goal
Editing a unit says it changes another unit only for fields that really flow there, as does the enterprise's derived-from line.

## Purpose
A notice that overstates what a change touches teaches users to ignore it. The owner (2026-11-20): the name of a non-primary legal unit does not change the enterprise's name, and an enterprise's name, primary or not, does not change the legal unit's name.

## Principle
The notice follows the derivation, field by field: what timeline_enterprise_def takes from the primary legal unit (or establishment) is what the notice names; nothing else.

## Relevant details
PrimaryUnitNotice (app/src/components/form/primary-unit-notice.tsx, 839f84c98) shows 'Primary for the enterprise X: this change also changes the enterprise' beside Save on every form of a primary unit, whatever the field. timeline_enterprise_def: the enterprise's name is COALESCE(enterprise.short_name, primary legal unit's name, primary establishment's name), so an enterprise with a short_name does not take its name from the legal unit; enterprise owns only short_name, enabled and edit stamps. On the local Norway copy no enterprise has a short_name (0 of 1,134,475). The enterprise header's derived-from line (64ae2w, answer 4) must say the same. Raised by the owner while designing 64ae2w.

## Depends on

## Acceptance
- [ ] Which fields flow from a primary legal unit to its enterprise, and from a primary establishment to its legal unit or enterprise, is read from the source (timeline_*_def) and documented in doc/, each field with where its value comes from
- [ ] The notice beside Save appears only on fields that flow to the other unit, and names that unit; a jest test covers a flowing and a non-flowing field
- [ ] Editing an enterprise's short name, and a non-primary legal unit's name, shows no such notice; checked in Firefox on the local Norway data

## Questions
- 2026-11-20T17:15 question 1 by hibiscus to jhf:
  Which fields of a primary legal unit flow to its enterprise (name unless the enterprise has a short name; activities, locations, contact, sector, legal form, status, figures?), and which of a primary establishment flow to its legal unit? The notice beside Save will name the other unit only on those fields.
  answered 2026-11-21T09:31 by jhf:
    This is something that you delegate to junior to figure out and then to document in our documentation how these things flow or to find where it is already documented. This is not something that you ask of me. That is sloppy on your part. It is in our source code and we shall know our source code

## Notes


2026-11-21 owner (answer 1): which fields flow is in the source code; find it or document it, do not ask him. Check 1 reworded accordingly. Delegated to worker blowfish (session_blowfish_1795249933735_59720b2a8edc52f4): read timeline_enterprise_def / timeline_legal_unit_def, document field by field in doc/, report back; hibiscus builds the notice from that.
## History
- 2026-11-20T17:15 todo -> todo/design (ask)
- 2026-11-21T09:31 answered design, by jhf, for hibiscus (todo/design -> todo/ready):
  > Which fields of a primary legal unit flow to its enterprise (name unless the enterprise has a short name; activities, locations, contact, sector, legal form, status, figures?), and which of a primary establishment flow to its legal unit? The notice beside Save will name the other unit only on those fields.
  This is something that you delegate to junior to figure out and then to document in our documentation how these things flow or to find where it is already documented. This is not something that you ask of me. That is sloppy on your part. It is in our source code and we shall know our source code
- 2026-11-21T09:31 answer 1 delivered to hibiscus (session_hibiscus_1793348926173_ffff8733f4ad20e1)
- 2026-11-21T09:31 answer 1 acknowledged by hibiscus
- 2026-11-21T09:32 hibiscus read the answer: hug task note ep47vn "2026-11-21 owner (answer 1): which fields flow is in the source code; find it or document it, do not ask him. Check 1 r…"
- 2026-11-21T09:33 todo/ready -> doing/active (take with 64ae2w)
