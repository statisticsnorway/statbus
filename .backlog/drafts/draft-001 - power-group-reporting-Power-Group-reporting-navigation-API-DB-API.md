---
id: DRAFT-001
title: 'power-group-reporting: Power Group reporting & navigation API (DB/API)'
status: Draft
assignee: []
created_date: '2026-06-30 11:28'
updated_date: '2026-06-30 15:29'
labels:
  - power-group
  - api
  - hierarchy
  - design
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DB/API only (UI is a separate team member's job). Concept: see `doc/power-groups.md`. A **Power Group** = a DAG of legal units bound by ownership/control via `legal_relationship`. The name is SETTLED — never "enterprise group" or "control group".

PROBLEM: `statistical_unit_hierarchy('power_group', X)` today collapses the group to its root LU's single enterprise (via `statistical_unit_enterprise_id`), dropping every other member enterprise. A power group cannot be reported or navigated.

GOAL — two directions, both via `statistical_unit_hierarchy`:
- **Shape A (group on top)** — `statistical_unit_hierarchy('power_group', X)` → `{ "power_group": { …, power_group_members:[…] } }` — the whole DAG, members spanning ALL member enterprises.
- **Shape B (regular unit links to group)** — `statistical_unit_hierarchy('legal_unit'|'enterprise'|'establishment', X)` → the normal enterprise-rooted tree, PLUS a lean `power_group_link` at the root + a `power_group_membership` sub-key on each legal_unit node. No member expansion.

Split into TWO build bodies when promoted from Draft: (1) UNDERLYING power-group changes (0-index substrate); (2) EXTEND statistical_unit_hierarchy. Plus separate tasks: STATBUS-121 (foreign-member import risk); STATBUS-120 (multi-control import test).

NAMING (locked — memory `feedback_naming_full_vs_reference`: key↔type share a stem; full=`_hierarchy`/bare, reduced reference=`_link`; three ref forms `_id`/`_link`/relationship-edge):
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
1. `power_level` 0-indexed (root=0); `depth = max(power_level)`. Ripple: BFS seed `1→0` in `import.process_power_group_link`, `power_group_membership` view, `power_group_def`, tests 117/118/120, `doc/power-groups.md` scenarios.
2. member array key `power_group_members[]`.
3. SINGULAR `power_group_membership` (diamonds live in the edge arrays; BFS gives one canonical min-depth level per unit).
4. `physical_country_iso_2` inlined on member node (sourced from `statistical_unit`).
5. `domestic` inlined on member node (sourced from `statistical_unit.domestic`).
6. group `type` (power_group_type, national/multinational) surfaced at root.
7. BOTH edge directions always present (`influencers` + `influencees`) → every node self-navigable up and down.
8. EDGE `primary` = the UNIFIED single-controller flag = `legal_rel_type.primary_influencer_only OR percentage > 50`. "konsern" is NOT a separate concept — it IS this `primary`. Threshold `> 50` STRICT — finalized per IFRS 10: control presumes MORE THAN half the voting rights; exactly 50% is a deadlock, not control. The TYPE path (`primary_influencer_only`) is IFRS's de-facto-control-below-50% prong (board/voting control), so unified `primary` mirrors IFRS's two-pronged control test. Both routes guarantee a single controller (type via the 1:1 exclusion constraint; percentage via arithmetic). Keep distinct from `legal_rel_type.primary_influencer_only` (the TYPE-level input). No hard CHECK linking primary↔percentage; optional STORED generated column for indexing.
9. API param `primary_only boolean DEFAULT false` on `power_group_hierarchy` (threaded through `statistical_unit_hierarchy`). false = whole power group (all edges); true = the primary/controlling spine (consolidation view, ex-"konsern") — prune to primary edges + members reachable via them.

Cycle/multi: `power_group_membership` view is EMPTY for cycles → enumerate members from `legal_relationship`; root from `power_root` (`root_legal_unit_id`); `root_status` = `power_root.derived_root_status`.

OPEN (resolve before promotion):
- FRONTEND type touchpoints (requests.ts, database.types.ts, topology.tsx/topology-item.tsx, types.d.ts, power-groups/[id] stub). [pg-frontend never reported — gather inline]
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 power_group_hierarchy(pg_id, scope, valid_on, primary_only) returns Shape A with members spanning ALL member enterprises (not only the root LU's enterprise)
- [ ] #2 statistical_unit_hierarchy('power_group', X) dispatches to power_group_hierarchy and no longer collapses to a single enterprise
- [ ] #3 Shape B: enterprise/legal_unit/establishment hierarchies carry a lean power_group_link at the root and a power_group_membership sub-key on each legal_unit node, with NO member expansion
- [ ] #4 power_level is 0-indexed (root=0) across the membership view, power_group_def.depth, the hierarchy output, tests 117/118/120, and doc/power-groups.md scenarios
- [ ] #5 each power_group_membership carries influencers[] (up, holds influencing_id) and influencees[] (down, holds influenced_id); each edge has {type, percentage, primary} where primary = primary_influencer_only OR percentage>50
- [ ] #6 member nodes carry physical_country_iso_2 and domestic, both sourced from statistical_unit (not recomputed)
- [ ] #7 PowerGroup root carries type, depth, width, reach, root_legal_unit_id, root_status (clean|cycle|multi), root_is_custom
- [ ] #8 cycle/multi groups render: members enumerated from legal_relationship, root from power_root
- [ ] #9 primary_only param (default false) on power_group_hierarchy, threaded through statistical_unit_hierarchy: false=whole power group (all edges), true=primary/controlling spine
- [ ] #10 tests 118 and 120 extended to assert statistical_unit_hierarchy('power_group', ...) JSON by intent; expected .out blessed
- [ ] #11 TypeScript types added (PowerGroup, PowerGroupLink, PowerGroupMember, PowerGroupMembership, Influencer, Influencee) per the locked naming convention
- [ ] #12 doc/power-groups.md updated: naming-rationale strengthening, Reporting & Navigation section, 0-indexed scenarios, per-member domestic/country + group type, and the unified primary (ex-konsern) definition
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Implementation plan

## New SQL stubs (compose like the existing *_hierarchy fragments)
- `power_group_hierarchy(power_group_id int, scope hierarchy_scope DEFAULT 'all', valid_on date DEFAULT CURRENT_DATE, primary_only boolean DEFAULT false) RETURNS jsonb` — Shape A. Builds `{"power_group": {…root fields…, "power_group_members":[…]}}`. Members from `power_group_membership` (or `legal_relationship` for cycles); each member built via the member-node path + a `power_group_membership` sub-key. When `primary_only`, prune edges to primary and members to those reachable via primary edges.
- `power_group_membership_hierarchy(legal_unit_id int, valid_on date, primary_only boolean DEFAULT false) RETURNS jsonb` — the per-node `{"power_group_membership": {power_level, is_root, influencers:[…], influencees:[…]}}` fragment. `influencers` = `legal_relationship` where `influenced_id=LU`; `influencees` = where `influencing_id=LU`. Each edge `{<counterpart>_id, type (legal_rel_type.code), percentage, primary}`; `primary = primary_influencer_only OR percentage > 50`.
- `power_group_link(legal_unit_id int, valid_on date) RETURNS jsonb` — the lean `{"power_group_link": {…PowerGroupLink, NO members}}` for the Shape-B root (derive the group from the unit's membership; for an enterprise root, from its primary LU).
- `statistical_unit_hierarchy` dispatcher: `WHEN unit_type='power_group' THEN power_group_hierarchy(unit_id, scope, valid_on, primary_only)`; ELSE the existing enterprise path, now enriched — `enterprise_hierarchy` lifts `power_group_link` to its root; `legal_unit_hierarchy` injects `power_group_membership` on each LU node. Add `primary_only boolean DEFAULT false` to `statistical_unit_hierarchy`.

## 0-index ripple (decision #1 — the "underlying" build)
- `import.process_power_group_link`: BFS seed level `1→0` (root=0); children = parent_level+1.
- `power_group_membership` view: root rows level `1→0`.
- `power_group_def`: `depth = max(power_level)` (drop the −1).
- tests 117/118/120: re-assert 0-based levels. `doc/power-groups.md` scenarios: re-number to 0-base.
- **RIPPLE UNDER-COUNT — corrected in the STATBUS-124 build (2026-07-02, architect).** This list missed THREE more objects that select the root LU via `power_level = 1` and so must re-base to `= 0`: `timeline_power_group_def` (the PG NAME source in statistical_unit), `statistical_unit_enterprise_id` (the PG enterprise — the one 125 later reworks), `timeline_power_group_refresh`. The test-to-know tell was a 120 power_group-name flip (root→child). 124 re-based all SIX objects + a stored-level data re-base (`legal_relationship.derived_influenced_power_level` uniform −1, for live-DB upgrade consistency). 125 builds on root=0.

## Primary / konsern (decisions #8, #9)
- edge `primary` (derived) = `legal_rel_type.primary_influencer_only OR percentage > 50` (confirm `>` vs `>=`).
- NO CHECK linking primary↔percentage (would reject all-NULL-% BRREG primary rows and legit 60% 1:N edges). Optional STORED generated column on `legal_relationship` for indexing: `COALESCE(primary_influencer_only,false) OR COALESCE(percentage > 50,false)`.
- `primary_only=true` ⇒ primary edges + members reachable via them (the consolidation spine; ex-"konsern").

## Shape A example — statistical_unit_hierarchy('power_group', PG0001)
```
{ "power_group": { "ident":"PG0001","name":"Apex Group","type":{"code":"multinational","name":"Multinational"},
  "depth":1,"width":2,"reach":2,"root_legal_unit_id":101,"root_status":"clean","root_is_custom":false,
  "power_group_members":[
    {"legal_unit_id":101,"name":"Apex Holding AS","physical_country_iso_2":"NO","domestic":true,
     "power_group_membership":{"power_level":0,"is_root":true,"influencers":[],
       "influencees":[{"influenced_id":103,"type":"parent_company","percentage":100.00,"primary":true}]}, /*…full node…*/},
    {"legal_unit_id":103,"name":"KVÆRNER AMERICAS INC","physical_country_iso_2":"US","domestic":false,
     "power_group_membership":{"power_level":1,"is_root":false,
       "influencers":[{"influencing_id":101,"type":"parent_company","percentage":100.00,"primary":true}],"influencees":[]}, /*…*/} ] } }
```

## Shape B example — statistical_unit_hierarchy('legal_unit', 103)
```
{ "enterprise": {
   "power_group_link":{"ident":"PG0001","name":"Apex Group","type":{…},"depth":1,"width":2,"reach":2,
     "root_legal_unit_id":101,"root_status":"clean","root_is_custom":false},
   "legal_unit":[ {"legal_unit_id":103,"name":"KVÆRNER AMERICAS INC","physical_country_iso_2":"US","domestic":false,
     "power_group_membership":{"power_level":1,"is_root":false,
       "influencers":[{"influencing_id":101,"type":"parent_company","percentage":100.00,"primary":true}],"influencees":[]}, /*…normal node…*/ } ] } }
```

## TypeScript (hand-written hierarchy types)
```
interface PowerGroupHierarchy { power_group: PowerGroup }
interface PowerGroupLink { ident:string; name:string|null; type:PowerGroupType|null; depth:number; width:number; reach:number; root_legal_unit_id:number; root_status:"clean"|"cycle"|"multi"; root_is_custom:boolean }
interface PowerGroup extends PowerGroupLink { power_group_members: PowerGroupMember[] }
interface PowerGroupMember extends LegalUnitNode { legal_unit_id:number; physical_country_iso_2:string|null; domestic:boolean; power_group_membership: PowerGroupMembership }
interface PowerGroupMembership { power_level:number; is_root:boolean; influencers:Influencer[]; influencees:Influencee[] }
interface Influencer { influencing_id:number; type:string; percentage:number|null; primary:boolean }
interface Influencee { influenced_id:number; type:string; percentage:number|null; primary:boolean }
// Shape B: enterprise.power_group_link?: PowerGroupLink; the legal_unit node gains power_group_membership? + physical_country_iso_2 + domestic
```

## Tests & doc
- 118 → assert Shape A (members across enterprises, 0-based levels, both edge directions). 120 → lifecycle incl. cycle (members from `legal_relationship`, root from `power_root`), multi-root, custom_root override. Add a Shape-B assertion (power_group_link at root + power_group_membership on a LU node).
- `doc/power-groups.md`: strengthen naming rationale (memory `feedback_power_group_naming`); add a Reporting & Navigation section (the two shapes); re-base scenarios to 0; document unified `primary` + `primary_only`; note per-member `domestic`/country + group `type`.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
# Grounding (verified vs the LIVE DB this session; doc/db/ is STALE — use `./sb psql`)

## Objects
- `statistical_unit_type` enum = {establishment, legal_unit, enterprise, power_group}.
- `statistical_unit_hierarchy(unit_type, unit_id, scope hierarchy_scope DEFAULT 'all', valid_on DEFAULT CURRENT_DATE, strip_nulls DEFAULT false)` → today `SELECT enterprise_hierarchy(statistical_unit_enterprise_id(unit_type, unit_id, valid_on), scope, valid_on)`. `statistical_unit_enterprise_id` HAS a 'power_group' branch returning the root LU's enterprise (THE COLLAPSE to fix).
- `enterprise_hierarchy(enterprise_id, scope, valid_on)` → `{"enterprise": to_jsonb(en) || external_idents_hierarchy(…en.id) || legal_unit_hierarchy(NULL,en.id,…) || establishment_hierarchy(…) || notes || tag_for_unit_hierarchy(…)}`.
- `legal_unit_hierarchy(legal_unit_id, parent_enterprise_id, scope, valid_on)`; `establishment_hierarchy(…)`. `external_idents_hierarchy(est,lu,en,POWER_GROUP)` and `tag_for_unit_hierarchy(est,lu,en,POWER_GROUP)` ALREADY accept a `parent_power_group_id`.
- `power_group` (table, timeless identity): id, ident, short_name, name, type_id→power_group_type, contact_person, unit_size_id, data_source_id, foreign_participation_id.
- `legal_relationship` (temporal): influencing_id, influenced_id (both FK legal_unit, hard temporal FKs), type_id→legal_rel_type, percentage numeric(5,2) NULLABLE (CHECK 0..100), primary_influencer_only (denormalized from type via trigger `trg_legal_relationship_set_primary_influencer_only`), derived_power_group_id, derived_influenced_power_level. Exclusion constraint `legal_relationship_influenced_primary_excl` enforces 1:1 for `primary_influencer_only IS TRUE`.
- `power_root` (temporal, sparse — only cycle/multi): power_group_id, derived_root_legal_unit_id, custom_root_legal_unit_id, root_legal_unit_id GENERATED = COALESCE(custom, derived), derived_root_status ∈ {cycle, multi}.
- `power_group_membership` (view): power_group_id, power_group_ident, legal_unit_id, power_level (root=1 TODAY → 0 after #1), valid_range. EMPTY for cycles.
- `power_group_def` (view): depth, width, reach.
- `statistical_unit` (table) exposes `physical_country_iso_2` + `domestic` (boolean; computed in the timeline chain — `timeline_enterprise_refresh` `COALESCE(plu.domestic, pes.domestic)`).

## Konsern/primary (pg-konsern)
primary and percentage CAN currently disagree (no constraint links them). Norway BRREG seed `samples/norway/brreg/seed-legal-rel-types.sql`: primary 1:1 = HFOR(Hovedforetak = konsern parent)/EIKM/KOMP; non-primary 1:N = DTPR/DTSO. Konsern identifiable today ONLY by the primary flag/type (percentage unused; BRREG supplies none). Predicate: `primary_influencer_only OR percentage > 50`. Percentage scale 0–100, not 0–1.

## Foreign members (pg-engineer)
Representable ONLY as ordinary `legal_unit` rows (both `legal_relationship` endpoints are hard temporal FKs to `legal_unit`; no external-party escape). `legal_unit` has NO country flag; country lives in `location.country_id`; `statistical_unit` exposes `physical_country_iso_2`. `foreign_participation` = a classification lookup (8 codes), NOT an entity register. RISK → separate task: if BRREG import doesn't materialize `legal_unit` rows for UTLA (foreign) members, groups truncate at the border.

## BFS singular-level proof (pg-engineer / decision #3)
`import.process_power_group_link` BFS has a visited-guard ⇒ each unit recorded once at MIN depth; every incoming edge is then stamped with that one level ⇒ `power_level` is canonical-single per (group, LU) ⇒ SINGULAR `power_group_membership` is safe; diamonds live in the `influencers`/`influencees` edge arrays.
<!-- SECTION:NOTES:END -->
