# Statbus Temporal Data Model: Timepoints, Timesegments, and Timelines

## Introduction

Statbus is designed to track the history of statistical units and their attributes over time. This requires a robust temporal data model. This document explains the core components of this model: `timepoints`, `timesegments`, and the derived `timeline_*` views and tables. Understanding these concepts is crucial for comprehending how historical data is stored, processed, and queried.

The system uses `valid_after` and `valid_to` dates to define validity periods. By convention, a record is considered valid on a given date `D` if `record.valid_after < D <= record.valid_to`. This represents an `(]` (exclusive start, inclusive end) interval.

## Core Concepts

### 1. Base Temporal Tables

Many core tables in Statbus are temporal, meaning they track changes over time. These tables typically include:
- `id`: A primary key for the specific version of the record.
- `unit_id` (or similar foreign key): Identifies the statistical unit this record pertains to.
- `valid_after`: The date *after which* this version of the record becomes valid (exclusive start of the interval).
- `valid_to`: The date *on which* this version of the record's validity ends (inclusive end of the interval).
- Other attribute columns specific to the table.

Examples: `establishment`, `legal_unit`, `activity`, `location`, `contact`, `stat_for_unit`.

A key characteristic of these temporal tables is that a single conceptual entity (e.g., a specific legal unit identified by its `id` or an external `tax_ident`) can have multiple rows in the table. Each row represents a distinct temporal slice or version of that conceptual unit's attributes over a specific period.

**Example of a Temporal Table (e.g., `public.legal_unit` or similar):**

| id  | valid_after | valid_to   | name     | attribute_value |
|-----|-------------|------------|----------|-----------------|
| 100 | 2021-12-31  | 2022-06-30 | 'LU 100' | 'Value A'       |
| 100 | 2022-06-30  | 2022-12-31 | 'LU 100' | 'Value B'       |
| 101 | 2022-03-31  | 2022-09-30 | 'LU 101' | 'Value C'       |
| 101 | 2022-12-31  | 'infinity' | 'LU 101' | 'Value C Mod'   |

In this example, reflecting tables like `public.legal_unit`:
- The `id` column (e.g., 100, 101) is the **conceptual identifier** for the legal unit. It is the same for all temporal slices of that same conceptual legal unit.
- Each **row** in the table represents a distinct **temporal slice** of the conceptual unit. For example, conceptual unit `100` has two temporal slices, and conceptual unit `101` also has two temporal slices (four rows in total shown for these conceptual units).
- To uniquely identify each slice (each row), a **composite primary key** is typically used, such as `(id, valid_after)`.
- Other columns (like `name`, `attribute_value`) store the attributes of the conceptual unit as they were during the period defined by `valid_after` and `valid_to` for that specific slice.

The `valid_from` column, where `valid_from = valid_after + 1 day`, represents the inclusive start of the validity period. While `valid_from` might be used for human-readable display or some specific queries, the core storage and temporal logic (especially in functions like `batch_insert_or_update_generic_valid_time_table` and views like `timepoints`) primarily operate on the `(valid_after, valid_to]` interval.

### 2. `public.timepoints` View

**Purpose**: The `timepoints` view is the foundational element for constructing a complete history. Its goal is to identify every single unique date that is significant for a given statistical unit. A "significant date" is any date that marks an endpoint of a validity interval `(valid_after, valid_to]`. These are:
    - All `valid_after` dates from the unit's own base table and its related temporal attributes.
    - All `valid_to` dates from the unit's own base table and its related temporal attributes.
    - These dates are considered within the lifespan of the parent unit and after appropriate temporal trimming.

