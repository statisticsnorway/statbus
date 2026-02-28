# STATBUS Data Architecture

## Three Layers

1. **Import** — writes data to base tables (`legal_unit`, `establishment`, `legal_relationship`, `power_group`, `enterprise`, etc.)

2. **statistical_unit** — derived high-speed view of base table data, convenient for queries and aggregations. Built from `timepoints → timesegments → timeline_* → statistical_unit`.

3. **Reports** — high-speed reporting derived from `statistical_unit`: `statistical_*_history`, `statistical_*_facet`, etc.

## Key Invariant

All derived tables (layers 2 and 3) can be **cleared and recreated** from base tables at any time. The derive pipeline is idempotent — running it produces the same result regardless of prior state.

## Consequence for Pipeline Design

- Only **import** modifies base tables.
- `derive_statistical_unit` **reads** base tables and writes derived tables.
- `derive_reports` **reads** `statistical_unit` and writes report tables.

Any operation that creates or modifies base table records (e.g., creating `power_group` records, setting `legal_relationship.power_group_id`) belongs in the **import** layer, not in the analytics pipeline.
