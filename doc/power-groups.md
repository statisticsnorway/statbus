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

- **Control** (`primary_influencer_only = TRUE`) — singular, structural. One entity controls another. These relationships form the power group *hierarchy* (tree). The exclusion constraint guarantees single-root: each influenced unit can have at most one controller at any point in time.

- **Ownership** (`primary_influencer_only = FALSE`) — shared, informational. Multiple shareholders can own stakes in the same entity. These relationships enrich the *influence graph* but do not determine hierarchy.

Future: ownership relationships enable conglomerate analysis beyond direct control — mapping the full web of financial interests across corporate structures.

## Tables and Relationships

```
                    ┌──────────────────────┐
                    │   legal_rel_type      │
                    │   (reference data)    │
                    │───────────────────────│
                    │ id                    │
                    │ code                  │
                    │ primary_influencer_only│  ← determines PG formation
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
│ ...          │    │ power_group_id ──────┐                    │
└──────────────┘    │ primary_influencer_only (denormalized)    │
                    │ valid_range           │                    │
                    └──────────────────────┬┘                   │
                               │           │
                    ┌──────────┴──────┐    │
                    │ power_group      │◄───┘
                    │ (timeless)       │
                    │─────────────────│
                    │ id              │
                    │ ident (PG0001)  │   ← stable, human-friendly
                    │ short_name      │   ← optional override
                    │ name            │   ← optional override
                    │ type_id         │   ← domestic/foreign etc.
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
    ┌─────────┴──────────────┐              │
    │ power_root              │              │
    │ (sparse temporal,       │              │
    │  only cycle/multi PGs)  │              │
    │─────────────────────────│              │
    │ id (IDENTITY)           │              │
    │ power_group_id          │              │
    │ derived_root_legal_unit_id│            │
    │ derived_root_status     │              │
    │ custom_root_legal_unit_id│ ← NSO override
    │ root_legal_unit_id      │ ← GENERATED
    │ valid_range (sql_saga)  │              │
    └─────────────────────────┘              │
                                             │
                              ┌──────────────┴───┐
                              │ power_hierarchy   │
                              │ (view, read-only) │
                              │──────────────────│
                              │ legal_unit_id     │
                              │ root_legal_unit_id│
                              │ power_level       │
                              │ valid_range       │
                              │ path              │
                              │ is_cycle          │
                              └──────────────────┘
```

### Base Tables

**`legal_rel_type`** (reference data) — Defines relationship types. The `primary_influencer_only` boolean flag is the key: types with `TRUE` form power group hierarchies, types with `FALSE` are informational only. Each NSO configures its own types (see `samples/norway/brreg/` for an example).

**`legal_relationship`** (temporal, sql_saga) — Individual relationships between legal units. Each row says "unit A influences unit B during time range R". Key columns:
- `influencing_id` / `influenced_id` — FK to `legal_unit`
- `type_id` → `legal_rel_type` — determines semantics
- `primary_influencer_only` — denormalized from type, kept in sync by trigger + dual-column FK
- `power_group_id` — set by `process_power_group_link` during import, NULL for non-primary relationships
- `valid_range` — temporal validity

**`power_group`** (timeless, like enterprise) — Once created, exists forever. Active status is derived at query time from `legal_relationship.valid_range`. Key columns:
- `ident` — stable human-friendly identifier (e.g., PG0001), auto-generated via base-36 sequence, never changes once assigned
- `short_name`, `name` — optional overrides (NULL = derive from root legal unit)
- `type_id` → `power_group_type` — classification (domestic/foreign, national/multinational)

**`power_root`** (sparse temporal, sql_saga) — Only cycle/multi-root power groups get entries. Single-root PGs derive root from `power_hierarchy WHERE power_level = 1`. Populated by `process_power_group_link` during import.
- `derived_root_legal_unit_id` — algorithm-chosen root
- `derived_root_status` — `'cycle'` (root chosen from cyclic component) or `'multi'` (multiple roots merged into one PG)
- `custom_root_legal_unit_id` — NSO override (nullable); when set, overrides the derived root
- `root_legal_unit_id` — `GENERATED ALWAYS AS (COALESCE(custom_root, derived_root)) STORED` — one column to join on
- CHECK constraint enforces sparsity: only `cycle` and `multi` status values allowed

NSO edits to `custom_root_legal_unit_id` trigger `derive_statistical_unit` directly via the `power_root_derive_trigger`.

### Views

**`power_hierarchy`** — Two-phase recursive CTE (see algorithm below). Returns every legal unit's position in the hierarchy: `legal_unit_id`, `root_legal_unit_id`, `power_level`, `valid_range`.

