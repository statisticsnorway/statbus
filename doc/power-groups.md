# Power Groups

Power groups model ownership/control hierarchies between legal units. They answer: "which legal units form a corporate group under a single controlling entity?"

## Why "Power Group" Instead of "Enterprise Group"

The EU statistical framework uses the term "Enterprise Group" for the top-level grouping of legally independent units under common control. STATBUS uses **Power Group** instead because the EU name confuses two distinct concepts:

- **Enterprise** = an economic grouping of legal units and their establishments, organised to produce goods or services. This is already a defined statistical unit in STATBUS.
- **Enterprise Group** (EU term) = the hierarchy of controlling influence between legal units — who controls whom.

Calling both concepts "Enterprise" creates ambiguity: does "Enterprise Group" mean a group of enterprises, or a group defined by enterprise-level relationships? Neither reading is accurate. The EU's Enterprise Group is really about **political power** — the chain of control from a top-level parent down through subsidiaries.

**Power Group** accurately describes what the grouping captures: the hierarchy of controlling influence between legal units. The name makes the concept self-evident without requiring knowledge of EU statistical terminology.

### Control vs Ownership

The two generic relationship types map naturally to the power group model:

- **Control** (`primary_influencer_only = TRUE`) — singular, structural. One entity controls another. The exclusion constraint guarantees at most one controller per influenced unit at any point in time. These relationships define hierarchy *direction* (root detection, tree traversal).

- **Ownership** (`primary_influencer_only = FALSE`) — shared, informational. Multiple shareholders can own stakes in the same entity. These relationships add 1:N edges.

**Both types contribute to power group formation.** All relationship types participate in clustering — any two legal units connected by any relationship type belong to the same power group. The `primary_influencer_only` flag remains important for:
- **Import set semantics**: 1:1 (primary) vs 1:N (non-primary) cardinality
- **Exclusion constraint**: structural single-root guarantee for primary types
- **Hierarchy direction**: root detection uses relationship direction for tree traversal

Non-primary relationships may create multi-root situations (since they are 1:N), which the clustering algorithm handles by grouping all connected LUs into the same component.

## Tables and Relationships

```
                    ┌──────────────────────┐
                    │   legal_rel_type      │
                    │   (reference data)    │
                    │───────────────────────│
                    │ id                    │
                    │ code                  │
                    │ primary_influencer_only│  ← controls cardinality (1:1 vs 1:N)
                    └──────────┬────────────┘
                               │ type_id
                               │
┌──────────────┐    ┌──────────┴────────────┐    ┌──────────────┐
│  legal_unit  │◄───│  legal_relationship    │───►│  legal_unit  │
│  (temporal)  │    │  (temporal)            │    │  (temporal)  │
│──────────────│    │───────────────────────│    │──────────────│
│ id           │    │ id                    │    │ id           │
│ valid_range  │    │ influencing_id ───────┘    │ valid_range  │
│ name         │    │ influenced_id  ────────────┘              │
│ ...          │    │ derived_power_group_id ┐                   │
└──────┬───────┘    │ derived_influenced_power_level            │
       │            │ primary_influencer_only (denormalized)    │
       │            │ valid_range           │                    │
       │            └──────────────────────┬┘                   │
       │                       │           │
       │            ┌──────────┴──────┐    │
       │            │ power_group      │◄───┘
       │            │ (timeless)       │
       │            │─────────────────│
       │            │ id              │
       │            │ ident (PG0001)  │   ← stable, human-friendly
       │            │ short_name      │   ← optional override
       │            │ name            │   ← optional override
       │            │ type_id         │   ← domestic/foreign etc.
       │            └────────┬────────┘
       │                     │
       │      ┌──────────────┼──────────────┐
       │      │              │              │
       │  ┌───┴──────────────────────┐      │
       │  │ power_root                │      │
       │  │ (sparse temporal,         │      │
       │  │  only cycle/multi PGs)    │      │
       │  │──────────────────────────│      │
       │  │ id (IDENTITY)            │      │
       │  │ power_group_id           │      │
       ├◄─│ derived_root_legal_unit_id│ FK  │
       │  │ derived_root_status      │      │
       └◄─│ custom_root_legal_unit_id│ FK (nullable)
          │ root_legal_unit_id       │ ← GENERATED
          │ valid_range (sql_saga)   │      │
          └──────────────────────────┘      │
                                            │
                             ┌─────────────────────────┐
                             │ power_group_membership   │
                             │ (view, reads materialized│
                             │  data from LR + PG)      │
                             │─────────────────────────│
                             │ power_group_id           │
                             │ power_group_ident        │
                             │ legal_unit_id            │
                             │ power_level              │
                             │ valid_range              │
                             └─────────────────────────┘
```

