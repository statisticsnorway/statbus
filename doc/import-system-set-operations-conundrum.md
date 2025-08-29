# The Conundrum of Intra-Step Dependencies in Set-Based Processing

## 1. Introduction and Premise

The Statbus import system processes data in a series of steps, where each step targets a specific database table (e.g., `process_legal_unit` for the `legal_unit` table, `process_activity` for the `activity` table). The dependency between these steps is natural and expected: for example, an activity cannot be created without knowing the ID of the legal unit it belongs to. This **inter-step dependency** is handled by the import job orchestrator, which ensures steps run in the correct order.

The true architectural challenge, and the focus of this document, is the **intra-step dependency**. This conundrum arises when a single batch of rows, destined for a single target table, contains internal dependencies. For example, a batch for the `legal_unit` table might contain one row to `INSERT` a new unit and several other rows to `REPLACE` or `UPDATE` historical slices for that *same unit*. A set-based processing function like `temporal_merge` must receive this entire batch and resolve these dependencies internally to be efficient.

This document outlines this core problem and describes the final, implemented architecture that solves it.

## 2. The Core Problem: Intra-Step and Inter-Step Dependencies

To understand the challenge, consider a more realistic scenario involving multiple, related temporal tables and a source file that builds a history for a new entity.

### 2.1. Target Data Model

Our target database contains these simplified tables:
*   `legal_unit (id SERIAL PK, valid_after DATE, valid_to DATE, name TEXT, edit_comment TEXT)`: The main temporal entity table.
*   `external_ident (legal_unit_id INT FK, ident TEXT, code TEXT)`: A non-temporal table linking external identifiers to a legal unit.
*   `stat_for_unit (id SERIAL PK, valid_after DATE, valid_to DATE, legal_unit_id INT FK, stat_code TEXT, value TEXT, edit_comment TEXT)`: A related temporal table for statistical variables.

### 2.2. Source Data and Processing Flow

An import job is created with steps to process `legal_unit` data and then `statistical_variables`. The source file contains two rows that define a complete history for a single new legal unit, `987654321`.

**Source `import.csv`:**
| tax_ident | valid_from | valid_to   | name              | employees | turnover | edit_comment           |
|:----------|:-----------|:-----------|:------------------|:----------|:---------|:-----------------------|
| 987654321 | 2023-01-01 | 2023-05-31 | Unit A            |           |          | "Initial load"         |
| 987654321 | 2023-06-01 | 2023-12-31 | Unit A Inc.       | 12        | 100000   | "Name change"          |
| 987654321 | 2024-01-01 | 2024-12-31 | Unit A Inc.       | 15        | 120000   | "Employee update"      |
| 987654321 | 2025-01-01 | infinity   | Unit A Inc.       |           |          | "Employee corrected"   |
| 111111111 | 2023-01-01 | infinity   | Stable Corp       | 5         | 50000    | "Stable Corp created"  |
| 222222222 | 2023-01-01 | 2023-12-31 | Original Name LLC |           |          | "Original Name created"|
| 222222222 | 2024-01-01 | infinity   | New Name LLC      |           |          | "Name changed"         |
| 333333333 | 2023-01-01 | 2023-12-31 | Consistent Inc    | 20        |          | "Consistent Inc created"|
| 333333333 | 2024-01-01 | infinity   | Consistent Inc    | 25        | 250000   | "Employees updated"    |

**Analysis Phase**:
The system analyzes the source data and populates the job's `_data` table. Key determinations are:
*   The `analyse_external_idents` step finds that none of the `tax_ident` values exist. It groups the rows by identifier and determines the action for each row:
    *   **Unit 987654321**: `row_id`s `[1, 2, 3, 4]`. Row 1 is the `INSERT`, rows 2, 3, and 4 are `REPLACE`s. All share `founding_row_id=1`.
    *   **Unit 111111111**: `row_id` `[5]`. Row 5 is a simple `INSERT`. It is its own founding row: `founding_row_id=5`.
    *   **Unit 222222222**: `row_id`s `[6, 7]`. Row 6 is the `INSERT`, row 7 is a `REPLACE`. Both share `founding_row_id=6`.
    *   **Unit 333333333**: `row_id`s `[8, 9]`. Row 8 is the `INSERT`, row 9 is a `REPLACE`. Both share `founding_row_id=8`.