**`power_group_def`** — Aggregates hierarchy to compute per-root metrics: `depth` (longest path), `width` (direct children), `reach` (total controlled units).

**`legal_relationship_cluster`** — Maps each `primary_influencer_only` relationship to its cluster root, used by `process_power_group_link` to assign `power_group_id`.

**`power_group_membership`** — Joins `power_group` ↔ `power_hierarchy` to answer "which legal units belong to which power group at what level".

**`power_group_active`** — Power groups with at least one relationship valid today.

## Core Concept: `primary_influencer_only`

Instead of percentage thresholds (e.g., "50% ownership = controlling"), power group formation is determined by **relationship type**. The `legal_rel_type.primary_influencer_only` boolean flag marks which types form power group hierarchies.

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

## Two-Phase Hierarchy Algorithm

The `power_hierarchy` view uses a two-phase recursive CTE to handle both clean hierarchies and cycles/multi-root structures.

### Phase 1: Natural Roots

Uses `range_agg` multirange subtraction to compute exact temporal root periods:

1. For each legal unit that has children (`primary_influencer_only = TRUE` outgoing edges), subtract the periods where it also has a parent (incoming edge)
2. The remaining periods are when the unit is a **natural root**
3. Recursively traverse downward, assigning increasing `power_level` (1 = root, 2 = direct subsidiary, etc.)
4. Cycle detection via `path` array prevents infinite recursion; max depth 100

### Phase 2: Orphan/Cycle Connected Components

Handles nodes that participate in primary edges but were not covered by Phase 1 (typically cycles):

1. Identify **orphan periods** — times when a node has primary edges but no Phase 1 assignment
2. **Bidirectional flood fill** groups orphans into connected components
3. Pick root per component using priority:
   - **`power_root.custom_root_legal_unit_id`** — NSO-chosen root (overrides algorithm for known groups)
   - **Adjacent Phase 1 root** — temporal continuity with nearest natural-root period
   - **MIN(id)** — deterministic fallback when no natural root ever existed
4. Directed traversal from chosen root, same as Phase 1

## Design Scenarios

These scenarios motivated the two-phase algorithm and the sparse `power_root` table.

### Scenario 1: Simple hierarchy (single root)

```
Timeline: 2020 ────────────────────── infinity
LU Alpha (id=1)  [2020, infinity)
LU Beta  (id=2)  [2020, infinity)
LR: Alpha->Beta  [2020, infinity)   control, primary_influencer_only=TRUE
```

Phase 1: Alpha has child Beta, no parent — root for full lifetime.

```
power_hierarchy:
 lu_id | root | level | valid_range
     1 |    1 |     1 | [2020, infinity)
     2 |    1 |     2 | [2020, infinity)

power_root: (empty — single-root PGs have no entry; root derived from power_hierarchy level 1)
```

### Scenario 2: Cycle forming later

```
Timeline: 2020 ──── 2023 ────────── infinity
LR: Alpha(1)->Beta(2)  [2020, infinity)   control
LR: Beta(2)->Alpha(1)  [2023, infinity)   control   <- cycle!
```

Phase 1 uses `range_agg` subtraction:
- Alpha root periods: `[2020, infinity) - [2023, infinity)` = **`[2020, 2023)`**
- Beta root periods: `[2020, infinity) - [2020, infinity)` = **empty** (always has a parent)

Phase 1 covers `[2020, 2023)` only. Phase 2 finds orphans for `[2023, infinity)`:
- Adjacent root from Phase 1: Alpha was root for `[2020, 2023)` — use Alpha
- Hierarchy: Alpha(level=1) -> Beta(level=2) for both periods

```
power_root: (only cycle period gets an entry — sparse)
 pg  | derived_root | derived_status | custom_root | root_lu | valid_from | valid_until
 PG1 |            1 | cycle          |        NULL |       1 | 2023-01-01 | infinity
```

Before cycle: no `power_root` entry (single-root, derived from hierarchy level 1).
After cycle: `power_root` entry with `derived_root_status = 'cycle'`. NSO can override via `custom_root_legal_unit_id`.

### Scenario 3: Temporary cycle (adjacent-root heuristic)

```
Timeline: 2020 ──── 2023 ──── 2025 ──── infinity
LR: Beta(2)->Alpha(1)   [2020, infinity)       <- Beta controls Alpha
LR: Alpha(1)->Beta(2)   [2023, 2025)           <- temporary cycle
```