### Base Tables

**`legal_rel_type`** (reference data) — Defines relationship types. The `primary_influencer_only` boolean flag controls cardinality (1:1 vs 1:N) and the exclusion constraint, but all types contribute to power group formation. Each NSO configures its own types (see `samples/norway/brreg/` for an example).

**`legal_relationship`** (temporal, sql_saga) — Individual relationships between legal units. Each row says "unit A influences unit B during time range R". Key columns:
- `influencing_id` / `influenced_id` — FK to `legal_unit`
- `type_id` → `legal_rel_type` — determines semantics
- `primary_influencer_only` — denormalized from type, kept in sync by trigger + dual-column FK
- `derived_power_group_id` — set by `process_power_group_link` during import for all relationships in a cluster
- `derived_influenced_power_level` — BFS depth from root (NULL for cycles); set by `process_power_group_link`
- `valid_range` — temporal validity

**`power_group`** (timeless, like enterprise) — Once created, exists forever. Active status is derived at query time from `legal_relationship.valid_range`. Key columns:
- `ident` — stable human-friendly identifier (e.g., PG0001), auto-generated via base-36 sequence, never changes once assigned
- `short_name`, `name` — optional overrides (NULL = derive from root legal unit)
- `type_id` → `power_group_type` — classification (domestic/foreign, national/multinational)

**`power_root`** (sparse temporal, sql_saga) — Only cycle/multi-root power groups get entries. Single-root PGs derive their root from `power_group_membership WHERE power_level = 1` (no `power_root` entry needed). Populated by `process_power_group_link` during import.
- `derived_root_legal_unit_id` — algorithm-chosen root
- `derived_root_status` — `'cycle'` (root chosen from cyclic component) or `'multi'` (multiple roots merged into one PG)
- `custom_root_legal_unit_id` — NSO override (nullable); when set, overrides the derived root
- `root_legal_unit_id` — `GENERATED ALWAYS AS (COALESCE(custom_root, derived_root)) STORED` — one column to join on
- CHECK constraint enforces sparsity: only `cycle` and `multi` status values allowed

NSO edits to `custom_root_legal_unit_id` trigger change tracking via `base_change_log` (statement-level triggers), which feeds into the standard `collect_changes` → `derive_statistical_unit` pipeline.

### Views

All views read **materialized data** — no recursive CTEs at query time. Power levels and group assignments are pre-computed by `process_power_group_link` during import and stored on `legal_relationship`.

**`power_group_membership`** — UNION of two simple queries reading materialized data:
1. Roots (level 1): influencing LUs that are never influenced within the same PG
2. Non-roots: influenced LUs with their stored `derived_influenced_power_level`

Returns: `power_group_id`, `power_group_ident`, `legal_unit_id`, `power_level`, `valid_range`.

**`power_group_def`** — Aggregates `power_group_membership` to compute per-PG metrics: `depth` (longest path), `width` (direct children of root), `reach` (total controlled units).

**`legal_relationship_cluster`** — Trivial read: `SELECT id, derived_power_group_id FROM legal_relationship WHERE derived_power_group_id IS NOT NULL`. Cluster identity is materialized on the LR row itself.

**`power_group_active`** — Power groups with at least one relationship valid today (filtered by `valid_range @> CURRENT_DATE`).

## Core Concept: `primary_influencer_only`

The `legal_rel_type.primary_influencer_only` boolean flag controls cardinality and the exclusion constraint — **not** power group membership. All relationship types contribute to power group formation.

