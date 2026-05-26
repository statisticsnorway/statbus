# StatBus Vision

> ## **Simple to use. Simple to understand. Simply useful.**
>
> **StatBus is a temporal source of truth for statistical business registries, operated by national statistical offices.**

This document defines the identity. It moves rarely — at the cadence of years, not months. Strategy (how we make decisions to serve this identity) lives in `STRATEGY.md`. Specific designs (how a particular subsystem implements strategy) live in domain documents under `doc/`.

---

## The motto, with discipline of word choice

**Simple to use** — the UI is succinct and to the point. The operator's interface does not exceed the operator's task.

**Simple to understand** — you can see changes over time. Temporal truth isn't only an architectural property; it's the UX promise that makes the data legible.

**Simply useful** — you can enter data, find and modify data one by one, and extract reports.

The motto deliberately says **simple**, not **uncomplicated** and not **not-complex**. The world StatBus models is complex (taxonomies reform, regions split, units evolve). The implementation that absorbs that complexity may also be complex. What the operator experiences is *simple*. Complexity inside is acceptable when it buys simplicity outside.

These commitments translate concretely:

- **The UI's main menus are three**: *Import*, *Search*, *Report*. Data goes in; you find and modify what's there; data goes out. Three buttons; everything else lives inside one of those three.
- **The temporal axis is ambient, not hidden.** A time picker in the top-right corner is the context every operation knows about. The operator picks a context once; operations work within it. The temporal complexity is never invisible, but never demanding either.
- **Complexity is made part of the context you are in**, never hidden behind an "advanced mode" toggle that surprises the operator on discovery.

## Identity

StatBus is a database-centric system that stores observed entities — legal units, establishments, locations — with full temporal history. It exists so a National Statistical Office can answer "who was where doing what at time T" with current and historical truth, transparently and auditably.

## Architecture stance — load-bearing, not implementation detail

PostgreSQL stores the truth. PostgREST exposes the schema. Row Level Security enforces authorization. The application layer is a thin lens over the database — not a translation, not a business-logic owner.

The architecture is **Lego-shaped**. Security and data structure are enforced inside the database. Above that single enforcement layer, any composition of access modes, roles, operations, and integration patterns is valid. There is no one true way to use StatBus; there is one true place where rules live. NSOs grow from level 1 (UI) to level 3 (direct DB) without throwing away StatBus and without changing the rules.

When something exists in StatBus, it has the same name everywhere — in the database, in the auto-generated PostgREST API, in the UI. There are no mapping layers. Learning a concept once means using it anywhere; this is what makes the three integration levels coherent rather than three separate products.

Operators with `./sb psql` access see exactly what the UI sees. Integrators using the API see exactly what the database holds. There is no hidden middleware, no secret transformation, no application-layer business logic the database doesn't enforce.

This is identity, not implementation. A version of StatBus that drifted from database-centric, or from the Lego shape, or from cross-layer naming uniformity, would not be StatBus.

## Who operates StatBus

National statistical offices, self-hosting. Two modes:

- **Standalone** — one dedicated server per country (the rune box for Norway, future country boxes).
- **Multi-tenant cloud** — multiple countries co-located on a shared host (niue.statbus.org hosting demo, dev, etc.).

NSOs run their own upgrades, extend taxonomies for national needs, integrate StatBus with their own data pipelines via the public PostgREST API.

StatBus is **not** SaaS. It is software that NSOs run themselves, with source open and architecture transparent.

## Who uses StatBus — the 1-2-3 of audiences

Three audiences in priority order. Design serves them in this sequence; trade-offs default toward the lower number.

1. **NSO statisticians** — the **primary**. They enter data, find and modify records, extract reports. The UI is built for them. Their experience is the test of the motto.
2. **NSO operators** — technically advanced users running the deployment, automating workflows, scripting bulk operations. They get power via the command palette and the REST API.
3. **NSO integrators** — those building automation and integration at depth. They get full access through the PostgREST API and direct database connections.

## The 1-2-3 of integration levels

Different NSOs arrive with different technical capabilities. StatBus meets them where they are and lets them grow:

