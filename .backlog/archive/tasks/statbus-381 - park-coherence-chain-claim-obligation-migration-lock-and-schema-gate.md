---
id: STATBUS-381
title: >-
  Park coherence chain: refuse claims when the convergence obligation cannot be
  recorded, persist it box-wide, serialize migrate_up, and gate source startup
  through MayRun
status: Done
assignee: []
created_date: '2026-09-22 17:01'
updated_date: '2026-09-22 17:01'
labels:
  - upgrade
  - recovery
  - cli
dependencies: []
references:
  - 9f8cd1b8f
priority: high
type: bug
ordinal: 23
---

## Park coherence chain

A parked predecessor can leave the checkout and binary one generation ahead of
the containers kept serving for operability. Displacing that park must not lose
the obligation to converge the serving tree before the successor captures its
source identities.

The required chain is:

1. A claim is refused when a standing park must be displaced but the schema
   cannot durably record the convergence obligation.
2. `public.upgrade.tree_convergence_required` persists that obligation across
   rows as box-scoped durable state, rather than recomputing it from one claim
   attempt.
3. Claim-time schema probing and migration use the shared `migrate_up` advisory
   lock, so predecessor-schema compatibility and `ADD COLUMN` cannot race the
   displacement transaction.
4. Source-era schema authorization uses the route-only MayRun path before any
   app/worker/rest start. A refused schema proof leaves the serving tier
   untouched and the park landed.

## Resolution

Fixed on master by `9f8cd1b8f` (`upgrade: make parked-era recovery coherent`).
The implementation adds the durable column and migration, refuses unsafe
park displacement, applies the daemon schema floor under lock when required,
atomically carries the box obligation into the successor claim, converges the
serving tier before source capture, and gates parked-source startup through
MayRun.

Fable, Opus, and Kimi each returned **ACCEPT** in the triple-gated review. The
fix rides `v2026.09.1-rc.28`. Status is **Done** because the complete chain is on
master; release verification is supplied by the rc.28 arc.