*   The `analyse_valid_time` step converts all `valid_from` dates to the system's exclusive `valid_after` dates (e.g., `2023-01-01` becomes `2022-12-31`).

## Processing Phase (Approach 1: In-Procedure Two-Stage Processing)
The orchestrator begins processing a batch containing all 9 rows (`row_id`s `[1-9]`).

*   **Step 1: `import.process_legal_unit`**
    *   **The Conundrum (Intra-Step Dependency)**: The procedure must process the `INSERT` rows (`1, 5, 6, 8`) to generate `legal_unit.id`s before it can process the `REPLACE` rows (`2, 3, 4, 7, 9`). It resolves this with its two-stage process.
    *   **Stage 1 (Inserts)**: It calls `temporal_merge` for the `INSERT` group.
        *   **Result**: Four new legal units are created (e.g., with `id`s `101, 102, 103, 104`).
    *   **ID Propagation**: The procedure updates the `_data` table, back-filling the new IDs. For example, `UPDATE ... SET legal_unit_id = 101 WHERE founding_row_id = 1;`, `... = 102 WHERE founding_row_id = 5;`, etc.
    *   **Stage 2 (Updates/Replaces)**: It calls `temporal_merge` for the `REPLACE` group (`[2, 3, 4, 7, 9]`), which now have the necessary IDs.
        *   **Result for Unit 987654321**: `temporal_merge` receives three rows for `id=101`. Since `name='Unit A Inc.'` is the same for all, it coalesces them, creating one new slice.
        *   **Result for Unit 222222222**: The name changes, so `temporal_merge` creates a new slice for `id=103`.
        *   **Result for Unit 333333333**: The name is the same, so `temporal_merge` coalesces the slice for `id=104`.
    *   **Outcome for `legal_unit` table**:
        *   Unit 101 ("Unit A", "Unit A Inc.") has two time slices.
        *   Unit 102 ("Stable Corp") has one time slice.
        *   Unit 103 ("Original Name LLC", "New Name LLC") has two time slices.
        *   Unit 104 ("Consistent Inc") has one time slice (coalesced).

*   **Step 2: `import.process_statistical_variables`**
    *   **The Conundrum (Inter-Step & Intra-Step Dependencies)**: This step depends on the `legal_unit.id`s from the previous step. It filters the batch for rows that contain `employees` data.
    *   **Stage 1 (Inserts)**: It calls `temporal_merge` for its `INSERT` group.
        *   Rows 1, 4, 6, 7 are skipped (no `employees` data).
        *   Row 2 (`founding_row_id=1`) is a local `INSERT` for the `employees` stat. `stat_for_unit.id=201` is created for `legal_unit_id=101`.
        *   Row 5 (`founding_row_id=5`) is a local `INSERT`. `stat_for_unit.id=202` is created for `legal_unit_id=102`.
        *   Row 8 (`founding_row_id=8`) is a local `INSERT`. `stat_for_unit.id=203` is created for `legal_unit_id=104`.
    *   **ID Propagation**: The procedure back-fills the new `stat_for_unit.id`s into the `_data` table (e.g., in a temporary `employees_stat_id` column).
    *   **Stage 2 (Updates/Replaces)**: It calls `temporal_merge` for its `REPLACE` group.
        *   Row 3 (`founding_row_id=1`) updates the stat for `id=201`.
        *   Row 9 (`founding_row_id=8`) updates the stat for `id=203`.
    *   **Outcome for `stat_for_unit` table**:
        *   Stat 201 (for LU 101) has two time slices (values 12 -> 15). Because the final source row for this unit had no `employees` data, the timeline for this specific statistic is correctly truncated and ends on 2024-12-31.
        *   Stat 202 (for LU 102) has one time slice (value 5).
        *   Stat 203 (for LU 104) has two time slices (values 20 -> 25).
        *   LU 103 has no stat records.

This multi-layered dependency within a single batch is the core challenge. An ideal solution must be efficient (set-based) while correctly resolving these dependencies.

## 3. Architectural Options

### Approach 1: In-Procedure Two-Stage Processing (Current Implementation)

This approach makes the `process_*` procedure responsible for resolving the dependencies within its batch.