**Construction**:
- For each `unit_type` (`establishment`, `legal_unit`, `enterprise`):
    - It collects all `valid_after` and `valid_to` dates from the unit's own base table (e.g., `public.establishment`).
    - It collects `valid_after` and `valid_to` dates from all related temporal tables (e.g., `public.activity`, `public.location`, `public.stat_for_unit` linked to that unit).
    - **Temporal Trimming**: When collecting dates from related entities, their validity periods `(child.valid_after, child.valid_to]` are first trimmed to ensure they fall within the validity period of the parent unit `(parent.valid_after, parent.valid_to]`. This is typically done using `GREATEST(parent.valid_after, child.valid_after)` for the new `valid_after` and `LEAST(parent.valid_to, child.valid_to)` for the new `valid_to`, ensuring the relationship is only considered during the time both entities were co-valid. The resulting interval must also be valid (i.e., `new_valid_after < new_valid_to`).
    - For higher-level units (like `legal_unit` or `enterprise`), it also considers timepoints derived from their constituent lower-level units and *their* related entities (e.g., activities of an establishment linked to a legal unit).
- The final step is `SELECT DISTINCT unit_type, unit_id, timepoint` to ensure that for each unit, every significant date appears only once. A timepoint here is a single date value that could be either a `valid_after` or a `valid_to` from some record.

### 3. `public.timesegments_def` View & `public.timesegments` Table

**Purpose**: Based on the unique, ordered `timepoints` for each unit, the `timesegments_def` view constructs continuous, non-overlapping time segments. Each segment represents a period during which the state of the unit and its direct relationships (in terms of which ones are active) is stable. The `public.timesegments` table materializes these segments.

**Construction (`timesegments_def`)**:
- It takes the unique, ordered `timepoints` for each `(unit_type, unit_id)`.
- It uses the `LEAD(timepoint) OVER (PARTITION BY unit_type, unit_id ORDER BY timepoint) AS next_timepoint` window function.
    - The `valid_after` column of a timesegment is the current `timepoint`.
    - The `valid_to` column of a timesegment is the `next_timepoint`.
- Rows where `valid_to IS NULL` (i.e., the last timepoint for a unit) or where `valid_after >= valid_to` are excluded, as they do not form valid `(exclusive, inclusive]` segments.

**Interval Convention in `timesegments`**:
- `timesegments.valid_after`: The date *after which* the segment begins (exclusive start).
- `timesegments.valid_to`: The date *on which* the segment ends (inclusive end).
- The actual period of validity for a timesegment is `(timesegments.valid_after, timesegments.valid_to]`. If `timesegments.valid_to` is 'infinity', the segment is open-ended towards the future.

The `public.timesegments` table is a physical table that stores the output of `timesegments_def`, primarily for performance and to provide a stable base for other timeline views. It has a primary key on `(unit_type, unit_id, valid_after)`.

### 4. Timeline Definition Views (e.g., `public.timeline_establishment_def`)

**Purpose**: These views aim to create a "flattened" or denormalized historical record for each unit, showing all its relevant attributes for each of its time segments.

**Construction (General Pattern)**:
1.  Start with `public.timesegments` for the specific `unit_type` (e.g., 'establishment'). This provides the `(unit_id, valid_after, valid_to)` for each segment.
2.  `INNER JOIN` to the unit's base table (e.g., `public.establishment es`) using `after_to_overlaps(t.valid_after, t.valid_to, es.valid_after, es.valid_to)`. This ensures that the version of the establishment record being joined was active during the timesegment `t`.
3.  `LEFT OUTER JOIN` to related temporal tables (e.g., `public.activity pa`, `public.location phl`). These joins also use `after_to_overlaps(t.valid_after, t.valid_to, related_table.valid_after, related_table.valid_to)` to fetch attributes from related entities that were active during that specific timesegment.

**The "Fan-Out" Problem and its Consequence**:
- A single timesegment `(t.unit_id, t.valid_after, t.valid_to)` represents a period where the *set* of active relationships is intended to be stable.
- However, if a unit has multiple distinct records in a related table that are *concurrently active* during this single timesegment, the `LEFT JOIN` operation will produce multiple output rows from the `timeline_*_def` view.
    - **Example**: An establishment `E1` has a timesegment from `2022-01-01` to `2022-12-31`.
        - Primary Activity `PA1` (Category X) for `E1` is active from `2022-01-01` to `2022-12-31`.
        - Primary Activity `PA2` (Category Y) for `E1` is *also* active from `2022-01-01` to `2022-12-31`.
    - The `LEFT JOIN` to `public.activity` for primary activities will match both `PA1` and `PA2` for this timesegment. This results in two rows in `timeline_establishment_def` for `E1` with the same `valid_after = '2021-12-31'` (which is `2022-01-01 - 1 day`), differing only in the activity-related columns.
