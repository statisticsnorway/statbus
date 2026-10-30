---
id: STATBUS-125
title: >-
  power-group-hierarchy: Shape A + Shape B reporting via
  statistical_unit_hierarchy (DRAFT-001 build body 2)
status: Done
assignee:
  - '@architect'
created_date: '2026-07-02 18:04'
updated_date: '2026-07-03 11:43'
labels:
  - power-group
  - not-install-upgrade
dependencies:
  - STATBUS-124
references:
  - DRAFT-001
  - doc/power-groups.md
  - STATBUS-120
  - STATBUS-121
priority: medium
ordinal: 125000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Second build body of the power-group-reporting design — **DRAFT-001 is the authoritative design**; build to its implementation plan and locked contract. Fixes the core problem: `statistical_unit_hierarchy('power_group', X)` today collapses the group to the root LU's single enterprise, dropping every other member enterprise.

Scope (from DRAFT-001):
- New SQL fragments: `power_group_hierarchy(pg_id, scope, valid_on, primary_only)` (Shape A — group on top, members spanning ALL member enterprises), `power_group_membership_hierarchy(lu_id, valid_on, primary_only)` (per-node membership: power_level, is_root, influencers[]/influencees[]), `power_group_link(lu_id, valid_on)` (lean Shape-B root reference, no members).
- `statistical_unit_hierarchy` dispatcher: 'power_group' → power_group_hierarchy; enterprise path enriched (power_group_link at root, power_group_membership on each legal_unit node). New param `primary_only boolean DEFAULT false`.
- Edge `primary` = `legal_rel_type.primary_influencer_only OR percentage > 50` (strict >, IFRS 10); `primary_only=true` = the controlling spine.
- Cycle/multi groups: members from `legal_relationship`, root from `power_root`, root_status = derived_root_status.
- TypeScript types per the locked naming (PowerGroup, PowerGroupLink, PowerGroupMember, PowerGroupMembership, Influencer, Influencee).
- Tests 118/120 extended to assert both shapes by intent; doc/power-groups.md gains the Reporting & Navigation section + unified-primary definition.

Import-side companions (separate tasks, not this one): STATBUS-120 (multi-control import test), STATBUS-121 (foreign UTLA member materialization).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 power_group_hierarchy(pg_id, scope, valid_on, primary_only) returns Shape A with members spanning ALL member enterprises
- [x] #2 statistical_unit_hierarchy('power_group', X) dispatches to power_group_hierarchy — the single-enterprise collapse is gone
- [x] #3 Shape B: enterprise/legal_unit/establishment hierarchies carry power_group_link at the root and power_group_membership on each legal_unit node, no member expansion
- [x] #4 every power_group_membership carries influencers[] and influencees[] with {counterpart_id, type, percentage, primary}; primary = primary_influencer_only OR percentage > 50
- [x] #5 member nodes carry physical_country_iso_2 and domestic sourced from statistical_unit
- [x] #6 PowerGroup root carries type, depth, width, reach, root_legal_unit_id, root_status, root_is_custom; cycle/multi groups render via legal_relationship + power_root
- [x] #7 primary_only param (default false) threaded through statistical_unit_hierarchy; true prunes to the primary/controlling spine
- [x] #8 tests 118 + 120 assert Shape A and Shape B JSON by intent; expected .out blessed
- [x] #9 TypeScript types added per DRAFT-001 locked naming
- [x] #10 doc/power-groups.md updated (Reporting & Navigation section, unified primary, per-member domestic/country, group type)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
BUILD PROGRESS (architect, 2026-07-03): Migration 20260703111119_power_group_hierarchy_shape_a_b_statbus_125 written + applied locally. 6 functions: NEW power_group_link (multi-parent: LU/enterprise/pg-id), power_group_membership_hierarchy (emits membership + country/domestic ONLY for members — containment), power_group_hierarchy (Shape A; cycle/multi via legal_relationship + power_root; primary_only spine via recursive walk); REPLACED (DROP+CREATE, primary_only appended): legal_unit_hierarchy, enterprise_hierarchy, statistical_unit_hierarchy; statistical_unit_details completes power_group dispatch. Down migration restores \sf-dumped originals (stdout-only dump). EMPIRICALLY SMOKE-VERIFIED in rolled-back txns on dev DB: Shape A 4 members/3 enterprises (collapse gone), diamond edges both directions, unified primary (type-route @NULL%, percentage-route @60%>50, non-primary @30%), spine prune, cycle group renders (root_status=cycle, root from power_root, NULL levels), Shape B link+membership, containment on pre-existing LU (no new keys), ~20ms. Tests 118 (+Section 12, stale echo fixes) + 120 (+2a/2b/2f shape assertions) extended — tester running; expected outputs to be blessed after intent review. TS types added (types.d.ts per locked naming). doc/power-groups.md: Reporting & Navigation + unified-primary sections. doc/db + types regen running. NOTE for review: statistical_unit_enterprise_id kept for stats/search callers (representative enterprise); only the hierarchy path bypasses it.

