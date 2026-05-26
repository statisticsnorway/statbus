# StatBus Strategy

> Principles that filter every architectural decision. Each was earned across multiple campaigns; the list expands when a new principle proves repeatedly load-bearing, never speculatively.

`VISION.md` defines what StatBus is. This document defines how we make decisions to stay true to that vision.

---

## How to use this document

This file is **not** a tutorial, not onboarding documentation, not an exhaustive style guide. It is the load-bearing decisions that, when in conflict with a proposed design, win.

If a code review, design proposal, or campaign decision conflicts with a principle below, the principle wins unless the conflict is named, justified, and the principle updated.

---

## Principles

### 1. The Lego principle — enforcement at the bottom, composition above

The data structure and the security model live in the database. Above that single enforcement layer, anything composable is allowed. Roles compose with operations; access modes compose with integration levels; UI elements compose with command-palette shortcuts; primitives compose with import jobs.

**This is the meta-principle from which most of the others follow.** Uniform security across access modes works because RLS is the one place rules live. Three integration levels work because customers can move between them without re-architecting — the rules don't change. Live-truth database works because the database is what's exposed, not a mapped surface. Import-as-mutation-contract is a Lego move: reuse the existing pipeline instead of building a parallel apply engine.

A consequence: when something exists in StatBus, it has the same name everywhere — in the database, in the auto-generated PostgREST API, in the UI. There are no mapping layers. This is what allows learning to compound across layers.

**Why**: NSOs arrive with different needs and different technical capabilities. A "my way or the highway" architecture excludes them. The Lego architecture says "yes, and" — click in the UI, *and* call the REST API, *and* connect via psql, all at once, all under the same rules, all composable.

**Lesson learned the hard way.** The previous version of StatBus took the architecturally-conservative path that conventional wisdom recommends: a mapping layer between the database and the API. The mapping layer was too narrow — we hadn't anticipated all the ways customers would want to integrate — and the system became unusable. The Lego architecture is the deliberate refusal of that pattern. We pay for it with strict discipline on names, schema shape, and exposed surfaces — and customers get a system they can actually use.

**Forbids**: building new mechanism when composition does the job; one-true-way features that exclude alternative integration patterns; security or business logic outside the database (which would create a second enforcement layer that must be kept in sync); mapping layers between database and REST and UI; cross-layer name divergence; **dual identity for one concept** — a view AND a table that represent the same thing, or any pattern where "which underlying object am I really operating on?" becomes unclear and accumulates over time.

**Enables**: NSOs growing from level 1 to level 3 without throwing away StatBus; the design discipline that produces the rest of this document; the motto — simple outside, composable inside.

### 2. Database-centric, with uniform security across access modes

PostgreSQL holds the data and the business logic. PostgREST exposes the schema. Row Level Security enforces authorization — once, in one place, equally for every access mode.

The same security rules apply whether the operator clicks in the UI, calls the REST API, or connects via psql. There is no privileged back door, no "internal-only" channel where rules relax.

