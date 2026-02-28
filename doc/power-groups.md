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

## Current Implementation

### Core Concept: `primary_influencer_only`

Instead of percentage thresholds (e.g., "50% ownership = controlling"), power group formation is determined by **relationship type**. The `legal_rel_type.primary_influencer_only` boolean flag marks which types form power group hierarchies:

| Code | Name | `primary_influencer_only` | Forms PG? |
|------|------|--------------------------|-----------|
| HFOR | Hovedforetak (parent company) | TRUE | Yes |
| EIKM | Eierkommune (owner municipality) | TRUE | Yes |
| KOMP | Komplementar (general partner) | TRUE | Yes |
| DTPR | Deltaker pro-rata | FALSE | No |
| DTSO | Deltaker solidarisk | FALSE | No |

**Why not percentages?** BRREG (Norway's business register) does not provide ownership percentages. Fabricating percentages (e.g., 50% for partners) caused exclusion constraint violations when multiple partners shared ownership. The type-based approach accurately reflects the data source: HFOR/EIKM/KOMP are structurally guaranteed to be single-root relationships.

### Constraint Model

An **exclusion constraint** ensures that for `primary_influencer_only = TRUE` types, each influenced legal unit can have at most one influencer of a given type at any point in time:

```sql
-- sql_saga predicated unique key
SELECT sql_saga.add_unique_key(
    table_oid => 'public.legal_relationship',
    column_names => ARRAY['influenced_id', 'type_id'],
    key_type => 'predicated',
    predicate => 'primary_influencer_only IS TRUE',
    unique_key_name => 'legal_relationship_influenced_primary'
);
```

This guarantees **single-root** hierarchies — essential for the recursive CTE algorithm that discovers power group membership.

### Denormalized Column with Trigger

`legal_relationship.primary_influencer_only` is denormalized from `legal_rel_type` via:
- A **trigger** (`trg_legal_relationship_set_primary_influencer_only`) that auto-sets the value on INSERT or UPDATE of `type_id`
- A **dual-column FK** (`(type_id, primary_influencer_only) REFERENCES legal_rel_type(id, primary_influencer_only) ON UPDATE CASCADE`) that keeps the value in sync if the type definition changes

### Hierarchy Algorithm

The `legal_unit_power_hierarchy` view uses a recursive CTE:

1. **Base case**: Find root legal units — those that have `primary_influencer_only = TRUE` children but no `primary_influencer_only = TRUE` parent
2. **Recursive case**: Traverse down through `primary_influencer_only = TRUE` relationships, assigning increasing `power_level` (1 = root, 2 = direct subsidiary, etc.)
3. **Cycle prevention**: Tracked via `path` array; max depth 100

### Power Group Lifecycle

1. **Creation**: When `derive_power_groups()` runs, it identifies clusters of connected `primary_influencer_only` relationships via the hierarchy view
2. **Assignment**: Each cluster gets a `power_group` record; all relationships in the cluster get `power_group_id` set
3. **Reuse**: Existing power groups are reused when relationships change within the same cluster
4. **Dissolution**: When a relationship changes to a non-`primary_influencer_only` type, its `power_group_id` is cleared; if no relationships remain, the PG becomes inactive

### Import Flow

The import system handles power groups as a **holistic step** (not batched per-row):

1. **`analyse_power_group_link`**: Builds combined graph of existing + new relationships, computes clusters via recursive CTE, assigns `cluster_root_legal_unit_id` to each data row
2. **`process_power_group_link`**: Creates/finds power groups for each cluster, updates `legal_relationship.power_group_id` for both new and existing relationships

### Which BRREG Roles Are Imported

- **HFOR** (Hovedforetak): Parent company. Always 1:1. Forms PG.
- **EIKM** (Eierkommune): Owner municipality. Always 1:1. Forms PG.
- **KOMP** (Komplementar): General partner. Always 1:1. Forms PG.
- **DTPR** (Deltaker pro-rata): Proportional liability partner. Can be many-to-one. Imported but doesn't form PG.
- **DTSO** (Deltaker solidarisk): Joint liability partner. Can be many-to-one. Imported but doesn't form PG.

**Excluded**: KENK (Kontrollerende enhet) duplicates HFOR; KDEB (Komplementar/debitor) duplicates KOMP.

## Future Directions

### Multi-Root Power Groups (DTPR/DTSO)

Partnership structures (ANS, DA, KS) have multiple co-equal partners. A single DA might have three DTPR partners, each with proportional liability. These partnerships need power group representation but can't use the current single-root model.

**Challenges:**
- The hierarchy algorithm requires a single root for traversal. Multi-root requires a different discovery strategy — perhaps connected-component analysis rather than top-down traversal
- The exclusion constraint (`primary_influencer_only IS TRUE` → one influencer per type per influenced unit) would need to be relaxed or replaced for partnership types
- Naming: current PGs inherit the root unit's name. Multi-root groups need a composite naming strategy (e.g., "Partnership: A + B + C" or use the influenced unit's name)
- `power_level` semantics change: in a partnership, all partners are at level 1 (peers), not a hierarchy

