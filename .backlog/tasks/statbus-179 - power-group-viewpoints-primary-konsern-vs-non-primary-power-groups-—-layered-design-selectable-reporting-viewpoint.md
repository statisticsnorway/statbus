---
id: STATBUS-179
title: >-
  power-group-viewpoints: primary (konsern) vs non-primary power groups —
  layered design + selectable reporting viewpoint
status: To Do
assignee: []
created_date: '2026-07-14 10:00'
updated_date: '2026-07-14 10:16'
labels:
  - power-groups
  - design
  - reporting
  - architect-plan
  - not-install-upgrade
dependencies: []
priority: medium
ordinal: 180000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: an NSO can report on the PRIMARY power group (konsern — controlling edges only; what the EU wants in reports today) AND on the larger interest-alignment grouping (non-controlling edges included: delt ansvar, equal shares, two-50% holders), choosing the viewpoint at reporting time.
> ORIGIN: King, 2026-07-14 morning, from the STATBUS-120/178 discussion + the meeting with Swedish NSO staff reporting to the EU: both viewpoints are useful; the EU wants the primary one in their reports, for now. Delt-ansvar-forms-power-groups is WANTED, but OPTIONAL — a selectable viewpoint, not a forced merge.
> COMPLEXITY: architect design first (this is the ticket's substance), King reviews; build follows as its own scope.

THE OPEN DESIGN QUESTION (King's words, near-verbatim): is a non-controlling cluster part of the SAME power group, or do we have MULTIPLE power groups — a primary power group and a non-primary power group that can SPAN multiple other (primary) power groups? The design must be looked at for how that can work.

GROUNDING (current state, verified 2026-07-14): primary-ness is per-type (legal_rel_type.primary_influencer_only); Norway maps HFOR/EIKM/KOMP primary, DTPR/DTSO (delt ansvar) non-primary. Two docs currently DISAGREE on whether non-primary edges form power groups today: samples/norway/brreg/README.md says DTPR/DTSO don't (future, via multi-root); doc/power-groups.md:24 says all types contribute to clustering. The design work must first establish the empirical current behavior (one import experiment) and fix whichever doc is wrong, then rule the layered model.

DESIGN POINTS: (1) edge marking vs group multiplicity — one clustered group with primary/non-primary marked edges queryable per viewpoint, or two group layers where a non-primary group may span several primary groups; (2) how two-50% holders (legal, must be expressible) attach without violating the primary exclusion; (3) reporting API: viewpoint selection (primary-only default per EU; expanded on request); (4) relation to derived_root_status multi-root machinery; (5) migration/derivation cost of whichever model wins.

RELATED: STATBUS-178 (duplicate PRIMARIES stay illogical and per-row-erroring regardless of this design), STATBUS-120 (test coverage; closes with 178's unit), doc/power-groups.md DRAFT-001 reporting design.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Empirical current behavior established: do only-DTPR/DTSO edges form a power group today — and the losing doc (brreg README vs doc/power-groups.md) corrected
- [ ] #2 Architect design ruling: one marked-edge group vs layered primary/non-primary groups (spanning allowed) — with the two-50% case expressible
- [ ] #3 Reporting viewpoint selection designed: primary-only (EU default, for now) vs expanded interest-alignment view
- [ ] #4 King reviews and approves the design before any build
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-07-14 10:16
---
AC#1 EMPIRICAL RESULT (architect, 2026-07-14): only-DTPR/DTSO edges DO form a power group today.

Evidence, two independent layers:
1. THE RUN (the committed, CI-proven kind — stronger than a one-off local import): test/sql/119_roller_data_power_groups.sql imports an all-DTPR ("Baltic") hierarchy through the real import pipeline alongside an HFOR ("Nordic") one; its committed expected output asserts `total_power_groups = 2` (test/expected/119_roller_data_power_groups.out:283-289) — the DTPR-only component forms its own group with memberships. Green in the rc.05 preflight (85/85 fast tests, 2026-07-13).
2. THE CODE: import_process_power_group_link builds the clustering edge set as `SELECT influencing_id, influenced_id FROM public.legal_relationship` UNION the reverse — no `primary_influencer_only` filter anywhere in analyse/process (doc/db/function/import_process_power_group_link…md lines 57-59; import_analyse_power_group_link idem).

LOSING DOC: samples/norway/brreg/README.md ("Forms PG? No" for DTPR/DTSO; "don't currently form power groups"). CORRECTED in the working tree (uncommitted, for foreman review + commit): the Forms-PG column removed (everything forms PGs; the column encoded the wrong model), the intro now states what primary_influencer_only actually controls (cardinality, exclusion, hierarchy direction — not membership), and the "Partnership Structures (Future)" section rewritten to present tense + pointer to this ticket. doc/power-groups.md:24 stands as written.
---

author: architect
created: 2026-07-14 10:16
---
DESIGN RULING part 1/2 (architect, 2026-07-14) — AC#2: the LAYERED model, with a SPARSE interest layer.

Answer to the King's question: both halves of it are true at once, because the two groupings are mathematically nested. Primary edges are a subset of all edges, so the components over primary edges REFINE the components over all edges: every primary (konsern) group lies wholly inside exactly one interest-alignment group, and one interest group may SPAN several primary groups. It is not "same group" versus "separate groups" — it is one clustered universe with two layers, where the non-primary layer is the coarsening of the primary layer.

Why primary groups must be FIRST-CLASS rows (not a marked-edge pruning of today's merged group): take the must-express case — konsern A and konsern B each hold exactly 50% of joint venture X. Today's all-edge clustering merges A's tree, B's tree and X into ONE power_group: one ident (PGxxxx) for what the EU sees as TWO enterprise groups plus an unconsolidated JV. Worse, the existing `primary_only=true` rendering prunes to members reachable from THE single derived root (MIN-id ⇒ A), so konsern B's entire tree silently vanishes from the primary view of its own group — a reporting crack that exists today. Enumerable EU reporting units with stable idents require the konsern to BE a row.

THE MODEL:
- power_group gains `scope` ∈ {primary, interest} (naming for the King: messages "controlling group (konsern)" / "interest-alignment group").
- PRIMARY groups = components over primary edges, where a primary edge is the already-ratified unified flag (type primary_influencer_only OR percentage > 50, doc/power-groups.md:169) — grouping and reporting share one definition of control.
- INTEREST layer is SPARSE (precedent: power_root): an interest row exists ONLY when the all-edge component's membership differs from exactly-one primary component's — i.e. it spans ≥2 primary groups, or adds units around one (the JV), or contains no primary edges at all (pure DTPR/DTSO partnerships, the test-119 Baltic case). The common konsern with no shared-ownership links stays ONE row (scope=primary), no duplicate pair.
- Containment materialized: scope=primary rows carry a nullable FK to their containing interest row. Interest membership = union of contained primary members + endpoints of its non-primary edges — computable from materialized data, no recursion at query time (house rule).
- Edge storage: a primary edge's derived_power_group_id → its primary group; a non-primary edge's → its interest row when one exists, else the primary group it is internal to (intra-konsern DTPR edges render inside the konsern exactly as primary_only=false shows them today). NEW derived_primary_influenced_power_level for konsern-internal depth (BFS over primary edges from primary roots; NULL on non-primary edges); the existing level column keeps its all-edge semantics so partnership hierarchies (Baltic) keep their tree rendering — no regression.
- power_root machinery UNCHANGED, attaches per group row in either layer: primary-layer cycle/multi still arise (cross-type dual primary parents — the exclusion constraint is per (influenced, type); data-error double->50% edges), and NSO custom roots become per-konsern. The README's old "future multi-root" framing for partnerships is superseded: partnerships are interest-layer, already handled.

Two-50% holders (AC#2's must-express): both edges percentage=50, not >50 ⇒ non-primary ⇒ no exclusion violation, X consolidates into NO konsern (IFRS: 50% is deadlock, not control), and one interest group spans PG_A + PG_B + X. Expressible, and the sparse interest row is exactly its representation.
---

author: architect
created: 2026-07-14 10:16
---
DESIGN RULING part 2/2 (architect, 2026-07-14) — AC#3 reporting + costs + bless points.

REPORTING VIEWPOINT (AC#3): replace the existing `primary_only boolean` with `viewpoint` ∈ {'primary' (DEFAULT — the EU report view, for now per the King), 'interest'} threaded exactly where primary_only threads today: statistical_unit_hierarchy → power_group_hierarchy, power_group_link, power_group_membership_hierarchy. Semantics: viewpoint=primary renders the konsern row (its members, primary spine, konsern-internal levels, per-konsern root incl. NSO override); viewpoint=interest renders the containing interest group (all members across spanned konsern, all edges, all-edge levels) — falling back to the primary group itself when no interest row exists. Shape B units link to their group per viewpoint. Enumeration/search/statistical-unit surfaces filter on scope; EU exports read scope=primary. Clean break per house rule: the boolean param is removed and the app updated in the same commit — no deprecation shim.

DERIVATION + MIGRATION COST (design point 5): the same label-propagation + BFS machinery runs twice (primary-edge pass, all-edge pass) — identical asymptotics, ~2× the constant of today's single pass; analyse/process_power_group_link extended in place; base_change_log.power_group_ids logs both layers' ids so the derive pipeline refreshes both. One-time migration: existing groups whose membership equals one primary component (the vast majority) keep their ident, gain scope=primary; a merged cluster's existing row keeps its ident as the interest row (its membership is unchanged — ident stability contract honored) and its contained konsern MINT NEW idents. Deterministic, set-based, no per-row judgment.

RELATION TO 178/120 (unchanged): duplicate PRIMARIES of the same type remain per-row import errors regardless of viewpoint — the detector byte-mirrors the exclusion constraint; nothing here relaxes it.

KING BLESS POINTS (AC#4):
1. The layered model itself: two first-class layers with sparse interest rows — versus his alternative reading (one group, marked edges), which the JV reporting crack rules out.
2. Scope naming: 'primary' / 'interest' (messages: "controlling group (konsern)" / "interest-alignment group").
3. The viewpoint parameter as a clean break replacing primary_only (app + API same commit).
4. Ident continuity in previously-merged clusters: the old ident stays with the INTEREST row; each konsern inside mints a new ident. (Alternative — largest konsern inherits the old ident — is defensible if EU continuity of the konsern ident matters more than membership continuity; I rule membership continuity, he may overrule.)
5. EU default = viewpoint 'primary', revisited when the EU asks for more.

Build follows as its own scope after his review; test 119/117/118/120 extend naturally (Baltic becomes the zero-primary interest case; a new JV-spanning fixture proves the sparse row + both viewpoints).
---
<!-- COMMENTS:END -->