*   **How it works**:
    1.  The procedure splits the batch internally into two groups: rows that create new entities (local `INSERT`s) and rows that modify existing ones (local `UPDATE`s/`REPLACE`s).
    2.  **Stage 1**: It calls `temporal_merge` for the `INSERT` group.
    3.  It captures the newly generated `id`s from the `temporal_merge` result.
    4.  **ID Propagation**: It performs an `UPDATE` on the job's main `_data` table, back-filling the new `id`s into all other rows in the batch that belong to the same entity (e.g., `WHERE founding_row_id = ...`).
    5.  **Stage 2**: It calls `temporal_merge` again for the `UPDATE`/`REPLACE` group, which now have all the necessary `id`s.

*   **Pros**:
    *   Keeps batch sizes large, which can be more performant by minimizing transaction overhead.
    *   The logic is self-contained within each `process_*` procedure.

*   **Cons**:
    *   The logic is highly complex and stateful, making the procedures difficult to maintain.
    *   It has been a significant source of subtle bugs (e.g., `MISSING_TARGET` errors, data corruption, duplicate key violations) during development.
    *   It duplicates the complex ID propagation logic across multiple `process_*` procedures.

### Approach 2: Declarative Batch Fences (Proposed Alternative)

This approach moves the dependency resolution out of the `process_*` procedures and makes it a declarative part of the data.

*   **How it works**:
    1.  A new, holistic analysis step (e.g., `analyse_dependencies`) runs once before processing begins.
    2.  It scans the entire dataset, identifies dependent groups (based on `founding_row_id`), and sorts them.
    3.  It adds a `batch_fence = TRUE` flag to every row that depends on a preceding row in the same batch.
    4.  The main batching loop in `admin.import_job_processing_phase` is modified to stop building a batch when it encounters a row with `batch_fence = TRUE`.
    5.  This automatically creates smaller, dependency-free batches. The `process_*` procedures become simple, stateless wrappers that make a single call to `temporal_merge`.

*   **Pros**:
    *   **Architecturally Clean**: Dramatically simplifies `process_*` procedures and removes duplicated logic.
    *   **Robust & Debuggable**: Dependencies are made explicit in the data, making the system's behavior easier to trace and verify.
    *   **Centralized Logic**: All dependency handling is in one place.

*   **Cons**:
    *   **Performance**: Results in more, smaller batches, which increases transaction overhead and could slow down imports.
    *   **Complexity Shift**: The complexity moves to the new analysis step and the batch selection logic. A mechanism to efficiently re-resolve IDs between these smaller batches would be needed.

### Approach 3: "Smart" `temporal_merge` (Implemented Architecture)

This approach reframes the problem by enriching the data with dependency metadata during analysis, allowing a "smarter" `temporal_merge` function to resolve dependencies declaratively. This is the **final, implemented architecture**.

*   **How it works**:
    1.  **Analysis Phase Enhancement**: A new holistic analysis step is introduced. It scans the dataset, identifies all rows belonging to the history of a single conceptual entity (e.g., based on external identifiers), and assigns them all a shared `identity_seq` number.
    2.  **Simplified `process_*` Procedures**: The complex, stateful logic is removed from the `process_*` procedures. They now become simple wrappers that prepare the relevant columns and make a **single call** to `temporal_merge`, passing the `identity_seq`.
    3.  **"Smart" `temporal_merge` Logic**: The function receives the batch and partitions it by `identity_seq`. For each entity group, it finds the first chronological row. If that row has a `NULL` surrogate ID, the function knows it's a new entity. It performs an `INSERT`, captures the new ID, and propagates it to all other rows in that entity's group before proceeding with the temporal merge logic. This resolves the intra-step dependency internally and declaratively.

*   **Pros**:
    *   **Architecturally Clean**: `process_*` procedures are dramatically simplified, stateless, and free of duplicated logic.
    *   **Robust & Declarative**: The `temporal_merge` function handles all complex logic, making the system more robust. The dependency is declared in the data (`identity_seq`) rather than handled procedurally.
    *   **Encapsulation**: All complex temporal and dependency logic is encapsulated in one well-tested engine.

*   **Cons**:
    *   **Inter-Step Dependency Remains**: This architecture solves the *intra-step* dependency (e.g., `INSERT`/`REPLACE` for `legal_unit`). It does not solve the *inter-step* dependency (e.g., `process_statistical_variables` needing the `legal_unit_id` from `process_legal_unit`). The ID back-fill into the `_data` table between steps is still required.

