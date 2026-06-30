---
id: DRAFT-001
title: 'power-group-reporting: Power Group reporting & navigation API (DB/API)'
status: Draft
assignee: []
created_date: '2026-06-30 11:28'
labels:
  - power-group
  - api
  - hierarchy
  - design
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DB/API only (UI is a separate team member's job). Concept: see `doc/power-groups.md`. A **Power Group** = a DAG of legal units bound by ownership/control via `legal_relationship`. The name is SETTLED — never "enterprise group".

PROBLEM: `statistical_unit_hierarchy('power_group', X)` today collapses the group to its root LU's single enterprise (via `statistical_unit_enterprise_id`), dropping every other member enterprise. A power group cannot be reported or navigated.

GOAL — two directions, both via `statistical_unit_hierarchy`:
- **Shape A (group on top)** — `statistical_unit_hierarchy('power_group', X)` → `{ "power_group": { …, power_group_members:[…] } }` — the whole DAG, members spanning ALL member enterprises.
- **Shape B (regular unit links to group)** — `statistical_unit_hierarchy('legal_unit'|'enterprise'|'establishment', X)` → the normal enterprise-rooted tree, PLUS a lean `power_group_link` at the root + a `power_group_membership` sub-key on each legal_unit node. No member expansion (keeps it small + non-circular).

Split into TWO bodies of work when promoted from Draft: (1) UNDERLYING power-group changes (the 0-index substrate); (2) EXTEND statistical_unit_hierarchy (the new stubs). Plus a SEPARATE task for the foreign-member import risk.

NAMING (locked — memory `feedback_naming_full_vs_reference`: key↔type share a stem; full = `_hierarchy`/bare, reduced reference = `_link`; three ref forms `_id`/`_link`/relationship-edge):
- `power_group` / `PowerGroup` / `power_group_hierarchy()` — the full group.
- `power_group_link` / `PowerGroupLink` / `power_group_link()` — reduced group reference (PowerGroup minus members).
- `power_group_membership` / `PowerGroupMembership` / `power_group_membership_hierarchy()` — a unit's membership.
- `power_group_members` / `PowerGroupMember[]` — member nodes (inside the full group).
- `influencers` / `Influencer[]` (UP; holds `influencing_id`) + `influencees` / `Influencee[]` (DOWN; holds `influenced_id`) — per-membership edges; each `{ <counterpart>_id, type, percentage, primary }`.

CONTRACT:
- `PowerGroup` root: `ident, name, type (national/multinational), depth, width, reach, root_legal_unit_id, root_status (clean|cycle|multi), root_is_custom, power_group_members[]`.
- `PowerGroupLink` = `PowerGroup` minus `power_group_members[]`.
- `PowerGroupMember extends LegalUnitNode { legal_unit_id, physical_country_iso_2, domestic, power_group_membership }`.
- `PowerGroupMembership { power_level (0-indexed; root=0), is_root, influencers[], influencees[] }`.

LOCKED DECISIONS:
1. `power_level` 0-indexed (root=0); `depth = max(power_level)`. Ripple: BFS seed `1→0` in `import.process_power_group_link`, `power_group_membership` view, `power_group_def`, tests 117/118/120, and `doc/power-groups.md` scenarios.
2. member array key `power_group_members[]`.
3. SINGULAR `power_group_membership` (diamonds live in the edge arrays; BFS gives one canonical min-depth level per unit).
4. `physical_country_iso_2` inlined on member node (sourced from `statistical_unit`).
5. `domestic` inlined on member node (sourced from `statistical_unit.domestic`).
6. group `type` (power_group_type, national/multinational) surfaced at root.
7. BOTH edge directions always present (`influencers` + `influencees`) → every node self-navigable up and down.

Cycle/multi: `power_group_membership` view is EMPTY for cycles → enumerate members from `legal_relationship`; root from `power_root` (`root_legal_unit_id`); `root_status` = `power_root.derived_root_status`.

OPEN (must resolve before promotion):
- KONSERN vs full power-group views: reports need (a) whole power group (all edges) and (b) konsern-only = primary/majority (>=50%). Edges already carry `primary` + `percentage` so both are filterable; verify consistency between `legal_rel_type.primary_influencer_only` (1:1 control) and `legal_relationship.percentage`, and define a clean konsern predicate (likely `percentage >= 50 OR (percentage IS NULL AND primary_influencer_only)`). [pg-konsern investigating]
- FOREIGN-member import truncation: confirm BRREG import materializes `legal_unit` rows for UTLA (foreign) members, else groups truncate at the border. [SEPARATE TASK]
- FRONTEND type touchpoints (requests.ts, database.types.ts, topology.tsx/topology-item.tsx, types.d.ts, power-groups/[id] stub). [pg-frontend — not yet reported]
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 power_group_hierarchy(pg_id, scope, valid_on) returns Shape A with members spanning ALL member enterprises (not only the root LU's enterprise)
- [ ] #2 statistical_unit_hierarchy('power_group', X) dispatches to power_group_hierarchy and no longer collapses to a single enterprise
- [ ] #3 Shape B: enterprise/legal_unit/establishment hierarchies carry a lean power_group_link at the root and a power_group_membership sub-key on each legal_unit node, with NO member expansion
- [ ] #4 power_level is 0-indexed (root=0) across the membership view, power_group_def.depth, the hierarchy output, tests 117/118/120, and doc/power-groups.md scenarios
- [ ] #5 each power_group_membership carries influencers[] (up, holds influencing_id) and influencees[] (down, holds influenced_id); each edge has {type, percentage, primary}
- [ ] #6 member nodes carry physical_country_iso_2 and domestic, both sourced from statistical_unit (not recomputed)
- [ ] #7 PowerGroup root carries type, depth, width, reach, root_legal_unit_id, root_status (clean|cycle|multi), root_is_custom
- [ ] #8 cycle/multi groups render: members enumerated from legal_relationship, root from power_root
- [ ] #9 konsern view supported per the resolved konsern predicate (pending pg-konsern)
- [ ] #10 tests 118 and 120 extended to assert statistical_unit_hierarchy('power_group', ...) JSON by intent; expected .out blessed
- [ ] #11 TypeScript types added (PowerGroup, PowerGroupLink, PowerGroupMember, PowerGroupMembership, Influencer, Influencee) per the locked naming convention
- [ ] #12 doc/power-groups.md updated: naming-rationale strengthening, a Reporting & Navigation section, 0-indexed scenarios, per-member domestic/country + group type
<!-- AC:END -->
