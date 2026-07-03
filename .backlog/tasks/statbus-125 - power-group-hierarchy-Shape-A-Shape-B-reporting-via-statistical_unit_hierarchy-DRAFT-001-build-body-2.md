---
id: STATBUS-125
title: >-
  power-group-hierarchy: Shape A + Shape B reporting via
  statistical_unit_hierarchy (DRAFT-001 build body 2)
status: In Progress
assignee:
  - '@architect'
created_date: '2026-07-02 18:04'
updated_date: '2026-07-03 11:03'
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
- [ ] #1 power_group_hierarchy(pg_id, scope, valid_on, primary_only) returns Shape A with members spanning ALL member enterprises
- [ ] #2 statistical_unit_hierarchy('power_group', X) dispatches to power_group_hierarchy — the single-enterprise collapse is gone
- [ ] #3 Shape B: enterprise/legal_unit/establishment hierarchies carry power_group_link at the root and power_group_membership on each legal_unit node, no member expansion
- [ ] #4 every power_group_membership carries influencers[] and influencees[] with {counterpart_id, type, percentage, primary}; primary = primary_influencer_only OR percentage > 50
- [ ] #5 member nodes carry physical_country_iso_2 and domestic sourced from statistical_unit
- [ ] #6 PowerGroup root carries type, depth, width, reach, root_legal_unit_id, root_status, root_is_custom; cycle/multi groups render via legal_relationship + power_root
- [ ] #7 primary_only param (default false) threaded through statistical_unit_hierarchy; true prunes to the primary/controlling spine
- [ ] #8 tests 118 + 120 assert Shape A and Shape B JSON by intent; expected .out blessed
- [ ] #9 TypeScript types added per DRAFT-001 locked naming
- [ ] #10 doc/power-groups.md updated (Reporting & Navigation section, unified primary, per-member domestic/country, group type)
<!-- AC:END -->
