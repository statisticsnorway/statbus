# Specification: Set-Based Temporal Processing Functions

## 1. Project Handover & Agent Instructions

This document contains the complete specification for developing a new set of high-performance, set-based temporal processing functions. This task is being handed over for implementation.

### 1.1. High-Level Goals

1.  **Fix Performance**: The primary goal is to eliminate the performance degradation observed during large data imports. This will be achieved by replacing the current slow, iterative (RBAR) temporal functions with highly efficient, set-based equivalents.
2.  **Ensure Correctness**: The new functions must correctly handle all possible temporal overlap scenarios as defined by Allen's Interval Algebra and maintain data integrity, especially with respect to the `sql_saga` temporal foreign key system. You can read more about that here https://github.com/veridit/sql_saga
3.  **Improve Maintainability**: The new architecture must be easier to understand, test, and maintain than the legacy implementation.

### 1.2. Your Task

Your task is to implement the PL/pgSQL logic for the functions defined in this specification. The work is divided into two main parts:

1.  **Implement the `plan_set_*` functions**: Write the core temporal logic that analyzes source and target data and generates a correct DML plan. This is the most complex part of the task.
2.  **Implement the `set_*` functions**: Write the orchestrator logic that calls the planner, materializes the plan, and executes it transactionally.

The stubs for these functions and a comprehensive test framework have already been created. Your implementation should make the tests pass.

### 1.3. Referenced Files

To avoid information overload, read the following files **after** you have understood this specification document.

**Primary Implementation & Test Files:**
*   `migrations/20250814100000_create_set_based_temporal_upsert_functions.up.sql`: Contains the function stubs you will be implementing.
*   `test/sql/113_test_set_insert_or_replace.sql`: The test suite for the `_replace` planner. Your implementation must make these tests pass.
*   `test/sql/114_test_set_insert_or_update.sql`: The test suite for the `_update` planner. Your implementation must make these tests pass.

**Key Concepts & Conventions (read these for context):**
*   `doc/valid-time.md`: Explains the project's temporal data model. Essential reading.
*   `migrations/20240607000000_add_eras_and_constraints.up.sql`: Shows how `sql_saga` is used to enforce temporal foreign keys.
*   `migrations/20250425000000_create_type_allen_interval_relation.up.sql`: Defines the Allen Interval relations your logic must handle.

**Legacy Implementations (for reference on what is being replaced):**
*   `migrations/20250427000000_import_create_batch_insert_or_update_generic_valid_time_table.up.sql`
*   `migrations/20250428000000_import_create_batch_insert_or_replace_generic_valid_time_table.up.sql`

### 1.4. Permission to Iterate

This specification provides a detailed plan and a robust API. However, it is a guide, not a rigid set of rules. You have the authority to propose changes or refinements to the plan if you discover a more effective way to achieve the high-level goals. Any proposed changes must respect the core principles outlined below.

### 1.5 High Level View

The import process itself has analyse/process phases, where analyse can be holistic, going through multiple steps, and some
look at all rows, and some process in batch, while the process phase is always batch oriented, and within each batch performs each step.
Each of these process steps will call the set based insert or x function for their specific target table. Some will make temporary
unpivot tables and some may use the data table directly. The set insert or x then calls plan and then performs according to the plan.

---

## 2. Overall Workflow: From Import Job to Set-Based Functions

This section describes the end-to-end data flow, clarifying how the high-level import job phases interact with the new low-level set-based functions.

1.  **Job Orchestration**: The `admin.import_job_process` procedure is the main orchestrator for an import job. It manages the job's overall state (e.g., `analysing_data`, `processing_data`).

2.  **Analysis Phase**:
    *   The orchestrator calls `admin.import_job_analysis_phase`.
    *   This phase processor iterates through the import definition's steps (e.g., `analyse_valid_time`, `analyse_external_idents`, `analyse_legal_unit`).
    *   Each `import.analyse_*` procedure is called in batches. Its sole responsibility is **row-level validation**. It inspects each row for data errors (e.g., bad dates, invalid codes, missing required fields).
    *   If an `analyse_*` procedure finds an unrecoverable error in a row, it marks that row in the job's `_data` table with `state = 'error'` and `action = 'skip'`. This prevents the row from being processed further.