- **`primary_influencer_only = TRUE`**: Structurally 1:1. The exclusion constraint ensures each influenced unit has at most one influencer of this type at any time. These types define hierarchy direction (root detection, tree traversal).
- **`primary_influencer_only = FALSE`**: Structurally 1:N. Multiple influencers per influenced unit are allowed. These types add edges to the power group graph but don't determine hierarchy direction.

Each NSO defines its own relationship types with appropriate `primary_influencer_only` settings. See `samples/norway/brreg/` for Norway's BRREG role mappings as an example.

**Why not percentages?** Many data sources don't provide ownership percentages. The type-based approach works with any data source where relationship types structurally imply single-root control.

### Constraint Model

An **exclusion constraint** ensures that for `primary_influencer_only = TRUE` types, each influenced legal unit can have at most one influencer of a given type at any point in time:

```sql
SELECT sql_saga.add_unique_key(
    table_oid => 'public.legal_relationship',
    column_names => ARRAY['influenced_id', 'type_id'],
    key_type => 'predicated',
    predicate => 'primary_influencer_only IS TRUE',
    unique_key_name => 'legal_relationship_influenced_primary'
);
```

### Denormalized Column with Trigger

`legal_relationship.primary_influencer_only` is denormalized from `legal_rel_type` via:
- A **trigger** (`trg_legal_relationship_set_primary_influencer_only`) that auto-sets the value on INSERT or UPDATE of `type_id`
- A **dual-column FK** (`(type_id, primary_influencer_only) REFERENCES legal_rel_type(id, primary_influencer_only) ON UPDATE CASCADE`) that keeps the value in sync if the type definition changes

## Clustering and Hierarchy Algorithm

The algorithm runs during `process_power_group_link` (called during import) and materializes results on `legal_relationship` rows. There are no recursive CTEs at query time — all views read pre-computed data.

Reference implementation: `migrations/20260226000000_integrate_power_group_into_derive_pipeline.up.sql` lines 2130-2439.

### Step 1: Connected Components via Iterative Label Propagation

Groups all relationship-connected legal units into components. O(edges × depth).

1. Build **bidirectional edges** from all `legal_relationship` rows (both influencing→influenced and influenced→influencing)
2. Initialize each LU as its own component: `comp_id = lu_id`
3. **Iteratively propagate** the minimum `comp_id` along edges until convergence (max 100 iterations)
4. Result: `_lu_comp(lu_id, comp_id)` — every LU mapped to its component

All relationship types (primary and non-primary) contribute equally to component formation.

### Step 2: Cluster-to-Power-Group Mapping

1. Map each `legal_relationship` to its cluster via `_lu_comp`
2. Check if any relationship in the cluster already has `derived_power_group_id` (reuse existing PG)
3. Create new `power_group` records for clusters without one
4. Bulk-update `legal_relationship.derived_power_group_id` for all relationships
5. Detect and handle **cluster merges** (when multiple PGs converge to one cluster, consolidate to the largest)

### Step 3: BFS Power Levels from Roots

Computes hierarchy depth via breadth-first search. Materialized on `legal_relationship.derived_influenced_power_level`.

1. Detect **natural roots**: LUs that influence others but are never influenced within the same PG (the "no-parent" criterion)
2. Seed BFS with roots at level 1
3. Expand frontier along directed edges (influencing → influenced), assigning increasing levels
4. Store BFS level on each relationship: `derived_influenced_power_level = level`
5. Relationships whose influenced LU is never reached via BFS (cycles) get `NULL` level

### Step 4: Power Root Detection (Cycle/Multi-Root Handling)

Handles power groups with anomalous root structures. Populates the sparse `power_root` table.

1. Count natural roots per component:
   - **0 roots** → `derived_root_status = 'cycle'` — pick `comp_id` as synthetic root
   - **1 root** → no `power_root` entry needed (root derived from `power_group_membership` level 1)
   - **2+ roots** → `derived_root_status = 'multi'` — pick `MIN(lu_id)` as derived root
2. Build source rows with: `power_group_id`, `derived_root_legal_unit_id`, `derived_root_status`, preserved `custom_root_legal_unit_id`, union of all relationship `valid_range` values
3. Temporal merge into `power_root` via `sql_saga.temporal_merge()` (preserves NSO overrides across re-imports)

### Root Selection Priority