1. **UI only** — the operator clicks; the system works. Sufficient for an NSO that does not yet have automation skills.
2. **REST API** — the operator scripts. PostgREST exposes the same data model as the UI. Every UI call is visible in the browser's Network tab, which means scripting begins by inspection and imitation. (AI assistance turns this into a powerful onboarding ramp.)
3. **Direct database access** — the operator integrates. Connection strings, SQL, table reads and writes; create and run import jobs from external systems.

The promise of the three levels: **the same security model applies at all three.** Whether you click, call REST, or query the database directly, Row Level Security enforces the same authorization. There is no privileged back door, no level where rules relax.

This is what makes progressive disclosure of complexity safe.

## The three-layer model

Import → Derive → Report.

- **Import** is the only thing that mutates base tables. All bulk mutation flows through the import pipeline.
- **Derive** is read-only and idempotent. Derived tables can be cleared and rebuilt from base tables at any time.
- **Report** consumes derived views. Reports never mutate.

This separation is identity-level, not just architectural. A version of StatBus where reports could mutate base tables, or where derive procedures wrote to base tables, would not be StatBus.

The derived layer carries the **aggregate views** — `statistical_unit`, `statistical_history`, `statistical_history_facet` — that integrators target. These views absorb the join and temporal complexity that would otherwise be re-coded by every consumer. They are the stable surface of the live-truth database.

## Temporal truth, preserved exactly — the killer feature

Source data's `[valid_from, valid_until)` is preserved verbatim. The system remembers what was observed at the time it was observed. Reporting interprets; storage remembers.

**Temporal truth is what StatBus does that almost no other SBR does.** The standard SBR design — codified in the [United Nations Guidelines on Statistical Business Registers](https://unstats.un.org/unsd/business-stat/SBR/Documents/UN_Guidelines_on_SBR.pdf) (UN Statistics Division, 2019) and followed by most national systems — uses **frozen frames**: a complete database copy per year. With frozen frames, "show me the number of employees by year" requires joining N annual copies; merging legal units into enterprises across time becomes intractable. The practical consequence is that most national SBRs treat `enterprise = legal_unit` (or `legal_unit = establishment`) because they cannot afford the join cost across copies. This isn't malice — it's that getting it right under the frozen-frame paradigm is too hard.

Notably, the UN Guidelines do not discuss temporal tables or graphs-over-time as design patterns. StatBus is solving a problem the canonical reference doesn't even frame.

StatBus uses **live temporal tables** powered by `sql_saga` — a custom PostgreSQL extension that provides temporal data with foreign keys, written in optimized Rust, exhaustively tested. This is the foundational complexity that affords the simple promise of the motto: enter data for 2024, see the graph over years, modify 2024 while editing 2026, everything stays correct.

**The killer graph**: years on the x-axis, count of statistical units on the y-axis, with employees and turnover as the headline measures. This is the single most-asked-for view from a statistical business registry. StatBus shows it correctly because temporal truth is the foundation, not a feature bolted on later.

## What victory looks like

- Albania, Norway, Morocco each running their own StatBus, with national customizations on a shared kernel.
- Researchers querying state across reforms — pre-2020 Norway region data viewable through post-2020 lenses — without losing the underlying truth.
- An NSO upgrading to a new release with zero data loss and full audit trail.
- New NSO adoption requiring days of integration work, not months.
- An NSO that has adopted StatBus has a viable path forward at every level of investment — the simple UI for everyday work, the command palette and REST API as they automate, direct database access for the truly novel needs. The investment never gets wasted because the system never restricts what they can build.

## What StatBus is NOT

- Not a CRM, not a generic ERP.
- Not a microservices platform — single PostgreSQL database, single app, simple deployment.
- Not SaaS — NSOs run their own deployments.
- Not a closed product — every architectural decision is open and explainable.
- Not a black box — operators can introspect, customize, and extend at the database layer.

## Boundaries of identity

A proposed change that touches the motto, the database-centric stance, the three-layer model, the temporal truth promise, the 1-2-3 audience priority, the three integration levels, or the uniform-security-across-modes posture is a **vision-level change** requiring re-grounding before proceeding.

A change that adds or modifies a decision filter (how we choose between alternatives) updates `STRATEGY.md`.

A change inside an existing principle (refining how it applies in a specific subsystem) updates the relevant design document under `doc/`.