**Why**: NSOs integrate StatBus at different levels (see principle #2). A single security boundary in the database means the integration level can change without rewriting authorization logic. Security audits focus on one layer. Operators see in psql what the UI sees.

**Forbids**: parallel application-layer security; business logic that lives in the app and isn't enforced at the database; "the API is a contract, the DB schema is internal" stance; admin tooling that bypasses RLS via shared credentials; any logic that would behave differently when invoked via UI vs REST vs direct DB.

**Enables**: operators self-service via psql with the same safety as the UI; integrators learn StatBus by inspecting `/rest` calls in their browser; security model has one place to reason about.

### 3. Three progressive integration levels: UI → REST → DB

Customers vary widely in technical capability. StatBus offers three integration levels and lets each customer choose how deep they want to go. The rough split of operator effort:

- **Level 1: UI** (clicks). Covers about 80% of operator work directly, with another ~10% reachable through the **command palette** for power users. The UI is built for the primary audience.
- **Level 2: REST API** (PostgREST calls). Covers about ~9% — the automation and scripting needs that exceed clickable UI. The browser's Network tab is the documentation; every UI call is inspectable, so customers script by imitation.
- **Level 3: Direct database** (psql, SQL, programmatic connections). Covers the remaining ~1% — the genuinely novel needs no one anticipated. Full power, same security. NSOs at this level can even install their own additional database alongside StatBus and integrate at the database layer, without giving up the StatBus they already have.

The compound: an NSO that adopts StatBus has a viable path forward for *anything* they need to do. No one ever throws StatBus away because it "doesn't support X" — they go deeper instead. This is what the investment in StatBus buys: never being stuck.

**Why**: countries arrive with different technical maturity. Forcing one access pattern excludes lower-capability adopters; restricting power excludes the technically advanced. Three layers lets one StatBus serve all — and the existence of level 3 is what protects the investment of everyone at levels 1 and 2.

**Forbids**: features exposed at the UI but unreachable through REST; data shapes accessible only through the application that don't match the database schema; "API for advanced users only" tiering; documentation that hides the database structure.

**Enables**: integration progresses with skill; AI-assisted scripting onboarding (inspect Network tab, imitate, automate); no rewrites when a customer levels up; NSOs investing in StatBus knowing they can extend it for novel needs.

### 4. Database as live truth, with stable aggregate layers

The database schema is the API. It evolves. Customers at integration levels 2 and 3 adapt their automation as it evolves — they re-inspect, re-script. AI assistance makes this cheap.

**This is sustainable because** the database includes deliberate **aggregate layers** — `statistical_unit`, `statistical_history`, `statistical_history_facet` — that absorb the join and temporal complexity. Integrators target these aggregate views, not the base tables. The aggregate layers are where naming discipline matters most: they are the stable surface where the cost of change is paid by the system, not by the customer.

**Why**: a versioned, frozen public API would mean a second source of truth diverging from the database. Either the API would lag the schema (and customers would lose access to new capabilities), or the API would race ahead (and the schema would be forced into shapes that suit the API rather than the data). The live-truth stance avoids that fork by paying the cost in two ways: deliberate aggregate layers that hide volatile internals, and strict naming discipline at the layers customers see.

**Forbids**: pretending the database is internal and the REST API is the contract; building separate "stable" API shapes that diverge from the schema; renaming aggregate-layer columns or views for cosmetic reasons.

**Enables**: schema and API stay in lockstep (one source of truth); new capabilities are immediately available at every integration level; AI-assisted adaptation when changes do land.

### 5. Three-layer pipeline: Import → Derive → Report

Only Import mutates base tables. Derive is read-only and idempotent — derived tables can be cleared and rebuilt from base tables at any time. Report consumes derived views; reports never mutate.

**Why**: bugs in derivation are recoverable (clear, rebuild, verify); reports can never corrupt source data; tests can clear and rebuild and check determinism.

**Forbids**: derivation procedures that write to base tables; reports that bypass derived views and query base directly; "fix it directly with UPDATE" workflows on base tables.

**Enables**: full pipeline re-run after every code change; performance work on derive without touching base data; auditability — if base data is correct, derived data WILL be correct.

### 6. Import is the universal mutation contract; triggers do plumbing

Every bulk mutation of unit data is an import job. The worksheet → CSV → re-import pattern is how mass corrections, mapping resolutions, and bulk fixes happen.

Database triggers handle small automatic propagation — change detection, derived-table updates, statistical-history rollups. They do **not** perform bulk mutations of user data. The dividing line: triggers do plumbing that an operator would not have wanted to think about; import jobs do work an operator deliberately initiated and should be able to preview, approve, and audit. Country-specific calculation strategies (e.g., recomputing statistical-unit size from rule tables) produce import jobs even when triggered by a button — the operator previews the proposed changes before they apply.

**Why**: the import pipeline already provides preview, progress, error handling, batching, idempotency, audit trail. Building parallel "apply" infrastructure duplicates all of that and splits operators' mental model.

**Forbids**: parallel "apply" engines; bulk-update commands; DSLs for rule application; standalone "mass-fix" UI workflows.

**Enables**: one mutation surface, learned once; one preview/audit/error model; new bulk workflows ship by generating CSVs instead of building UIs.

### 7. Temporal truth, preserved exactly

Source data's `[valid_from, valid_until)` is preserved verbatim — never truncated by computed signals like `death_date`. The reporting layer interprets; the storage layer remembers.

**Why**: NSOs need to drill into historical state. If `valid_until` is silently rewritten at import time, history is unrecoverable.

**Forbids**: implicit-truncation logic; "smart" valid-until rewriting at import; collapsing distinct temporal facts into "current state".

**Enables**: historical drill-down across taxonomy reforms; provable data lineage; trustworthy time-travel queries.

### 8. Two-tier import validation, with Fail Fast

Three categories of input data:

- **Unprincipled** — system cannot store coherently. Fail-fast, row skipped, actionable error.
- **Principled but missing** — foundation sound, data absent. Warning, row stored, soft error logged.
- **Valid** — silent acceptance.

**Why**: actionable feedback at import time prevents data-corruption pathways. Silent acceptance of broken data is the most expensive bug class.

**Forbids**: silent acceptance of broken data; vague "import failed" messages; "we'll fix it later" deferrals on bad source rows.

**Enables**: operators get actionable feedback at import; mapping gaps become continuous to-dos, not silent drift.

### 9. No surprises — Specify → Preview → Apply

Every operator-driven change to stored data goes through three steps. Reference-data edits (small, low-volume — crosswalk rows, settings, taxonomy entries) are immediate. Propagation to stored data requires an explicit subsequent action with a preview the operator confirms.

**Why**: trust depends on knowing what a change will do before it does it. Surprise mutation breaks trust and forces operators to fear configuration changes.

**Forbids**: silent backfills triggered by config edits; auto-scheduled mutation flips; "save and apply" buttons that combine specification with propagation.

**Enables**: trust; auditability; one mental model for any change — "what would this do? show me, then I'll decide".

### 10. Simple AND complex — complexity inside, simplicity outside

The system StatBus models is **really, really complex** — temporal validity, multi-version taxonomies, varying statistical variables across countries, entity-merge over time, derived rollups, RLS-enforced access at every layer. The implementation that absorbs this is itself huge: a custom PostgreSQL extension (`sql_saga`) for temporal data with foreign keys, written in optimized Rust; layered derived tables; exhaustive test coverage.

What the operator experiences is **simple**. They click "Import," they see a graph, they edit a value at a point in time, they trust the result.

The motto says **simple**, deliberately not **uncomplicated** and deliberately not **not-complex**. Embracing complexity is what affords the simplicity. Pretending the world is not complex creates surprise. Pretending the implementation can be uncomplicated creates fragility (missing features, brittle abstractions).

When two designs are compared:

- A design that pushes complexity into the implementation to keep the surface simple is preferred over one that pushes complexity into the operator's mental model.
- A design that is uncomplicated for the implementer but exposes that simplicity to the user as missing features or surprising edge cases is rejected.
- "Easy to build" never beats "easy to use."
- Under-investing in the engine to avoid implementation complexity is a violation, not a virtue.

Complexity that genuinely exists in the world (temporal validity, multi-version taxonomies, varying statistical variables across countries) is **made ambient**, not hidden. The temporal time picker in the top-right corner of the UI is the model: the temporal axis is always present, always part of the operator's context, but does not require explicit attention on every edit. The operator picks a context once; operations work within it.

This is the difference between **hidden** (surprise on discovery, "advanced mode" toggles, complexity revealed only when something breaks) and **ambient** (always visible, never demanding).

**Why**: NSO statisticians (the #1 audience) should not have to understand StatBus internals to use StatBus. The price of their simplicity is paid by the implementation, deliberately. Hiding complexity creates surprise; ambient complexity preserves the visible promise without cognitive tax. Refusing to absorb real complexity means pushing it onto the operator.

**Forbids**: exposing internal mechanism through the UI; rejecting hard-to-build features because they're hard to build when they would meaningfully simplify the operator's task; treating "simple implementation" and "simple use" as the same thing; "advanced mode" toggles that hide what should always be visible; under-investing in the engine when investment would buy operator simplicity.

**Enables**: adoption by NSOs with limited technical resources; principled refusal to push complexity onto the user; alignment with the motto.

### 11. Generic and declarative — never hard-code for a particular country

Country-specific rules are real, but they belong in **data**, not in **code**. When an NSO needs a particular algorithm (e.g., "size of statistical unit calculated from previous year's turnover and headcount, with country-specific thresholds"), the right shape is:

- A **rule table** where each strategy is declarative data.
- A **strategy selector** (UI button, REST endpoint, SQL function) so the user picks which strategy to apply.
- Execution that produces an **import job**: the proposed changes are visible as a preview before any data is mutated.

Schema-shape is declarative where it can be. The **path-on-region** pattern (LTREE) supports arbitrary hierarchy depth in one table; naïve designs use one table per region level and lose genericity. **JSONB for statistical variables** supports variable-shaped data with fixed columns; naïve designs use one column per variable and lose portability across countries.

The same discipline applies to **table granularity**. Tables collect the logically grouped attributes of an entity (legal_unit, establishment, location) — not one table per tracked value. The alternative (e.g., the Danish NSO's design with one table per attribute) loses comprehensibility: every query becomes a multi-way join across dozens of tables, and "wrap your head around it" becomes impossible. Some data redundancy (when one attribute changes but not another within the same entity) is the accepted cost of comprehensibility.

**Why**: StatBus serves many countries, each with idiosyncratic rules and varying statistical variables. Hard-coding any one country's choices means rewrites for the next country and brittleness for everyone. Declarative configuration + the import pipeline = generic code with country-specific behavior, on one codebase.

**Forbids**: hard-coded country-specific rules in SQL functions or app code; one-table-per-instance schemas (one table per region level; one column per statistical variable); algorithms that bake in one strategy when multiple are real-world legitimate; if-country-equals-X branches anywhere in the code.

**Enables**: a single codebase serving Albania, Norway, Morocco with their actual rules; new strategies added by data, not by code release; integrators see the same schema regardless of which country they query.

### 12. Names: uniform across layers, landed at once

Names are foundational. When something exists in StatBus, it has the same name everywhere — in the database, in the auto-generated PostgREST API, in the UI. Land the best name at once, because cosmetic renames break customer automation, and cross-layer uniformity is what makes naming compound into knowledge.

**There is no "we'll clean it up later" for names.** Once a name is exposed in the database, the API, or the UI, it lives in customer scripts, in muscle memory, in third-party documentation. The cost of changing it grows with every adopter. Naming debt is the worst kind of debt this system can carry; if a name is wrong, fix it before the next release, not later.

**Why**: customers integrate at the database level (the live-truth principle). Every renamed column, table, view, or function is a broken script somewhere in customer-land. And every cross-layer divergence — database column named one thing, UI labeling it differently — is a mental tax on every user. The Lego principle depends on names being learnable once and usable anywhere; that requires the names to actually match.

**Forbids**: rename-for-the-sake-of-renaming; "this word reads slightly better" commits without genuine semantic justification; speculative renames during refactors; database column names that diverge from API field names that diverge from UI strings; mapping layers that translate names between layers; **placeholder names with "TODO rename later" notes**.

**Enables**: customer automation that survives upgrades by default; learning that compounds across layers (master a concept in psql, use it in REST, recognize it in the UI); a culture where naming is debated when it matters (at design time) and treated as serious work.

### 13. Perfect migrations; deliberate change of public surfaces

There is no algorithmic rule for what can change in StatBus — it is judgment. The judgment uses a gradient:

- **Algorithms and implementation logic** change without notice. Customers see no change in observable behavior.
- **Adding non-destructive data** (new columns, new tables, new views) does not break existing automation.
- **Non-public schema changes** (`auth`, `import`, `worker` schemas — not exposed via PostgREST) are freer to evolve. But level-3 customers (direct DB access) can reach them; the responsibility to get the design right remains.
- **Public schema changes** (`public.*` — what PostgREST exposes) require care. Restructuring an established column, splitting a table, renaming a public surface — all hard.
- **Drastic public changes** require all three: (a) surfacing the change ahead of time, (b) transition time for customers to convert, (c) **perfect migrations** that guide people through with zero data loss.
- **The temporal foundation does not change.** It is the ground everything else stands on.

**Perfect migrations** means: both forward and backward, handling all realistic prior states (not just clean dev databases), tested on real data shapes, with documentation explaining what's changing and why. A migration that loses data — even data the operator might rarely look at — is a broken migration.

**Why**: customers integrate at the database level. The Lego principle works only if change respects that integration. A migration that loses data or fails on unusual-but-valid prior states breaks customer trust in a compounding way — once it happens, every future change is suspect.

**Forbids**: shipping a change to a public surface without a migration; migrations that drop data the operator might still need; "we'll write the migration later" (changes ship with their migrations); breaking changes shipped without prior surfacing or transition time.

**Enables**: customer automation that survives upgrades by default; the design space of "we can change anything if we do it right"; trust that upgrades won't surprise.

### 14. Add constraints, never defer known bugs

If a table can have duplicates that shouldn't exist, add UNIQUE. If a function has a race, fix it. The codebase has dozens of constraints by design.

**Why**: data corruption discovered post-hoc costs orders of magnitude more than data corruption prevented at the schema. "We'll add it later" is how silent corruption ships.

**Forbids**: TODO comments hiding race conditions; soft-handling constraint violations the design forbids; deferring known-bug fixes.

**Enables**: data corruption prevented at the schema layer; bugs surface immediately as constraint failures rather than as silent drift.

### 15. Tests are how trust is established — logical coverage, not regression accumulation

The system promises: **if you have the right data, you have the right calculations.** That promise is only believable when the tests pass. **Failing to have tests is a foundational failure**, not an engineering convenience — it breaks the promise the system makes to operators.

Tests are **logical**, not **regression-per-bug**. Adding one test per regression accumulates hundreds of brittle tests, each focused on a single past failure, none giving complete coverage of a real scenario. The discipline is to write tests that cover the **logical case** end-to-end — and the regression is naturally included. When a bug is fixed, the question is "does any existing logical-coverage test now exercise this path?" Often yes; sometimes the honest answer is "no, we were missing a logical case" and a new logical-coverage test fills a real gap.

Tests run **inside the database** (pg_regress), against the same engine the operator uses, with predictable input and predictable output. Test failures are signal. "Flaky" is a lazy excuse that masks real problems — concurrent test collision on shared resources, real code bugs, environment issues. Every failure has a real cause.

**Why**: the trust the system promises is operationalized only through tests. An untested or flakily-tested system can be correct only by accident. NSOs running statistical registries cannot operate on accident.

**Forbids**: skipping tests "for now"; one-test-per-regression accumulation patterns; flaky-quarantine without root-cause work; tests written to pass rather than to discriminate correctness; relying on manual verification of behavior the test suite should cover.

**Enables**: operator trust that "data correct → calculations correct" is provable, not asserted; a test suite that's a continuously-trustworthy guard; the freedom to refactor because tests catch real regressions.

### 16. Verify-first reasoning

Tool calls cost near-zero. Hypothetical reasoning costs thinking tokens AND risks wrong paths. When a tool can resolve a question, call the tool before drafting an answer. Cite file:line.

**Why**: in a system this size, no one's mental model is complete. The DB and the source are the ground truth; everything else is a fallible cache.

**Forbids**: speculative claims about code; trailing "verify before trusting" caveats; design proposals not grounded in observed code state.

**Enables**: faster correct answers; less debugging downstream; cumulative shared truth.

### 17. Cryptographic supply chain integrity

Every commit is signed. Every upgrade verifies signatures locally before applying. There is no shared privileged credential; every action has a traceable principal.

**Why**: NSO deployments are nationally-significant. A compromised upgrade path is a national security incident.

**Forbids**: trust-on-first-use; unauthenticated deploy paths; shared "deploy" credentials.

**Enables**: NSO compliance with national security requirements; provable origin for every line of code in production.

### 18. Pragmatic escape valves

Strict gates need narrow, audited bypasses. `SKIP_TEST_HARDENING=1`, `SKIP_TEST_INSTALL=1`, override-on-readiness-gate. Each bypass is logged; each is documented.

**Why**: rigidity makes operators reach for unaudited workarounds (manual psql, direct file edits). A documented bypass with audit trail is safer than an undocumented workaround.

**Forbids**: all-or-nothing release gates that have no override; bypasses without audit trail; bypasses not documented in the gate that uses them.

**Enables**: operator agency in emergencies; principled gates that don't become brittle.

---

## Adding to this list

A principle is added when:

- It has been *repeatedly* used as a decision filter across multiple campaigns.
- The pattern has been explicit enough to be named.
- Applying it as a filter would change the outcome of decisions.

Pre-emptive principles do not earn places here. The point is to name what is already load-bearing, not to legislate the future.

## Removing from this list

A principle is removed (or rewritten) when:

- The codebase has consistently violated it in well-reasoned ways.
- The principle has been superseded by a clearer one.

When the code and the principle disagree, the principle is on trial. Either fix the code or rewrite the principle. Don't carry both.