1. **`power_root.custom_root_legal_unit_id`** — NSO override (if set, overrides derived root via `COALESCE`)
2. **Derived root from algorithm** — `MIN(lu_id)` for multi-root, `comp_id` for cycle
3. For single-root PGs: root is simply the LU at power_level = 1 (no `power_root` entry)

## Design Scenarios

These scenarios motivate the clustering algorithm and the sparse `power_root` table.

### Scenario 1: Simple hierarchy (single root)

```
Timeline: 2020 ────────────────────── infinity
LU Alpha (id=1)  [2020, infinity)
LU Beta  (id=2)  [2020, infinity)
LR: Alpha->Beta  [2020, infinity)   control
```

Clustering: Alpha and Beta form one component. BFS: Alpha has no parent → root (level 1), Beta → level 2.

```
power_group_membership:
 lu_id | power_level | valid_range
     1 |           1 | [2020, infinity)
     2 |           2 | [2020, infinity)

power_root: (empty — single-root PGs have no entry)
```

### Scenario 2: Cycle

```
Timeline: 2020 ────────────────────── infinity
LR: Alpha(1)->Beta(2)  [2020, infinity)   control
LR: Beta(2)->Alpha(1)  [2020, infinity)   control   <- cycle!
```

Clustering: Alpha and Beta in same component. BFS: both are influenced → no natural root. Step 4 classifies as `'cycle'`, picks `comp_id` (= MIN(id) = Alpha) as derived root.

```
power_root:
 pg  | derived_root | derived_status | custom_root | root_lu | valid_range
 PG1 |            1 | cycle          |        NULL |       1 | [2020, infinity)
```

BFS levels are NULL (cycle prevents natural traversal). NSO can set `custom_root_legal_unit_id` to choose a specific root.

### Scenario 3: Multi-root

```
LU Alpha(1), Beta(2), Charlie(3)
LR: Alpha->Charlie  [2020, infinity)  control
LR: Beta->Charlie   [2020, infinity)  control
```

Clustering: all three in one component. BFS: Alpha and Beta are both natural roots (no parent). Step 4 classifies as `'multi'`, picks `MIN(id)` = Alpha.

```
power_root:
 pg  | derived_root | derived_status | root_lu | valid_range
 PG1 |            1 | multi          |       1 | [2020, infinity)
```

### Scenario 4: NSO temporal override

Starting from Scenario 2 (cycle). NSO edits `power_root.custom_root_legal_unit_id`:

```sql
UPDATE power_root
SET custom_root_legal_unit_id = 2  -- Beta as root
WHERE power_group_id = 1;
```

```
power_root after NSO edit:
 pg  | derived_root | derived_status | custom_root | root_lu | valid_range
 PG1 |            1 | cycle          |           2 |       2 | [2020, infinity)
```

The `root_legal_unit_id` is `COALESCE(custom_root, derived_root) = 2` (Beta). The statement-level triggers log the change to `base_change_log`, which feeds into `collect_changes` → `derive_statistical_unit` to recalculate timeline/statistical_unit.

**Validation**: Both `derived_root` and `custom_root` must be influencing LUs in the power group's legal relationships (enforced by `power_root_validate_root_membership` trigger).

### Scenario 5: Permanent cycle (no natural root ever)

```
LR: A->B [2020, infinity), B->C [2020, infinity), C->A [2020, infinity)
```

No natural root — all three are influenced. Classified as `'cycle'`, derived root = `MIN(id)`.

NSO can set `power_root.custom_root_legal_unit_id` to choose the correct root.

## Lifecycle

1. **Creation**: During import, `process_power_group_link` identifies clusters of connected relationships (all types) via iterative label propagation
2. **Assignment**: Each cluster gets a `power_group` record; all relationships in the cluster get `derived_power_group_id` set
3. **Reuse**: Existing power groups are reused when relationships change within the same cluster
4. **Merge**: When clusters merge (one hierarchy acquires another), relationships converge to the surviving power group
5. **Root tracking**: `power_root` records the derived root, status, and optional NSO override per time period — but only for cycle/multi groups (sparse)
6. **Dissolution**: When all relationships in a cluster are deleted, the PG becomes inactive (no active relationships)
7. **NSO override**: Editing `power_root.custom_root_legal_unit_id` triggers `derive_statistical_unit` to recalculate timeline and statistical_unit data