**Possible approach:**
- Introduce a second flag like `partnership_member` on `legal_rel_type`
- Partnership PGs would be formed from the influenced unit (the DA/ANS) looking "up" at its partners
- The influenced unit becomes the PG's identity anchor
- All partners get `power_level = 1`, the partnership entity gets `power_level = 0` (or a "partnership_root" flag)

### Set-Import Semantics

Currently, imports are additive: new relationships are inserted, existing ones are updated. There's no mechanism to detect that a relationship was **removed** from the source.

**Completeness detection** would work like this:
1. The import declares itself "complete" for a given scope (e.g., "all HFOR relationships from BRREG as of 2025-01-15")
2. After processing all rows, the system compares the imported set against existing relationships of the same type
3. Relationships that exist in the database but NOT in the import are candidates for deletion

**Implementation sketch:**
- Add `action = 'delete'` as a valid import action (currently only 'use' and 'skip')
- After the holistic `analyse_power_group_link` step, a new step identifies "phantom deletes" — existing relationships whose `(influencing_tax_ident, influenced_tax_ident, type_code)` triple isn't present in the import
- These phantom rows get `action = 'delete'` and are processed as temporal end-dating (setting `valid_to` to the import date)
- This requires the import to declare its scope explicitly to avoid accidentally deleting relationships from other sources

### Activity Aggregation

Power groups should aggregate economic activity data from all member legal units:
- NACE activity categories (primary/secondary) based on the majority contributor
- Employment totals across all member establishments
- Revenue/turnover aggregation
- Physical location of the root legal unit as the PG's "headquarters"

This is partially implemented via `timeline_power_group_def` which already selects name, activity, region etc. from the root legal unit. Full aggregation across all members would require:
- Summing `stat_for_unit` values across member establishments
- Weighted activity category selection (by employment or revenue)
- Geographic scope indicators (single-region vs multi-region PGs)

### `primary_influencer` Concept Evolution

The current boolean could evolve into a richer classification:
- `'primary_influencer'` (single root, current HFOR/EIKM/KOMP behavior)
- `'partnership_member'` (multi-root, future DTPR/DTSO behavior)
- `'advisory'` (no PG formation, purely informational)

This would require changing `primary_influencer_only boolean` to an enum or a more structured classification.

### Relationship to `primary_for_enterprise`

The existing `legal_unit.primary_for_enterprise` flag designates which legal unit "represents" an enterprise. Similarly, power groups need a concept of which legal unit "represents" the group — currently this is always the root (power_level = 1). If multi-root PGs are implemented, a mechanism to designate the "primary" partner would be needed.

### Public/Private/Nonprofit Influence Analysis

Different legal forms have different influence patterns:
- **Public entities** (municipalities, state-owned): EIKM relationships, government control
- **Private companies**: HFOR, KOMP ownership hierarchies
- **Nonprofits/Foundations**: Control without ownership

Power groups could be tagged by their dominant influence pattern, enabling analysis of government vs private sector corporate structures.