Phase 1: Beta root periods = `[2020, infinity) - [2023, 2025)` = `{[2020, 2023), [2025, infinity)}`
- Beta is root in Phase 1 for both non-cycle periods.

Phase 2 for `[2023, 2025)`:
- `MIN(id)` would wrongly pick Alpha(1) — **breaking continuity**
- **Adjacent-root heuristic**: Beta was root in adjacent `[2020, 2023)` — use Beta
- Hierarchy: Beta(level=1) -> Alpha(level=2) — consistent across ALL periods

```
power_root: (only cycle period gets an entry — sparse)
 pg  | derived_root | derived_status | root_lu | valid_from | valid_until
 PG1 |            2 | cycle          |       2 | 2023-01-01 | 2025-01-01
```

Non-cycle periods have no `power_root` entry (Beta is natural root from hierarchy). Power levels are consistent — Beta is always level 1.

### Scenario 4: Multi-root

```
LU Alpha(1), Beta(2), Charlie(3)
LR: Alpha->Charlie  [2020, infinity)  primary_influencer_only=TRUE
LR: Beta->Charlie   [2020, infinity)  primary_influencer_only=TRUE
```

Phase 1: Both Alpha and Beta are natural roots (children, no parents). Charlie appears under both. `process_power_group_link` merge logic detects shared members — one PG.

```
power_root: (multi-root gets an entry — sparse)
 pg  | derived_root | derived_status | root_lu | valid_from | valid_until
 PG1 |            1 | multi          |       1 | 2020-01-01 | infinity
```

### Scenario 5: NSO temporal override

Starting from Scenario 3 (Beta->Alpha, temporary cycle `[2023, 2025)`). NSO edits `power_root.custom_root_legal_unit_id` via the `power_root__for_portion_of_valid` view:

```sql
INSERT INTO power_root__for_portion_of_valid (power_group_id, custom_root_legal_unit_id, valid_from, valid_to)
VALUES (1, 1, '2023-01-01', '2025-01-01');  -- Alpha as custom root for cycle period
```

```
power_root after NSO edit:
 pg  | derived_root | derived_status | custom_root | root_lu | valid_from | valid_until
 PG1 |            2 | cycle          |           1 |       1 | 2023-01-01 | 2025-01-01
```

The `root_legal_unit_id` is `COALESCE(custom_root, derived_root) = 1` (Alpha). Phase 2 reads this and assigns Alpha as root for the cycle period. `power_root_derive_trigger` fires and enqueues `derive_statistical_unit` to recalculate timeline/statistical_unit.

**Override only affects the ambiguous period it targets.** Natural single-root periods have no `power_root` entry and are unaffected.

### Scenario 6: Permanent cycle (no natural root ever)

```
LR: A->B [2020, infinity), B->C [2020, infinity), C->A [2020, infinity)
```

No natural root ever — Phase 1 produces nothing. Phase 2:
- No adjacent Phase 1 root — fall back to MIN(id)
- Power levels assigned from MIN(id)

NSO can set `power_root.custom_root_legal_unit_id` to choose the correct root.

### Root Selection Priority (Phase 2)

1. **`power_root.custom_root_legal_unit_id`** — NSO override (read by Phase 2 for known power groups)
2. **Adjacent-period natural root** — root from closest Phase 1 period for same component
3. **MIN(id)** — deterministic fallback when no natural root ever existed

## Lifecycle

1. **Creation**: During import, `process_power_group_link` identifies clusters of connected `primary_influencer_only` relationships via the `legal_relationship_cluster` view
2. **Assignment**: Each cluster gets a `power_group` record; all relationships in the cluster get `power_group_id` set
3. **Reuse**: Existing power groups are reused when relationships change within the same cluster
4. **Merge**: When clusters merge (one hierarchy acquires another), relationships converge to the surviving power group
5. **Root tracking**: `power_root` records the derived root, status, and optional NSO override per time period — but only for cycle/multi groups (sparse)
6. **Dissolution**: When a relationship changes to a non-`primary_influencer_only` type, its `power_group_id` is cleared; if no relationships remain, the PG becomes inactive
7. **NSO override**: Editing `power_root.custom_root_legal_unit_id` triggers `derive_statistical_unit` to recalculate timeline and statistical_unit data

### Import Flow

The import system handles power groups as a **holistic step** (not batched per-row):

1. **`analyse_power_group_link`**: Builds combined graph of existing + new relationships, computes clusters via recursive CTE, assigns `cluster_root_legal_unit_id` to each data row
2. **`process_power_group_link`**: Creates/finds power groups for each cluster, updates `legal_relationship.power_group_id` for both new and existing relationships

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