### Import Flow

The import system handles power groups as a **holistic step** (not batched per-row):

1. **`analyse_power_group_link`**: Builds combined graph of existing + new relationships (all types), computes clusters via iterative label propagation, assigns `cluster_root_legal_unit_id` to each data row
2. **`process_power_group_link`**: Creates/finds power groups for each cluster, updates `legal_relationship.derived_power_group_id` and `derived_influenced_power_level` for all relationships

### Change Detection and the Derive Pipeline

Legal relationship changes **only affect power groups** — they do NOT affect individual legal units or their connected enterprises. The change detection system is designed around this principle:

**`base_change_log` has a `power_group_ids` column.** When LR rows change, the `log_base_change` trigger logs `derived_power_group_id` directly into the `power_group_ids` column — not `influencing_id`/`influenced_id` as LU IDs. This prevents unnecessary LU/enterprise re-derivation.

**LR changes are only logged when `derived_power_group_id IS NOT NULL`.** Changes before PG assignment are invisible to the derive pipeline. This means the import flow is:

1. Insert/update LR rows (`derived_power_group_id = NULL`, no log entry)
2. `process_power_group_link` assigns PG IDs (UPDATE triggers fire, PG IDs logged)
3. `collect_changes` drains `base_change_log` — PG IDs come directly from the log
4. `derive_statistical_unit` receives PG IDs and refreshes power group statistical units

**The `ensure_collect_changes` trigger on LR also filters for `derived_power_group_id IS NOT NULL`** to prevent scheduling collection when there's nothing to collect. A separate DELETE trigger always schedules (since PG was assigned before deletion and the log captured it).

**Direct vs indirect PG lookup.** Previously, `collect_changes` computed PG IDs via an indirect lookup: drain LU IDs from the log, then query `legal_relationship WHERE influencing_id IN (...) OR influenced_id IN (...)`. This failed during initial import because PG IDs weren't assigned yet when the log was written. The direct approach — logging PG IDs into `base_change_log` at trigger time — eliminates this race condition.

## Future Directions

### Multi-Root Power Groups

Multi-root situations (where two disconnected sub-trees share a member) are now handled:
- `power_root` entries with `derived_root_status = 'multi'` are created automatically
- The algorithm picks one root (lowest ID or merge survivor) as `derived_root_legal_unit_id`
- NSO can override via `custom_root_legal_unit_id` to designate the correct root

Partnership structures (multiple co-equal partners) may need further evolution:
- The exclusion constraint would need to be relaxed for partnership types
- `power_level` semantics change: in a partnership, all partners are at level 1 (peers)

### Set-Import Semantics

Currently, imports are additive: new relationships are inserted, existing ones are updated. There's no mechanism to detect that a relationship was **removed** from the source.

**Completeness detection** would work like this:
1. The import declares itself "complete" for a given scope (e.g., "all parent-company relationships as of 2025-01-15")
2. After processing all rows, the system compares the imported set against existing relationships of the same type
3. Relationships that exist in the database but NOT in the import are candidates for temporal end-dating

### Activity Aggregation

Power groups should aggregate economic activity data from all member legal units:
- NACE activity categories (primary/secondary) based on the majority contributor
- Employment totals across all member establishments
- Revenue/turnover aggregation
- Physical location of the root legal unit as the PG's "headquarters"

This is partially implemented via `timeline_power_group_def` which already selects name, activity, region etc. from the root legal unit.

### `primary_influencer` Concept Evolution

The current boolean could evolve into a richer classification:
- `'primary_influencer'` (single root, current behavior)
- `'partnership_member'` (multi-root, future behavior)
- `'advisory'` (no PG formation, purely informational)

This would require changing `primary_influencer_only boolean` to an enum or a more structured classification.

### Relationship to `primary_for_enterprise`

The existing `legal_unit.primary_for_enterprise` flag designates which legal unit "represents" an enterprise. Similarly, power groups need a concept of which legal unit "represents" the group — currently this is always the root (power_level = 1). If multi-root PGs are implemented, a mechanism to designate the "primary" partner would be needed.