## 4. Conclusion and Recommendation

*   **Approach 1 (In-Procedure Logic)** was the initial implementation. While functional, its complexity was a consistent source of subtle bugs and high maintenance overhead. It has been superseded.
*   **Approach 2 (Batch Fences)** is a robust architectural alternative that prioritizes explicit dependency declaration over performance. It remains a valid future option if inter-step dependencies become a major issue.
*   **Approach 3 (Smart Temporal Merge)** is the **final, implemented architecture**. By using an abstract `identity_seq` key, it successfully encapsulates the complex intra-step dependency logic within the `temporal_merge` function, dramatically simplifying the calling `process_*` procedures and improving maintainability.

**Recommendation**:
The project has successfully implemented **Approach 3**. This resolves the primary challenge of intra-step dependencies. The "Batch Fence" model from **Approach 2** should be kept in consideration for future architectural reviews if performance or inter-step dependencies prove to be a recurring problem.

---
## "Smart Temporal Merge" Architecture in Detail

This section provides a detailed breakdown of the final, implemented processing model based on the "Smart Temporal Merge" architecture.

The core idea is to enrich the data with more explicit metadata during the analysis phase, which the `temporal_merge` function can then use to resolve intra-step dependencies internally.

### Analysis Phase Enhancements
This approach centers on a single, powerful metadata column: `identity_seq`.

*   `identity_seq INTEGER`: A group identifier for all rows that belong to the history of a single conceptual entity. This is generated during the analysis phase.
    *   **Initialization**: Initially, for every row in the `_data` table, `identity_seq` is set to its own `row_id`.
    *   **Grouping**: A new, holistic analysis step (e.g., `analyse_dependencies`) runs after `analyse_external_idents`. It identifies groups of rows based on their shared external identifier (e.g., all rows with `tax_ident = '987654321'`). For each group, it finds the first chronological row (ordered by `valid_after`) and updates the `identity_seq` of *all* rows in that group to match the `row_id` of that first row. The `action` column is not needed for this process.
    *   **Result**: After this step, the `_data` table for our example would look like this:
        | row_id | tax_ident | name              | identity_seq |
        |:-------|:----------|:------------------|:-------------|
        | 1      | 987654321 | Unit A            | 1            |
        | 2      | 987654321 | Unit A Inc.       | 1            |
        | 3      | 987654321 | Unit A Inc.       | 1            |
        | 4      | 987654321 | Unit A Inc.       | 1            |
        | 5      | 111111111 | Stable Corp       | 5            |
        | 6      | 222222222 | Original Name LLC | 6            |
        | 7      | 222222222 | New Name LLC      | 6            |
        | 8      | 333333333 | Consistent Inc    | 8            |
        | 9      | 333333333 | Consistent Inc    | 8            |

### "Smart" `temporal_merge` API
The function signature becomes simpler and more abstract, requiring only the name of the column that holds the dependency key.
```sql
FUNCTION import.temporal_merge(
    ...,
    p_identity_seq_column TEXT -- e.g., 'identity_seq'
)
```

### Processing Flow with a "Smart" `temporal_merge`