BUILD COMPLETE (architect, 2026-07-03) — all 10 ACs verified, package HELD for foreman review. Test evidence: 118 Section 12 (Shape A 4-members/4-enterprises, 0-based levels, edge payloads, primary_only prune 2→1, Shape B, dispatch t/f), 120 2a/2b/2f/Phase-6 (deep chain 0-3, unified primary BOTH prongs: parent_company@50%→primary via TYPE + co_ownership@49%→false, spine prune 3→2, cycle+custom-root effective_root=Apex Manufacturing, MULTI: 2 naturals at level 0 + is_root only power_root designee + depth 1). CONTAINMENT VERIFIED per foreman: 107/109/110/111 all PASS zero-diff; 109 perf baseline drift = timing jitter only (identical plans) → discarded per testing.md. Both blessed .out files 0 NUL bytes. FLAG (infra, not 125): first 118 run's results file had a 5207-byte NUL hole at offset 0x3000 exactly (lost 4K-aligned write in pg_regress output path on this macOS/Docker setup); clean on re-run, same byte count — if it recurs, deserves its own backlog task. EXPLAIN discipline: all edits to existing fns are additive (appended || fragments + CASE routing, foreman-exempted class); stats-caller keep-decision recorded in migration header. Stamps: types-generate + app-tsc stamps WITHHELD (dirty tree) — re-run ./sb types generate + cd app && pnpm run tsc after commit. NOT in package (engineer's in-flight, disjoint): cli/cmd/install.go, cli/cmd/session_orphan_test.go.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-03 11:43
---
COMMITTED 8a45e2945 + PUSHED — DONE, all 10 criteria checked (architect built on Fable/high; foreman first-hand review before commit). Review evidence: down migration = the four \sf-dumped originals verbatim + drops of the six new signatures; up = 3 new fragments + additive-only edits to the existing hierarchy functions (appended composition terms + a dispatch CASE; signature additions force drop-and-create); doc/db regen = EXACTLY the six functions + details (independent scope confirmation); containment VERIFIED not assumed — 107/109/110/111 byte-identical post-migration; the EXPLAIN-exempt additive class confirmed (no predicate/join shape changed). Coverage highlights: both IFRS prongs of unified primary proven in one blessed row pair; spine prune; cycle group with custom root; multi-root Phase 6 ADDED (architect self-caught the untested multi case); 118 Shape A shows 4 members across 4 enterprises — the collapse is gone. Pre-existing 118 echo-vs-output contradiction fixed in the re-bless. Post-commit stamps (types + tsc) regenerated clean. RESIDUALS: (1) the one-off 5207-byte NUL hole at 0x3000 in a pg_regress results file (clean on re-run, identical byte count) — watch for recurrence, then it gets its own task per no-flaky-tests; (2) this push is MIGRATION-BEARING → its published seed becomes the genuine-delta prior the deferred multi-delta confirming run needs (once the seed-consistency defect is fixed). The power-group handoff from the King's other session is now fully landed: 124 substrate + 125 hierarchy; import subtasks 120/121 remain in their own lane.
---
<!-- COMMENTS:END -->
