# Statbus Temporal Data Model: Timepoints, Timesegments, and Timelines

## Introduction

Statbus is designed to track the history of statistical units and their attributes over time. This requires a robust temporal data model. This document explains the core components of this model: `timepoints`, `timesegments`, and the derived `timeline_*` views and tables. Understanding these concepts is crucial for comprehending how historical data is stored, processed, and queried.

The system uses a `[valid_from, valid_until)` temporal model, which is inclusive of the start date and exclusive of the end date. This is the standard for temporal data and is managed by the `sql_saga` extension. For convenience, a synchronized `valid_to` (inclusive end date) is also maintained.

## Core Concepts

### 1. Base Temporal Tables

Many core tables in Statbus are temporal, meaning they track changes over time. These tables are managed by `sql_saga` and include:
- `id`: The **conceptual identifier** for the unit. This value is the same for all temporal slices of a single conceptual unit.
- `valid_from`: The date on which this version of the record becomes valid (inclusive start of the interval).
- `valid_until`: The date on which this version of the record's validity ends (exclusive end of the interval).
- `valid_to`: A human-readable, inclusive end date, automatically kept in sync with `valid_until` by `sql_saga`.
- Other attribute columns specific to the table.

Examples: `establishment`, `legal_unit`, `activity`, `location`, `contact`, `stat_for_unit`.

A key characteristic is that a single conceptual entity (e.g., a legal unit) has multiple rows, each representing a distinct temporal slice of its history. To uniquely identify each slice, the primary key is typically a composite of the conceptual identifier and a temporal column, like `(id, valid_from)`.

**Example of a Temporal Table (`public.legal_unit`):**

| id  | valid_from | valid_until | valid_to   | name     | attribute_value |
|-----|------------|-------------|------------|----------|-----------------|
| 100 | 2022-01-01 | 2022-07-01  | 2022-06-30 | 'LU 100' | 'Value A'       |
| 100 | 2022-07-01 | 2023-01-01  | 2022-12-31 | 'LU 100' | 'Value B'       |
| 101 | 2022-04-01 | 2022-10-01  | 2022-09-30 | 'LU 101' | 'Value C'       |
| 101 | 2023-01-01 | 'infinity'  | 'infinity' | 'LU 101' | 'Value C Mod'   |

### 2. `public.timepoints` View

**Purpose**: The `timepoints` view is the foundational element for constructing a complete history. Its goal is to identify every single unique date that marks the start or end of a validity interval for a given statistical unit.

**Construction**:
- For each `unit_type` (`establishment`, `legal_unit`, `enterprise`):
    - It collects all `valid_from` and `valid_until` dates from the unit's own base table and all its related temporal attribute tables (`activity`, `location`, etc.).
    - **Temporal Trimming**: Dates from related entities are considered only within the lifespan of their parent unit.
- The final step is `SELECT DISTINCT unit_type, unit_id, timepoint` to get a clean, unique list of all significant dates for each unit.

### 3. `public.timesegments_def` View & `public.timesegments` Table

**Purpose**: Based on the unique, ordered `timepoints` for each unit, the `timesegments_def` view constructs continuous, non-overlapping time segments. Each segment represents an **atomic** period during which the state of the unit and its direct relationships is stable. The `public.timesegments` table materializes these segments for performance.

**Construction (`timesegments_def`)**:
- It takes the unique, ordered `timepoints` for each `(unit_type, unit_id)`.
- It uses the `LEAD(timepoint) OVER (PARTITION BY unit_type, unit_id ORDER BY timepoint) AS next_timepoint` window function.
    - The `valid_from` column of a timesegment is the current `timepoint`.
    - The `valid_until` column of a timesegment is the `next_timepoint`.
- Rows where `valid_until IS NULL` or where `valid_from >= valid_until` are excluded.

The `public.timesegments` table is a physical table that stores the output of `timesegments_def`. It has a primary key on `(unit_type, unit_id, valid_from)`.

### 4. Timeline Definition Views (e.g., `public.timeline_establishment_def`)

**Purpose**: These views create a "flattened" or denormalized historical record for each unit, showing all its relevant attributes for each of its atomic time segments.

**Construction (General Pattern)**:
1.  Start with `public.timesegments` for the specific `unit_type`. This provides the `(unit_id, valid_from, valid_until)` for each segment.
2.  `INNER JOIN` to the unit's base table (e.g., `public.establishment es`) using a temporal overlap condition: `(t.valid_from, t.valid_until) OVERLAPS (es.valid_from, es.valid_until)`.
3.  `LEFT OUTER JOIN` to related temporal tables (e.g., `public.activity`, `public.location`) using the same `OVERLAPS` logic to fetch attributes that were active during that specific timesegment.

**The "Fan-Out" Problem and its Resolution**:
- A single timesegment represents a period where the *set* of active relationships should be stable.
- If a unit has multiple distinct records in a related table concurrently active during a single timesegment (e.g., two primary activities), the `LEFT JOIN` will produce multiple output rows for the same timesegment key `(unit_type, unit_id, valid_from)`.
- This duplication causes errors during materialization into the physical `timeline_*` tables.

**Resolution Principle (No Dedup Workarounds)**:
The `timeline_*_def` views are designed to output at most one row per `(unit_type, unit_id, valid_from)`. We do not use `DISTINCT` or `GROUP BY` to hide duplicates. Instead:
- We ensure `timepoints` and `timesegments` correctly capture all change boundaries.
- Where relationships are truly multi-valued (e.g., multiple tags), we model that multiplicity as part of the single row’s state using explicit aggregation in lateral subqueries (e.g., `jsonb_agg`).
- Where relationships are intended to be single-valued (e.g., "primary" activity), we enforce this deterministically in the join logic, typically inside a lateral subquery.
- An error during materialization is a signal of a data integrity or import logic problem that must be fixed at its root, not hidden with deduplication.

### 5. Materialized Timeline Tables (e.g., `public.timeline_establishment`)

**Purpose**: These are physical tables that store the output of their corresponding `timeline_*_def` views, providing a high-performance source for querying the historical state of units.

**Conflict Target**: The primary key and conflict target for these tables is `(unit_type, unit_id, valid_from)`.

**Refresh Mechanism**: Functions like `public.timeline_establishment_refresh(p_valid_from, p_valid_until)` are used to update these tables by calculating changes from the `_def` view and applying them via `INSERT ... ON CONFLICT ... DO UPDATE`.

## Implications

-   **Data Integrity**: The accuracy of `timepoints` is fundamental. A missed date leads to incorrect timesegments and inaccurate historical snapshots.
-   **Reporting**: Reports querying historical states rely on the `timeline_*` tables. The fan-out issue must be resolved in the `_def` views to ensure these tables are correctly populated.
-   **Performance**: The `OVERLAPS` operator on `(valid_from, valid_until)` pairs is crucial for efficient temporal joins and can be accelerated by GiST indexes on `daterange` types, which are automatically created by `sql_saga`.
