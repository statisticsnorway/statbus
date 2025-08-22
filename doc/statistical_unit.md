# StatBus Data Derivation Architecture: From Base Tables to `statistical_unit`

This document outlines the multi-layered architecture used to derive the `public.statistical_unit` view, which is the primary data source for the API. Understanding this flow is crucial for ensuring both correctness and performance.

The architecture is designed to solve the complex problem of temporal data denormalization by breaking it down into distinct, manageable layers. Each layer has a specific responsibility.

## 1. High-Level Architecture

The data flows through the following layers:

`Base Tables` -> `timepoints` (View) -> `timesegments` (Table) -> `timeline_*` (Tables) -> `statistical_unit` (Table)

This layered approach ensures that complex calculations are performed once at the correct level and materialized at each step for performance and correctness.

## 2. Layer-by-Layer Breakdown

### 2.1. Base Tables

-   **Purpose**: The source of all primary data (e.g., `public.establishment`, `public.legal_unit`, `public.activity`, `public.location`).
-   **Temporality**: Most base tables are temporal, containing `valid_from` and `valid_to` columns to track when a particular record is valid.
-   **Responsibility**: To store the raw, normalized data as accurately as possible.

### 2.2. `public.timepoints` (View)

-   **Purpose**: To identify every single date that represents a significant change for a statistical unit or any of its direct child entities.
-   **Logic**: It performs a **global** `UNION` across all relevant base tables (`legal_unit`, `establishment`, `activity`, `location`, `contact`, etc.) to collect every `valid_from` and `valid_to` date.
-   **Responsibility**: **Correctness**. The accuracy of this view is the absolute foundation of the system. If any date of change is missed here, it leads to overly broad time segments, which is the direct cause of the "fan-out" data duplication bug.

### 2.3. `public.timesegments` (Table)

-   **Purpose**: To transform the global list of change-dates from `timepoints` into **atomic**, non-overlapping historical periods for each unit.
-   **Atomicity**: An atomic segment is the smallest possible slice of time during which the state of a unit and all its directly related child entities is constant. Any change to any related entity must create a new `timepoint`, which in turn creates new segment boundaries. This is the core principle that prevents fan-out.
-   **Logic**: It uses `lead()` window functions over the `timepoints` data to create distinct time-slices, each with a `valid_after` and `valid_to` boundary.
-   **Responsibility**: **Performance and Atomicity**. This table materializes the atomic time-slices, which is a relatively expensive calculation. The `timesegments_refresh` function keeps this table up-to-date.

### 2.4. `timeline_*` Tables (Custom Materialization)

-   **Purpose**: This is the primary denormalization and materialization layer. For each distinct time-slice defined in `timesegments`, this layer creates and stores a single, complete record representing the state of a unit *during that specific period*.
-   **Architecture**: This is a custom materialization pattern, more efficient than a standard `MATERIALIZED VIEW`. For each unit type (e.g., `establishment`), there are three components:
    1.  `public.timeline_establishment_def` (View): Contains the complex `SELECT` query that joins `timesegments` with all relevant base tables (`activity`, `location`, etc.) to calculate the fully denormalized state of an establishment for every one of its time-slices.
    2.  `public.timeline_establishment` (Table): The destination table that stores the materialized results from the `_def` view. This table is the direct source for the final `statistical_unit` view.
    3.  `public.timeline_establishment_refresh()` (Function): The procedure that populates the table. It calculates the new state using the `_def` view, diffs it against the existing data in the `timeline_establishment` table, and then performs the necessary `INSERT`s, `UPDATE`s, and `DELETE`s.
-   **Efficiency**: The key advantage of this pattern is that the `_refresh` functions accept parameters (e.g., `p_unit_ids`, `p_valid_after`). This allows the system to perform partial, targeted refreshes on small subsets of data, which is far more efficient than a full `REFRESH MATERIALIZED VIEW`.
-   **Responsibility**: **Data Aggregation, Denormalization, and Performance**. This layer is responsible for the heavy lifting of joining many tables and storing the results efficiently.

#### Key Column Flow Example (`primary_activity_category_path`):

1.  The `timeline_establishment_def` view joins `timesegments` with `activity` and `activity_category`.
2.  For a given time-slice (e.g., from `2023-01-01` to `2023-12-31`), it finds the single primary activity valid during that period.
3.  It selects the `path` from the corresponding `activity_category` row and exposes it as the `primary_activity_category_path` column in the view's output.
4.  When `timeline_establishment_refresh()` is called, it executes the query from the `_def` view and stores this pre-calculated value in the `timeline_establishment` table.

### 2.5. `public.statistical_unit` (Table - Final Materialization)

-   **Purpose**: The final, "everything" table that powers the UI and API. It contains a fully denormalized historical record for every unit in the system, for every atomic timesegment. This allows for extremely efficient queries at a glance for any point in time, and for detailed historical reports.
-   **Architecture**: This layer follows the same custom materialization pattern as the `timeline_*` tables:
    1.  `public.statistical_unit_def` (View): The query that `UNION`s all the `timeline_*` tables together.
    2.  `public.statistical_unit` (Table): The final destination table that stores the fully materialized results.
    3.  `public.statistical_unit_refresh()` (Function): The procedure that efficiently calculates and applies changes to the main table.
-   **Correct Logic**: The `statistical_unit_def` view's sole responsibility should be to `UNION ALL` the records from the underlying `timeline_*` tables. It must not contain complex joins or re-calculate data that has already been computed and materialized in the timeline layer.
-   **Responsibility**: **Presentation, Unification, and UI Performance**.

## 3. The Root Cause of the Current Bug

The current bug is a violation of this architecture within the `statistical_unit_def` view.

-   **The Guiding Principle**: The `statistical_unit` table must represent the **atomic truth**. Each row corresponds to an atomic timesegment where the state of the unit and its direct children is constant. Data from one segment must never be "smeared" or "filled forward" into another.
-   **The Flaw**: The previous implementation of `statistical_unit_def` violated this principle. It contained complex and buggy logic that attempted to re-join and transform the already-correct data from the `timeline_*` tables. This resulted in the incorrect merging of atomic segments and data loss.
-   **The Fix**: The `statistical_unit_def` view must be simplified to honor the architecture. It should act as a simple `UNION ALL` of the `timeline_*` tables, with no complex joins or transformations beyond what is necessary for unifying the data structure (e.g., handling external identifiers). It must trust its sources completely.