3.  **Processing Phase**:
    *   Once analysis is complete, the orchestrator calls `admin.import_job_processing_phase`.
    *   This phase processor iterates through the import definition's processing steps (e.g., `process_legal_unit`, `process_establishment`).
    *   Each `import.process_*` procedure receives a batch of `row_id`s that have passed all analysis steps (i.e., `action` is not `'skip'`).
    *   **Example: Inside `import.process_legal_unit`**:
        1.  The procedure receives a batch of `row_id`s.
        2.  It calls one of the new set-based orchestrator functions, for example `import.set_insert_or_replace_generic_valid_time_table`.
        3.  It passes the target table (`public.legal_unit`), the source table (the job's `_data` table), and the array of `row_id`s for the current batch.

4.  **Set-Based Function Execution**:
    *   **Inside `import.set_insert_or_replace_...` (The Orchestrator)**:
        1.  It calls its corresponding planner: `import.plan_set_insert_or_replace_...`, passing through all the arguments it received.
        2.  **Inside `import.plan_set_...` (The Calculator)**:
            *   It reads only the specified `row_id`s from the source `_data` table.
            *   It reads all conflicting temporal slices from the `public.legal_unit` target table.
            *   It performs the complex Allen Interval Algebra calculations and generates a complete execution plan as a `SETOF import.temporal_plan_op`.
            *   It returns this plan to the `set_...` function.
        3.  The `set_...` function materializes the entire returned plan into a `TEMP TABLE`.
        4.  Within a single transaction with `DEFERRED` constraints, it executes the DML operations from the temp plan in the correct order (`DELETE`, `UPDATE`, `INSERT`).
        5.  It returns a summary of the results (e.g., which source rows succeeded).
    *   The `import.process_legal_unit` procedure receives this summary and performs any final updates on the `_data` table (e.g., storing the newly created `legal_unit.id`).

This layered approach ensures that row-level data quality is handled during analysis, while the complex, set-based temporal logic is handled safely and transactionally during processing.

---

## 3. The New Set-Based Architecture: Detailed Specification

### 3.1. Core Principles

-   **Plan & Process Separation**: The architecture is split into a `plan` function (a pure calculation engine) and a `process` function (a transactional orchestrator). This makes the complex temporal logic independently testable.
-   **Set-Based Operations**: All data is processed in sets to achieve high performance and scalability.
-   **Flexible Source API**: The functions can operate on an entire source table or a specific subset of `row_id`s from a larger table, avoiding unnecessary data copying.
-   **Transactional Integrity**: All database modifications occur within a single transaction with `DEFERRED` constraints, guaranteeing atomicity and satisfying `sql_saga` temporal foreign key constraints.

### 3.2. Temporal Table Structure

-   `id INT NOT NULL`: This is the **Entity ID**, the stable identifier for a conceptual unit (e.g., a legal unit).
-   `valid_after DATE NOT NULL`: The exclusive start of the validity period for a temporal slice.
-   `valid_to DATE NOT NULL`: The inclusive end of the validity period for a temporal slice.
-   **Primary Key**: The key that uniquely identifies a temporal slice is the composite key `(id, valid_after)`.
-   **Foreign Keys**: Temporal foreign keys (e.g., `establishment.legal_unit_id`) store the `Entity ID` of the parent record. `sql_saga` is used to enforce integrity across these relationships. For more information, see the [sql_saga project](https://github.com/veridit/sql_saga).

### 3.3. The Plan Stage (`plan_set_*` functions)

The planner is a pure, read-only calculation engine.

#### 3.3.1. Function Signature
```sql
FUNCTION import.plan_set_insert_or_replace_generic_valid_time_table(
    p_target_schema_name TEXT,
    p_target_table_name TEXT,
    p_target_entity_id_column_name TEXT,
    p_source_schema_name TEXT,
    p_source_table_name TEXT,
    p_source_entity_id_column_name TEXT,
    p_source_row_ids INTEGER[], -- Optional
    p_ephemeral_columns TEXT[]
) RETURNS SETOF import.temporal_plan_op
```
(A corresponding `plan_set_insert_or_update` function will have the same signature).

#### 3.3.2. Parameters
-   `p_target_schema_name`, `p_target_table_name`: Define the target temporal table.
-   `p_target_entity_id_column_name TEXT`: The name of the column in the target table that contains the `Entity ID` (e.g., `'id'`).
-   `p_source_schema_name`, `p_source_table_name`: Define the source table containing the new data.
-   `p_source_entity_id_column_name TEXT`: The name of the column in the source table that contains the `Entity ID` for the target entity (e.g., `'legal_unit_id'`).
-   `p_source_row_ids INTEGER[]`: **Optional**. If `NULL`, the function processes the *entire* `p_source_table_name`. If an array of IDs is provided, it processes *only* those rows from the source table where the `row_id` column matches an ID in the array.
-   `p_ephemeral_columns TEXT[]`: Columns to be updated from the source record even when core data is equivalent (e.g., `edit_comment`).

#### 3.3.3. The Plan Output (`import.temporal_plan_op`)
The function returns a set of `import.temporal_plan_op` records, each representing one DML operation.
-   `source_row_id INTEGER`: The `row_id` from the source table that triggered this operation.
-   `operation import.plan_operation_type`: `'INSERT'`, `'UPDATE'`, or `'DELETE'`.
-   `entity_id INT`: The `Entity ID` of the unit being modified.
-   `old_valid_after DATE`: **Selector**. For `UPDATE` and `DELETE`, this is the `valid_after` key of the existing slice to be targeted.
-   `new_valid_after DATE`: **Value**. The new `valid_after` for an `INSERT` or `UPDATE`.
-   `new_valid_to DATE`: **Value**. The new `valid_to` for an `INSERT` or `UPDATE`.
-   `data JSONB`: The non-temporal data for the operation.

### 3.4. The Process Stage (`set_*` functions)

The process function is the "unit of work" orchestrator. Its API mirrors the planner's for consistency, but it returns a summary of work done.

#### 3.4.1. Responsibilities
1.  **Call Planner**: It calls the corresponding `plan_set_*` function with the provided parameters.
2.  **Materialize Plan**: It stores the entire plan in a `TEMP TABLE`. This is crucial for executing modifications in efficient, set-based batches.
3.  **Execute Plan**: Within a single transaction with `DEFERRED` constraints, it executes the plan. Deferring constraints is essential for allowing temporary, harmless overlaps (for exclusion constraints) and for ensuring `sql_saga`'s temporal foreign keys are validated against the final state of the transaction. It executes the plan in a strict order: all `INSERT`s, then all `UPDATE`s, then all `DELETE`s. This "add-then-modify" order is critical for `sql_saga` compatibility (see section 5.5).
4.  **Report Results**: It returns a summary of the operations performed.

### 3.5. Error Handling Strategy

Error handling is cleanly separated between the import job's `analyse` and `process` phases.
-   **Row-Level Validation (`analyse` phase)**: All validation of individual source rows (e.g., invalid date formats) is handled by the `analyse_*` procedures, which run *before* the process phase. They mark invalid rows with `action = 'skip'`.
-   **Batch-Level Transactional Safety (`process` phase)**: The `plan_set_*` function assumes its input rows are valid. If it discovers a logical inconsistency across the *entire batch* that cannot be resolved (a bug or unhandled edge case), it will `RAISE EXCEPTION`. The calling `process_*` procedure will catch this, the transaction will be rolled back, and the entire batch will be marked as errored, ensuring atomicity.

### 3.6. Testing Implications

-   **Plan Validation**: The `plan-process` separation allows for isolated testing of the `plan_set_*` functions. Test cases can provide various temporal scenarios (e.g., all Allen interval relations) and assert that the generated plan is correct, without ever touching a target table.
-   **Process Validation**: The `set_*` orchestrator functions can be tested to ensure they correctly execute a given plan and handle transactions properly.
-   **Source Data**: Tests should create isolated `TEMP` tables to act as the source. The flexible API allows passing this temp table name and leaving `p_source_row_ids` as `NULL`. In production, the `process_*` procedures will call the functions with the main `_data` table name and a specific array of `p_source_row_ids`, avoiding intermediate data copies.

---
## 4. Appendix: Analysis of Legacy System

-   **Problem Summary**: The import system's performance degrades as target tables grow due to the use of iterative, row-by-row (RBAR) processing in the functions `batch_insert_or_replace_generic_valid_time_table` and `batch_insert_or_update_generic_valid_time_table`.
-   **Analysis of Legacy Functions**: The core issue is the `FOR ... LOOP` structure, which executes N+1 queries for each batch. This results in a time complexity of approximately O(S * T), a classic and highly inefficient database anti-pattern (see section 5.6 for a detailed comparison).
-   **Strategic Decision**: `insert_or_update` is functionally superior for data integrity as it preserves historical data not present in an import file. It should be the new default, and the performance difference will be negligible in the new set-based model.

---
## 5. Project Completion

The set-based temporal functions are now complete. This work represents a significant architectural improvement, replacing the slow, iterative legacy functions with a highly efficient and robust set-based model.

### 5.1. Summary of Work Completed

1.  **Architectural Redesign**: A clean separation between a `plan` stage (pure calculation) and a `process` stage (transactional execution) was implemented.
2.  **Advanced Planner Logic**: Two sophisticated planner functions, `plan_set_insert_or_replace` and `plan_set_insert_or_update`, were developed. They correctly handle all Allen Interval relations, generating optimal DML plans by deconstructing timelines into atomic segments, calculating a final state, and diffing it against the target table.
3.  **Robust Orchestration**: The corresponding `set_*` orchestrator functions were implemented to execute these plans transactionally, respecting the critical DML execution order (`INSERT` -> `UPDATE` -> `DELETE`) required for compatibility with `sql_saga`'s temporal foreign keys.
4.  **Performance Goals Met**: The new architecture achieves a time complexity of `O((S+T) log (S+T))`, a significant improvement over the legacy `O(S * T)` approach, ensuring the system can handle large-scale data imports efficiently.
5.  **Comprehensive Testing**: The functions have been validated against a thorough test suite covering a wide range of temporal scenarios, ensuring correctness and reliability.

The project successfully meets all its high-level goals: performance is fixed, correctness is ensured, and the new functions are significantly more maintainable.

---
## 6. Future Work: `sql_saga` Integration Proposal

This section outlines a proposal for integrating the set-based temporal merge logic developed in this project directly into the `sql_saga` extension, making it a general-purpose utility for any `sql_saga`-managed temporal table.

### 6.1. Rationale

The core temporal reconciliation logic (the `plan_set_*` functions) is not specific to the Statbus import system. It is a powerful and generic solution for a common problem in temporal databases: performing a bulk "upsert" of new time-sliced data against an existing temporal table. By integrating this into `sql_saga`, it becomes available to any user of the extension, providing a high-performance, out-of-the-box solution for temporal data warehousing and ETL tasks.

### 6.2. Proposed API

Based on feedback regarding type safety and inspectability, the proposed API is refined to use `regclass` for both source and target tables and explicit, type-safe parameters instead of a generic `jsonb` object.

First, a dedicated type would be created to define the merge mode:
```sql
CREATE TYPE sql_saga.merge_mode AS ENUM ('update', 'replace');
```

A single, powerful function within the `sql_saga` schema could then provide this functionality:

```sql
PROCEDURE sql_saga.merge_temporal(
    p_target_table regclass,
    p_source_table regclass,
    p_id_columns text[],
    p_mode sql_saga.merge_mode DEFAULT 'update',
    p_ephemeral_columns text[] DEFAULT '{}'
);
```

#### 6.2.1. Parameters

*   `p_target_table regclass`: The target temporal table to merge data into. The function will introspect this table to find its `valid_after`, `valid_to`, and data columns.
*   `p_source_table regclass`: The source table, view, or temporary table containing the new data. This `regclass` approach is type-safe and allows the function to inspect the source's structure before execution.
*   `p_id_columns text[]`: An array of column names that constitute the conceptual primary key for the entity (e.g., `ARRAY['id']`). These columns **must** exist in both the source and target tables.
*   `p_mode sql_saga.merge_mode`: The merge mode, either `'update'` (default) or `'replace'`.
*   `p_ephemeral_columns text[]`: An array of column names to exclude from data-equivalence checks (e.g., `["edit_comment", "last_updated_by"]`).

The function will automatically discover and use all columns that exist with the same name in both the source and target tables as the data payload, excluding the ID and temporal columns.

#### 6.2.2. Usage Example

```sql
-- Create a temporary table with new data
CREATE TEMP TABLE new_employee_data (
    employee_id int,
    department text,
    last_updated_by text,
    -- The source data must use sql_saga's (valid_after, valid_to] convention
    valid_after date,
    valid_to date
);
INSERT INTO new_employee_data VALUES (123, 'Sales', 'data_entry_user', '2024-12-31', '2025-06-30');

-- Call the merge function, passing the regclass of the temp table
CALL sql_saga.merge_temporal(
    p_target_table      => 'public.employees',
    p_source_table      => 'new_employee_data',
    p_id_columns        => ARRAY['employee_id'],
    p_mode              => 'update',
    p_ephemeral_columns => ARRAY['last_updated_by']
);
```

### 6.3. Implementation Notes

*   The implementation would adapt the logic from the `plan_set_*` and `set_*` functions.
*   **Introspection**: It will heavily use `information_schema` to compare the column lists of the source and target tables, automatically determining the data payload and validating that the required ID and temporal columns exist. This provides strong type safety and validation before execution.
*   **Performance**: By operating on tables/views, the function allows the PostgreSQL query planner to generate more efficient plans compared to executing a raw text query.
*   The use of a `TEMP TABLE` for the internal DML plan would remain a core part of the implementation.

This proposal would elevate `sql_saga` from a constraint management system to a more complete temporal data management framework.