- This duplication of the `(unit_type, unit_id, valid_after)` key in the output of the `_def` view is what causes the "ON CONFLICT DO UPDATE command cannot affect row a second time" error when trying to materialize these views into the physical `timeline_*` tables.

**Resolution Principle for Fan-Out (No Dedup Workarounds)**:
The `timeline_*_def` views are constructed so they output at most one row per `(unit_type, unit_id, valid_after)` by design. Do not use `DISTINCT`, `DISTINCT ON`, `GROUP BY`, or similar “collapse after the fact” techniques at the materialization step to hide duplicates. Instead:
- Ensure `timepoints` and `timesegments` correctly capture all change boundaries so that a timesegment is the smallest non-changing unit of state. If any relationship change is missing from `timepoints`, fix it there first.
- Where relationships are truly multi-valued within a timesegment (e.g., multiple tags by design, or only 1 primary by design), model that multiplicity as part of the single row’s state, using explicit aggregation scoped to the current timesegment in lateral subqueries (e.g., arrays/JSON objects) without any LIMIT since it is either an aggregation or by design a single row to be found. This is not a workaround; it encodes domain multiplicity as a single-valued attribute of the timeline row.
- Where relationships are intended to be single-valued (e.g., “primary” activity, or a single physical location per timesegment), enforce this deterministically in the join logic using a well-defined ORDER BY inside a lateral subquery, or correct upstream data/integrity so that the invariant holds and *NEVER* use `LIMIT 1`.
This approach guarantees correctness: one row per timesegment key, with multi-valued attributes represented explicitly, and no reliance on post hoc deduplication that could mask logical errors.
- If there is still an error, it is an error in the import causing the duplication or a constraint error allowing it, so identify the data that cause the error and then go back and find the root cause in the relevant analysis or processing procedure.

### 5. Materialized Timeline Tables (e.g., `public.timeline_establishment`)

**Purpose**: These are physical tables that store the (ideally unique per conflict key) output of their corresponding `timeline_*_def` views. They provide a performant way to query the historical state of units.

**Conflict Target**: The primary key and conflict target for these tables is `(unit_type, unit_id, valid_after)`.

**Refresh Mechanism**: Functions like `public.timeline_establishment_refresh(p_valid_after, p_valid_to)` are used to update these tables. They typically:
1.  Create a temporary table populated from the `timeline_*_def` view for a given date range.
2.  Delete rows from the main timeline table that are in the date range but not in the temporary table.
3.  `INSERT` rows from the temporary table into the main timeline table, using `ON CONFLICT (unit_type, unit_id, valid_after) DO UPDATE SET ...` to update existing rows. This is where the "cannot affect row a second time" error occurs if the `_def` view produces duplicates for the conflict key.

## Implications

-   **Data Integrity**: The accuracy of `timepoints` and `timesegments` is fundamental. If a significant date is missed, segments might incorrectly span periods of change, leading to inaccurate historical snapshots.
-   **Reporting**: Reports querying historical states rely on the `timeline_*` tables. The fan-out issue in the `_def` views must be resolved to ensure these tables are correctly populated and reflect the true state of units over time.
-   **Performance**: While denormalized, the timeline tables can become large. Efficient indexing and partitioning strategies (if applicable) are important. The `after_to_overlaps` function is crucial for efficient temporal joins. It is implemented using PostgreSQL's `daterange` type and the `&&` (overlaps) operator, which allows the query planner to leverage specialized GIST indexes for high performance.

By addressing the fan-out in the definition views, the import system and subsequent analytics can reliably build and maintain accurate historical records of all statistical units.
