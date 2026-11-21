---
id: ep47vn
title: "The primary notice names only what flows to the other unit"
state: "done"
type: bug
priority: ""
assignee: ["hibiscus"]
labels: []
group: ""
rank: "zzzzh"
created: 2026-11-20
updated: 2026-11-20
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus"
done_at: "2026-11-21T21:13"
---

## Goal
Editing a unit shows the notice beside Save, saying it changes the enterprise, only on fields that flow there.

## Purpose
A notice that overstates what a change touches teaches users to ignore it. The owner (2026-11-20): the name of a non-primary legal unit does not change the enterprise's name, and an enterprise's name, primary or not, does not change the legal unit's name.

## Principle
The notice follows the derivation, field by field: what timeline_enterprise_def takes from the primary legal unit (or establishment) is what the notice names; nothing else.

## Relevant details
PrimaryUnitNotice (app/src/components/form/primary-unit-notice.tsx, 839f84c98) shows 'Primary for the enterprise X: this change also changes the enterprise' beside Save on every form of a primary unit, whatever the field. timeline_enterprise_def: the enterprise's name is COALESCE(enterprise.short_name, primary legal unit's name, primary establishment's name), so an enterprise with a short_name does not take its name from the legal unit; enterprise owns only short_name, enabled and edit stamps. On the local Norway copy no enterprise has a short_name (0 of 1,134,475). The enterprise header's derived-from line (64ae2w, answer 4) must say the same. Raised by the owner while designing 64ae2w.

## Depends on

## Acceptance
- [x] Which fields flow from a primary legal unit to its enterprise, and from a primary establishment to its legal unit or enterprise, is read from the source (timeline_*_def) and documented in doc/, each field with where its value comes from
- [x] The notice beside Save appears only on fields that flow to the other unit, and names that unit; a jest test covers a flowing and a non-flowing field
- [x] With the enterprise's short name set, editing its primary legal unit's name shows no notice; checked in Firefox on the local Norway data
- [x] A non-primary legal unit shows no notice on any field; a jest test covers it

## Questions
- 2026-11-20T17:15 question 1 by hibiscus to jhf:
  Which fields of a primary legal unit flow to its enterprise (name unless the enterprise has a short name; activities, locations, contact, sector, legal form, status, figures?), and which of a primary establishment flow to its legal unit? The notice beside Save will name the other unit only on those fields.
  answered 2026-11-21T09:31 by jhf:
    This is something that you delegate to junior to figure out and then to document in our documentation how these things flow or to find where it is already documented. This is not something that you ask of me. That is sloppy on your part. It is in our source code and we shall know our source code

## Notes


2026-11-21 owner (answer 1): which fields flow is in the source code; find it or document it, do not ask him. Check 1 reworded accordingly. Delegated to worker blowfish (session_blowfish_1795249933735_59720b2a8edc52f4): read timeline_enterprise_def / timeline_legal_unit_def, document field by field in doc/, report back; hibiscus builds the notice from that.
check 1: doc/primary-units.md (b7cd2f31e, worker blowfish): every enterprise field with where its value comes from (primary legal unit, else primary establishment, COALESCE per column; legal form from the legal unit only; name after short_name; identifiers the enterprise's own first; statistics and data sources over all units), legal unit fields (own rows; only statistics and data sources aggregate its establishments), and the precise sources in timeline_enterprise_def / timeline_legal_unit_def_for. Spot-checked against the live view: COALESCE(enplu.birth_date, enpes.birth_date), sector, status, unit size; enplu.legal_form_id alone.
2026-11-21 built (uncommitted, waiting for the owner's look): app/src/components/form/primary-unit-flow.ts (editChangesEnterprise from the doc's table) + 11 tests; PrimaryUnitNotice takes the form's field id and shows only when the field flows; a primary establishment's notice about its legal unit is gone (nothing flows from it, per the doc). Full jest 519/519, tsc, eslint. Driven Firefox, VERIDIT AS (tmp/hug/ep47vn-firefox.log): Name, physical location and Contact show 'Primary for the enterprise VERIDIT AS: this change also changes the enterprise'; the tax identifier shows none; with the enterprise's short name set to 'Veridit', Name shows none. The test short name was cleared afterwards. The local Norway copy has no enterprise with a non-primary legal unit (0), so that case is covered by the jest test, not in the browser.
2026-11-21 19:50 approved together with 64ae2w. Committed 2866d0b55, pushed to master; CI pending.
landed 2866d0b on master 2026-11-21: app: the primary-unit notice names the enterprise only where the field flows…
2026-11-21 20:13 CI green on 2866d0b55 (Fast Tests, app build & lint, Go Test, Images, Harness Selftest, Push on master, Notify: all success). Check 2: primary-unit-flow.test.ts (flowing Name/location/contact, non-flowing tax identifier) and Firefox on VERIDIT AS. Check 3: Firefox with the enterprise's short name 'Veridit' set, Name showed no notice (tmp/hug/ep47vn-firefox.log). Check 4: primary-unit-flow.test.ts non-primary legal unit case (no such unit in the Norway copy). Landed in 2866d0b55.
## History
- 2026-11-20T17:15 todo -> todo/design (ask)
- 2026-11-21T09:31 answered design, by jhf, for hibiscus (todo/design -> todo/ready):
  > Which fields of a primary legal unit flow to its enterprise (name unless the enterprise has a short name; activities, locations, contact, sector, legal form, status, figures?), and which of a primary establishment flow to its legal unit? The notice beside Save will name the other unit only on those fields.
  This is something that you delegate to junior to figure out and then to document in our documentation how these things flow or to find where it is already documented. This is not something that you ask of me. That is sloppy on your part. It is in our source code and we shall know our source code
- 2026-11-21T09:31 answer 1 delivered to hibiscus (session_hibiscus_1793348926173_ffff8733f4ad20e1)
- 2026-11-21T09:31 answer 1 acknowledged by hibiscus
- 2026-11-21T09:32 hibiscus read the answer: hug task note ep47vn "2026-11-21 owner (answer 1): which fields flow is in the source code; find it or document it, do not ask him. Check 1 r…"
- 2026-11-21T09:33 todo/ready -> doing/active (take with 64ae2w)
- 2026-11-21T21:13 doing/active -> done (done); was doing_since: 2026-11-21T09:33; doing_with: 64ae2w
