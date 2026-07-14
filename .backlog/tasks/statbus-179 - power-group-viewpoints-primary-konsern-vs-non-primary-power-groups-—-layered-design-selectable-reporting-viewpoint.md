---
id: STATBUS-179
title: >-
  power-group-viewpoints: primary (konsern) vs non-primary power groups —
  layered design + selectable reporting viewpoint
status: To Do
assignee: []
created_date: '2026-07-14 10:00'
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