*   **Step 1: `import.process_legal_unit`**
    *   The procedure receives a batch (e.g., `[1-9]`). It prepares a temporary source table containing the relevant data columns and the `identity_seq`. The `action` column is no longer passed to the merge function.
    *   It makes a **single call** to the enhanced `temporal_merge` function.
    *   **Internal Logic of `temporal_merge`**:
        The process maintains a clean separation of concerns between the pure, read-only **Planner** (`temporal_merge_plan`) and the transactional **Orchestrator** (`temporal_merge`).

        **Planner (`temporal_merge_plan`) Logic**:
        1.  The planner receives the source rows, including the `identity_seq`.
        2.  It identifies new conceptual entities by finding `identity_seq` groups where the first chronological row has a `NULL` surrogate key.
        3.  It then proceeds with the full temporal planning logic for the entire batch.
        4.  The plan it generates will contain operations for both existing entities (using their real, known IDs) and new entities. For new entities, the `entity_id` field in the plan will be `NULL`.
        5.  The planner returns this complete plan to the orchestrator. It does not need to generate placeholder IDs.

        **Orchestrator (`temporal_merge`) Logic**:
        The orchestrator resolves IDs for new entities using a standard and robust pattern that works around a limitation in PostgreSQL's `INSERT` statement. While the `RETURNING` clause of `UPDATE` and `DELETE` statements can refer to columns from other tables in their `USING` or `FROM` clauses, an `INSERT ... SELECT` statement's `RETURNING` clause can **only** refer to columns from the table being inserted into. It cannot see columns from the `SELECT`'s source table.

        The orchestrator resolves IDs for new entities using PostgreSQL's powerful `MERGE` statement. The `RETURNING` clause of a `MERGE` statement can refer to columns from both the source and target tables, which provides a direct and efficient solution to the ID mapping problem, making more complex workarounds unnecessary.

        1.  The orchestrator receives the complete plan from the planner.
        2.  **Stage 1 (Inserts & ID Mapping)**: It identifies all `INSERT` operations in the plan. To generate new IDs and map them back to their conceptual entity (`identity_seq`), it executes a single `MERGE` statement using a pattern that is proven to be safe for `GENERATED ALWAYS` identity columns:
            ```sql
            -- Simplified example
            MERGE INTO target_table t
            USING source_for_insert s ON t.id = s.target_id -- s.target_id is always NULL for new entities
            WHEN NOT MATCHED THEN
                INSERT (name, ...) VALUES (s.name, ...)
            RETURNING t.id AS new_id, s.identity_seq;
            ```
            The `RETURNING t.id, s.identity_seq` clause is the key. The join condition `ON t.id = s.target_id` (where `s.target_id` is guaranteed to be `NULL` for the `source_for_insert` set) correctly forces all rows into the `WHEN NOT MATCHED` path without triggering the planner bug seen with the `ON 1=0` pattern. This returns a perfect mapping of the newly generated `id` to the `identity_seq` from the source row that created it. The orchestrator collects these pairs into a temporary map table.
        3.  **Stage 2 (Updates)**: It executes all `UPDATE` operations from the plan. If an `UPDATE` operation targets a new entity, the orchestrator uses the `identity_seq` (from the plan's `source_row_ids`) to look up the new `id` from the map and uses it in the `WHERE` clause of the `UPDATE` statement.

        4.  **Stage 3 (Deletes)**: The same logic is applied to `DELETE` operations.

        5.  This multi-stage execution, driven by the planner's pure output and the direct ID mapping from `RETURNING`, correctly and efficiently resolves the intra-step dependency within a single transaction. The complex placeholder ID mechanism is not needed. The specific `action` type (`'insert'`, `'replace'`) is also not needed by `temporal_merge`; its role is reduced to high-level filtering (e.g., `WHERE action = 'use'`) by the calling `process_*` procedure.
    *   **Outcome**: The final state of the `legal_unit` table is identical to Approach 1, but achieved with a single, declarative function call.

*   **Step 2: `import.process_statistical_variables`**
    *   This step still has the **Inter-Step Dependency** on the `legal_unit_id`s, which must be populated in the `_data` table before it can run.
    *   The procedure prepares its source data by unpivoting columns like `employees` from the `_data` table.
    *   **Crucially**, it does *not* need to generate a new `identity_seq`. It simply inherits the `identity_seq` from its parent `_data` row. The same `identity_seq` (e.g., `1`) can be used to group both the legal unit's history and its employee stat's history.
    *   It then makes its own **single call** to the smart `temporal_merge`. The internal logic is identical, correctly handling the `stat_for_unit` records as their own independent dependency chain, identified by their inherited `identity_seq`.

This approach successfully solves the **Intra-Step Dependency** conundrum by delegating the resolution to the `temporal_merge` function, which dramatically simplifies the `process_*` procedures. The **Inter-Step Dependency** (e.g., `process_statistical_variables` needing the `legal_unit_id`) remains, and is correctly handled by the import job orchestrator which ensures `process_legal_unit` completes and back-fills the necessary IDs before `process_statistical_variables` is called.

### 5. Executable Proof of Viability

This section provides a complete, step-by-step walkthrough of the data flow, using the concrete example from the proof-of-viability script. This serves as an executable specification for the "Smart Merge" architecture. The script has been refactored to encapsulate the logic for each processing step into its own mock PL/pgSQL function. This more accurately reflects the final architecture, where a `process_*` procedure is a self-contained unit of work.

#### 5.1. Initial State

The process begins with the `job_data` table populated with 9 rows representing the history of 4 distinct conceptual entities. `identity_seq` has been populated by the analysis phase.

#### 5.2. Step 1: `process_legal_unit`

The main script calls the mock procedure `process_legal_unit_mock()`. This function encapsulates all the logic for processing `legal_unit` data for the batch. It operates on `job_data_view`, an updatable view on the base `job_data` table, accurately simulating a real `process_*` procedure. It:
1.  **Determines Final State**: Calculates the final state for each conceptual entity.
2.  **Executes Inserts & Creates Fence**: Uses the proven `MERGE` pattern to create the four new `legal_unit` entities. Crucially, it stores the results (the map of `new_id` to `identity_seq`) in a temporary table (`id_map_lu`). This is the mandatory "materialization fence."
3.  **Back-fills IDs**: Executes a simple `UPDATE` on the `job_data_view` using the `id_map_lu` table to back-fill the generated IDs.
4.  **Executes Updates**: Performs a `MERGE` to update the names for the entities that changed.

**Final `legal_unit` table state:**
| id | name | edit_comment |
| :--- | :--- | :--- |
| 1 | Unit A Inc. | Employee corrected |
| 2 | Stable Corp | Stable Corp created |
| 3 | New Name LLC | Name changed |
| 4 | Consistent Inc | Employees updated |

#### 5.3. Step 2: `process_statistical_variables`

The main script then calls `process_stat_vars_mock()`. This function now has access to the `legal_unit_id`s in the `job_data` table. It encapsulates all the logic for its step:
1.  **Unpivots Source Data**: Creates a temporary, unpivoted source table from the `employees` and `turnover` columns.
2.  **Executes Inserts & Creates Fence**: Creates the new `stat_for_unit` entities using the same "materialization fence" pattern.
3.  **Back-fills IDs**: Updates the `job_data_view`, pivoting the new stat IDs into the `employees_stat_for_unit_id` and `turnover_stat_for_unit_id` columns.
4.  **Executes Updates**: Updates the values for the stats that changed.

**`job_data` table after all steps:**
| row_id | identity_seq | name | ... | legal_unit_id | employees_stat_for_unit_id | turnover_stat_for_unit_id |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | 1 | Unit A | ... | 1 | 1 | 2 |
| 2 | 1 | Unit A Inc. | ... | 1 | 1 | 2 |
| 3 | 1 | Unit A Inc. | ... | 1 | 1 | 2 |
| 4 | 1 | Unit A Inc. | ... | 1 | 1 | 2 |
| 5 | 5 | Stable Corp | ... | 2 | 3 | 4 |
| 6 | 6 | Original Name LLC | ... | 3 | | |
| 7 | 6 | New Name LLC | ... | 3 | | |
| 8 | 8 | Consistent Inc | ... | 4 | 5 | 6 |
| 9 | 8 | Consistent Inc | ... | 4 | 5 | 6 |

**Final `stat_for_unit` table state:**
| id | legal_unit_id | stat_code | value | edit_comment |
| :--- | :--- | :--- | :--- | :--- |
| 1 | 1 | employees | 15 | Employee update |
| 2 | 1 | turnover | 120000 | Employee update |
| 3 | 2 | employees | 5 | Stable Corp created |
| 4 | 2 | turnover | 50000 | Stable Corp created |
| 5 | 4 | employees | 25 | Employees updated |
| 6 | 4 | turnover | 250000 | Employees updated |

---
## Appendix: Analysis of Temporary Objects in the Proof-of-Viability Script

The proof-of-viability script (`tmp/temporal_merge_resolve_conundrum.sql`) makes use of several temporary objects (`VIEW`s and `TABLE`s) to execute its logic. This section analyzes each temporary table, explaining its purpose and why it was chosen over an alternative like a view.

### `legal_unit_plan`
*   **Purpose**: Materializes the calculated DML plan for `legal_unit` operations (`insert` vs. `update`).
*   **Why a Table?**: The plan, which is derived from complex window functions, is queried twice: once to find rows for `INSERT`, and again to find rows for `UPDATE`. Materializing the plan into a `TEMP TABLE` is a performance optimization that avoids re-calculating it.
*   **Alternative?**: A `VIEW` or CTE could be used, but this would force the database to re-run the expensive planning logic for each subsequent query that uses it. A `TEMP TABLE` is more efficient for this use case.

### `source_for_lu_insert`
*   **Purpose**: Isolates the source data for new legal units that need to be created.
*   **Why a Table?**: It provides a clean, distinct set of rows to the subsequent `INSERT ... RETURNING` logic. This separation of concerns improves the clarity and step-by-step readability of the procedure.
*   **Alternative?**: Yes, this could be a CTE within the next step. Materializing it is not strictly required but is a good practice for logical clarity.

### `id_map_lu`
*   **Purpose**: Stores the mapping between an entity's `identity_seq` and its newly generated database `id`.
*   **Why a Table?**: Materializing the ID map into a `TEMP TABLE` creates a "materialization fence." This is a critical architectural pattern that is **mandatory** to work around a confirmed PostgreSQL query planner bug.
    *   **The Bug**: When a `MERGE` statement is used in a data-modifying CTE to `UPDATE` an *updatable view*, the planner incorrectly handles the `GENERATED ALWAYS` identity column and fails. The exact same operation succeeds if the `UPDATE` targets a base table. This was definitively proven by the smaller proof-of-concept scripts.
    *   **Minimal Reproduction of the Bug**: The following self-contained example demonstrates the bug. The `UPDATE` on `source_view` fails, while the identical `UPDATE` on `source_table` succeeds.
        ```sql
        -- Setup
        CREATE TEMP TABLE source_table (id INT PRIMARY KEY, name TEXT, target_id INT);
        CREATE TEMP VIEW source_view AS SELECT * FROM source_table;
        CREATE TEMP TABLE target_table (id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, name TEXT);
        INSERT INTO source_table VALUES (1, 'Update via View', NULL), (2, 'Update via Table', NULL);

        -- FAILS: The UPDATE targets a VIEW.
        WITH id_map AS (
            MERGE INTO target_table t
            USING (SELECT * FROM source_view WHERE id = 1) s ON t.id = s.target_id
            WHEN NOT MATCHED THEN INSERT (name) VALUES (s.name)
            RETURNING t.id as new_id, s.id as source_id
        )
        UPDATE source_view sv SET target_id = im.new_id
        FROM id_map im WHERE sv.id = im.source_id;
        -- ERROR: cannot insert a non-DEFAULT value into column "id"

        -- SUCCEEDS: The exact same logic, but the UPDATE targets a TABLE.
        WITH id_map AS (
            MERGE INTO target_table t
            USING (SELECT * FROM source_table WHERE id = 2) s ON t.id = s.target_id
            WHEN NOT MATCHED THEN INSERT (name) VALUES (s.name)
            RETURNING t.id as new_id, s.id as source_id
        )
        UPDATE source_table st SET target_id = im.new_id
        FROM id_map im WHERE st.id = im.source_id;
        -- UPDATE 1
        ```
    *   **The Workaround**: By executing the `MERGE` first and storing its results in a `TEMP TABLE`, the subsequent `UPDATE` on the view becomes a simple, non-nested operation that the planner can handle correctly. The main proof-of-viability script (`temporal_merge_resolve_conundrum.sql`) now correctly demonstrates this pattern.
*   **Alternative?**: A single `UPDATE` statement with a data-modifying CTE can be used, but **only if the target of the `UPDATE` is a base table, not a view.** Since the `process_*` procedures in this project are designed to operate on updatable views (for abstraction and security), the temporary table is a required part of the architecture.

### `source_for_stats`
*   **Purpose**: Stores the unpivoted statistical data (`employees`, `turnover`).
*   **Why a Table?**: This is a major data transformation. The resulting unpivoted data set is queried multiple times throughout the rest of the procedure. Materializing it once into a `TEMP TABLE` is significantly more performant than re-running the complex unpivot query multiple times via a `VIEW` or CTE.
*   **Alternative?**: A `VIEW` or CTE is functionally possible but would be highly inefficient due to the repeated execution of the unpivot logic.

### `source_for_stat_insert` and `id_map_stat`
*   **Purpose & Rationale**: These tables serve the exact same purpose for the `stat_for_unit` step as their `_lu_` counterparts did for the `legal_unit` step. `source_for_stat_insert` isolates data for clarity, and `id_map_stat` is a required materialization fence.
