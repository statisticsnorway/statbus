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
Each of these process steps will call the new `temporal_merge` orchestrator function for their specific target table. The orchestrator then calls the `temporal_merge_plan` planner and executes the resulting plan.

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

4.  **Temporal Merge Execution**:
    *   For a detailed architectural overview of this stage, see [Architecture and Data Flow: `temporal_merge`](doc/temporal_merge_architecture_and_flow.md).
    *   **Inside `import.temporal_merge` (The Orchestrator)**:
        1.  It calls the `import.temporal_merge_plan` planner, passing through all the arguments it received.
        2.  **Inside `import.temporal_merge_plan` (The Planner)**:
            *   It reads the specified `row_id`s from the source `_data` table.
            *   It reads all conflicting temporal slices from the target table.
            *   It performs the complex temporal calculations and generates a complete execution plan.
            *   It returns this plan to the Orchestrator.
        3.  The Orchestrator materializes the entire returned plan into a `TEMP TABLE`.
        4.  Within a single transaction with `DEFERRED` constraints, it executes the DML operations from the temp plan in the correct order.
        5.  It returns a detailed, row-level summary of the results.
    *   The `import.process_legal_unit` procedure receives this summary and performs any final updates on the `_data` table (e.g., storing the newly created `legal_unit.id`).

This layered approach ensures that row-level data quality is handled during analysis, while the complex, set-based temporal logic is handled safely and transactionally during processing.

---

## 3. The New Set-Based Architecture: Detailed Specification

### 3.1. Core Principles

-   **Planner & Orchestrator Separation**: The architecture is split into a `Planner` function (a pure calculation engine) and an `Orchestrator` function (a transactional execution engine). This makes the complex temporal logic independently testable.
-   **Set-Based Operations**: All data is processed in sets to achieve high performance and scalability.
-   **Flexible Source API**: The functions can operate on an entire source table or a specific subset of `row_id`s from a larger table, avoiding unnecessary data copying.
-   **Transactional Integrity**: All database modifications occur within a single transaction with `DEFERRED` constraints, guaranteeing atomicity and satisfying `sql_saga` temporal foreign key constraints.

### 3.2. Temporal Table Structure

-   **Entity ID Column(s)**: One or more columns that form the stable identifier for a conceptual unit across its history (e.g., a single `id` column for `legal_unit`, or a composite key like `(stat_definition_id, establishment_id)` for `stat_for_unit`).
-   `valid_after DATE NOT NULL`: The exclusive start of the validity period for a temporal slice.
-   `valid_to DATE NOT NULL`: The inclusive end of the validity period for a temporal slice.
-   **Primary Key**: The key that uniquely identifies a temporal slice is the composite of the entity ID column(s) and `valid_after` (e.g., `(id, valid_after)`).
-   **Foreign Keys**: Temporal foreign keys (e.g., `establishment.legal_unit_id`) store the Entity ID of the parent record. `sql_saga` is used to enforce integrity across these relationships. For more information, see the [sql_saga project](https://github.com/veridit/sql_saga).

### 3.3. The Planner Stage (`temporal_merge_plan` function)

The Planner is a pure, read-only calculation engine.

#### 3.3.1. Function Signature
```sql
FUNCTION import.temporal_merge_plan(
    p_target_schema_name TEXT,
    p_target_table_name TEXT,
    p_source_schema_name TEXT,
    p_source_table_name TEXT,
    p_entity_id_column_names TEXT[],
    p_mode import.set_operation_mode,
    p_source_row_ids INTEGER[], -- Optional
    p_ephemeral_columns TEXT[],
    p_insert_defaulted_columns TEXT[] DEFAULT '{}'
) RETURNS SETOF import.temporal_plan_op
```
The `temporal_merge` Orchestrator function will have a corresponding signature.

#### 3.3.2. Parameters
-   `p_target_schema_name`, `p_target_table_name`: Define the target temporal table.
-   `p_source_schema_name`, `p_source_table_name`: Define the source table containing the new data.
-   `p_entity_id_column_names TEXT[]`: An array of column names that form the unique, stable identifier for a conceptual entity (e.g., `ARRAY['id']` or `ARRAY['stat_definition_id', 'establishment_id']`). These columns must exist in both the source and target tables with the same names.
-   `p_source_row_ids INTEGER[]`: **Optional**. If `NULL`, the function processes the *entire* `p_source_table_name`. If an array of IDs is provided, it processes *only* those rows from the source table where the `row_id` column matches an ID in the array.
-   `p_ephemeral_columns TEXT[]`: Columns to be updated from the source record even when core data is equivalent (e.g., `edit_comment`).
-   `p_insert_defaulted_columns TEXT[]`: **Optional**. An array of column names that have database `DEFAULT` values and should not be included in `INSERT` operations. This allows the database to populate them automatically for new records (e.g., a surrogate key like `'id'` or a timestamp like `'created_at'`).

#### 3.3.3. The Plan Output (`import.temporal_plan_op`)
The function returns a set of `import.temporal_plan_op` records, each representing one DML operation.
-   `source_row_ids INTEGER[]`: An array of `row_id`s from the source table that were merged into this single operation. This ensures that every source row can be mapped to a result.
-   `operation import.plan_operation_type`: `'INSERT'`, `'UPDATE'`, or `'DELETE'`.
-   `entity_id INT`: The `Entity ID` of the unit being modified.
-   `old_valid_after DATE`: **Selector**. For `UPDATE` and `DELETE`, this is the `valid_after` key of the existing slice to be targeted.
-   `new_valid_after DATE`: **Value**. The new `valid_after` for an `INSERT` or `UPDATE`.
-   `new_valid_to DATE`: **Value**. The new `valid_to` for an `INSERT` or `UPDATE`.
-   `data JSONB`: The non-temporal data for the operation.

#### 3.3.4. Planner Implementation Notes: Key CTEs
The planner's logic is complex, relying on a series of Common Table Expressions (CTEs) to deconstruct and reconstruct the timeline. Adhering to a clear naming convention for the columns in these CTEs is critical for correctness.

1.  **`source_rows`, `target_rows`**: These initial CTEs prepare the data. They should produce columns: `entity_id`, `valid_after`, `valid_to`, `data_payload`, and for `source_rows`, `source_row_id`.

2.  **`diff`**: This is the core CTE where the final calculated timeline is compared against the original target timeline. To avoid ambiguity, columns from the final timeline should be prefixed with `f_` and columns from the target timeline with `t_`.
    *   **Final Timeline (`f`)**: `f_entity_id`, `f_after`, `f_to`, `f_data`, `f_representative_source_row_id`, `f_source_row_ids`.
    *   **Target Timeline (`t`)**: `t_entity_id`, `t_after`, `t_to`, `t_data`.

3.  **`plan`**: This CTE consumes the `diff` and determines the final DML operation (`INSERT`, `UPDATE`, `DELETE`, or internal `NOOP`). When referencing columns from the `diff` CTE, it is essential to use the correct `f_` and `t_` prefixed names (e.g., `f_to`, not `f_valid_to`).

### 3.4. The Orchestrator Stage (`temporal_merge` function)

The Orchestrator is the "unit of work" execution engine. Its API mirrors the Planner's for consistency, but it returns a detailed row-level summary of work done.

#### 3.4.1. Responsibilities
1.  **Call Planner**: It calls the `temporal_merge_plan` function with the provided parameters.
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
## 5. Project Status: Core Implementation Complete

The core set-based temporal functions are now complete. This work represents a significant architectural improvement, replacing the slow, iterative legacy functions with a highly efficient and robust set-based model. The next phase is to integrate these functions into the import job processing steps.

### 5.1. Summary of Work Completed

1.  **Architectural Redesign**: A clean separation between a `plan` stage (pure calculation) and a `process` stage (transactional execution) was implemented.
2.  **Advanced Planner Logic**: Two sophisticated planner functions, `plan_set_insert_or_replace` and `plan_set_insert_or_update`, were developed. They correctly handle all Allen Interval relations, generating optimal DML plans by deconstructing timelines into atomic segments, calculating a final state, and diffing it against the target table.
3.  **Robust Orchestration**: The corresponding `set_*` orchestrator functions were implemented to execute these plans transactionally, respecting the critical DML execution order (`INSERT` -> `UPDATE` -> `DELETE`) required for compatibility with `sql_saga`'s temporal foreign keys.
4.  **Performance Goals Met**: The new architecture achieves a time complexity of `O((S+T) log (S+T))`, a significant improvement over the legacy `O(S * T)` approach, ensuring the system can handle large-scale data imports efficiently.
5.  **Comprehensive Testing**: The functions have been validated against a thorough test suite covering a wide range of temporal scenarios, ensuring correctness and reliability.
6.  **Maintainability Improvement**: The `_replace` and `_update` functions were separated into distinct migration files. This logical separation enhances code clarity and prevents cross-function bugs during maintenance, which proved to be a critical factor for ensuring correctness.
7.  **Semantic Analysis**: A thorough analysis comparing the legacy `batch_*` functions with the new `set_*` functions was completed. The findings revealed a critical difference in the `_replace` strategy (Temporal Patch vs. Full Timeline Replace) and confirmed the semantic equivalence of the `_update` strategy. This is documented in `doc/batch_vs_set_semantics.md`.

The project successfully meets all its high-level goals: performance is fixed, correctness is ensured, and the new functions are significantly more maintainable.

---

The `## 6. is moved to doc/sql_saga_temporal_merge.md`

---
## 7. Integration Plan for Import Jobs

This section outlines the concrete steps for integrating the new, unified `temporal_merge` function into the existing import job processing steps. The goal is to replace all calls to the legacy `batch_insert_or_*` functions.

### 7.1. Target `process_*` Procedures

The primary candidates for this refactoring are the procedures responsible for writing data to the main temporal tables. Based on the system design, these are:
*   `import.process_legal_unit`
*   `import.process_establishment`
*   `import.process_activity`
*   `import.process_location`
*   `import.process_contact`
*   `import.process_stat_for_unit`

Note: `region` and `sector` are classification tables, not temporal entity tables managed directly by `process_*` steps. The import system links to existing classifications, which is handled during the `analyse_*` phase of other steps (e.g., `analyse_location` resolves region codes). Therefore, `process_region` and `process_sector` procedures do not exist and are not needed.

### 7.2. Refactoring Steps for each Procedure

For each procedure listed above, the refactoring will involve the following steps:

1.  **Identify Legacy Call**: Locate the call to `batch_insert_or_update_generic_valid_time_table` or `batch_insert_or_replace_generic_valid_time_table`.
2.  **Determine Mode**: Confirm whether the "update" or "replace" mode is appropriate for the business logic of that step. Based on the project conventions, "update" is generally preferred to preserve existing historical data unless a full replacement is explicitly required by the import definition.
3.  **Construct New Call**: Replace the legacy function call with a call to the new `import.temporal_merge` function.
4.  **Map Parameters**: Ensure all parameters are correctly mapped to the new function signature. This includes:
    *   Target schema and table names.
    *   Source schema and table names (which will be the job's `_data` table).
    *   The correct `p_mode` (`'upsert_patch'` or `'upsert_replace'`) based on the job's strategy.
    *   Entity ID column names.
    *   The batch of `p_source_row_ids`.
    *   The list of `p_ephemeral_columns`.
5.  **Handle Return Value**: The new functions return a `SETOF` records indicating the `status` for each source row (`'SUCCESS'` or `'ERROR'`). The procedure must be updated to handle this new return format. A robust approach is to collect the results into a temporary table and then check if any rows have a status of `'ERROR'`. If errors are found, the procedure should raise an exception with the details, causing the batch to fail atomically.

### 7.3. Status

*   **Status**: **COMPLETED**.

### 7.4. Integration Pattern: Handling Mutually Exclusive Foreign Keys

*   **Problem**: Some target tables, like `stat_for_unit`, have `CHECK` constraints that enforce mutual exclusivity between a set of foreign key columns (e.g., exactly one of `legal_unit_id`, `establishment_id`, etc., must be set). The generic `set_*` functions are unaware of this constraint. If the source `_data` table contains more than one of these columns with non-`NULL` values for a given row, the planner will include all of them in the `INSERT` operation, causing a constraint violation.
*   **Context**: This occurs in import definitions that link two unit types, such as importing establishments that belong to existing legal units (`establishment_formal`). In this case, a row in the `_data` table can have both `legal_unit_id` and `establishment_id` populated.
*   **Solution**: The calling `process_*` procedure, which has the necessary business context, must be responsible for resolving this ambiguity. It must:
    1.  Inspect the import job's `definition_snapshot` to determine the primary unit type for the operation (e.g., from `definition.mode`).
    2.  Construct a list of the *other*, irrelevant unit ID foreign key columns.
    3.  Pass this list to the `set_*` function using the `p_insert_defaulted_columns` parameter. This will exclude them from `INSERT` operations, allowing them to default to `NULL` and satisfying the constraint.
*   **Example (`process_statistical_variables`)**: When processing for an `establishment` import, the procedure will call the `set_*` function with `p_insert_defaulted_columns => ARRAY['id', 'created_at', 'legal_unit_id', 'enterprise_id', 'group_id']`. This ensures only `establishment_id` is passed to the `INSERT` statement for `stat_for_unit`.

---
## 10. Phase 4: Regression Fixes

### 10.1. Bug Analysis: Incomplete Result Handling in `process_*` Procedures

*   **Observation**: The integration test `107` fails with errors like `"Set-based function returned success but no entity ID."`. This occurs during the processing of `REPLACE` actions for an entity's history.
*   **Problem**: The `process_legal_unit` and `process_establishment` procedures correctly use a two-stage process ("inserts first, then replaces"). However, after calling the `set_*` functions for the `REPLACE` stage, they fail to process the results. When the planner merges multiple source rows, the orchestrator provides "complete feedback" (a `SUCCESS` result for every source row), but the procedure does not use this feedback to update the `_data` table.
*   **Impact**: For rows that were merged by the planner, their `legal_unit_id` or `establishment_id` columns in the `_data` table are left `NULL`. This causes downstream steps (like `process_location` or `process_statistical_variables`) to fail because they cannot find the required parent entity ID.
*   **Resolution**: The fix is to add the necessary logic to both `process_legal_unit` and `process_establishment`. After the `set_*` function is called for the `REPLACE`/`UPDATE` stage, the procedure must iterate through the results, collect all `source_row_id`s that were processed successfully, and perform a final `UPDATE` on the `_data` table to back-fill the entity IDs.
*   **Summary**: This change completes the logic in the `process_*` procedures, ensuring they correctly handle all results from the set-based functions. This is the final step in the integration of the new temporal logic.

---
## 8. Phase 2: Semantic Alignment and API Refinements

Based on a detailed review of the semantic differences between the legacy `batch_*` functions and the new `set_*` functions, the following refinements are required to ensure the new functions align with user expectations and legacy behavior.

---
### 8.0. Phase 2 - Step 1: Adjust Tests to Match New Requirements

As the first step in aligning the function semantics, the test suites have been updated to reflect the desired behavior. The goal is to make these new tests fail first, confirming the current implementation does not match, and then proceed with implementing the logic to make them pass.

*   **`_replace` Tests Adjusted**: The test cases for `plan_set_insert_or_replace` (113) and `set_insert_or_replace` (115) have been modified. The expected plans and final database states now assert the "Temporal Patch" behavior, where non-overlapping historical records are preserved rather than deleted.
*   **`_update` API and Tests Adjusted**: The test cases (114 and 116) were reviewed. The existing logic using `jsonb_strip_nulls` already correctly implements the desired "ignore nulls" behavior, making the proposed API change unnecessary.

### 8.1. Adjust `_replace` Semantics to "Temporal Patch" - **COMPLETED**

*   **Observation**: The current `set_insert_or_replace` function implements a "Full Timeline Replace" for each entity. This means it deletes all historical records for an entity and replaces them with only the records provided in the source data.
*   **Requirement**: The legacy `batch_insert_or_replace` function and user expectations are based on a "Temporal Patch" model. In this model, only the segments of an entity's timeline that directly overlap with the source data are replaced. Historical data outside the time window of the source data must be preserved.
*   **Action**: The logic within `import.plan_set_insert_or_replace_generic_valid_time_table` has been modified. The `resolved_atomic_segments` CTE now calculates the final timeline by considering segments from both the source and target tables. The data payload selection logic (`COALESCE(s.data_payload, t.data_payload)`) ensures that source data replaces target data in overlapping segments, while non-overlapping target segments are preserved. This aligns the function with the expected "Temporal Patch" behavior.

### 8.2. Phase 2 - Step 2: Final Test Alignment & Completion

*   **Observation**: After implementing the "Temporal Patch" logic, the orchestrator test (`115`) passed, confirming the final database state was correct. However, the planner test (`113`) still failed for the `contains` scenario.
*   **Analysis**: The planner was generating a highly efficient single `UPDATE` operation, while the test expectation was for a less optimal `DELETE` and `INSERT`. The planner's output was correct and more performant.
*   **Action**: The expectation file `113_test_set_insert_or_replace.out` has been updated to match the more efficient plan. With this change, all tests for the semantic alignment phase now pass.

### 8.3 Phase 2 - Step 3: Correct `_replace` `NULL` Handling

*   **Observation**: A bug was found where `plan_set_insert_or_replace` was using `jsonb_strip_nulls`, which is `_update` behavior. For a `replace` operation, a `NULL` in the source data is a meaningful value that must overwrite a non-`NULL` value in the target.
*   **Action**:
    1.  Removed the `jsonb_strip_nulls` call from the `source_rows` CTE in `plan_set_insert_or_replace_generic_valid_time_table`.
    2.  Added new test cases to the planner (`113`) and orchestrator (`115`) tests to explicitly verify that a source `NULL` correctly overwrites an existing value in the target table.
*   **Status**: **COMPLETED**. This change ensures the `_replace` function now correctly handles `NULL` values according to its defined semantics.

---
## 9. Phase 3: Regression Analysis and Fix

With the core functions implemented and integrated, this phase focuses on resolving regressions found during full-system testing.

*   **Status**: **COMPLETED**.
*   **Task**: The bug preventing statistical variables from being inserted has been fixed. The `process_statistical_variables` procedure now correctly uses the `set_insert_or_replace_generic_valid_time_table` function.
*   **Details**: The `_update` function was previously used, but its `jsonb_strip_nulls` behavior was incorrect for the `stat_for_unit` table, where a `NULL` in one typed `value_*` column is meaningful when another is set. The `_replace` function correctly handles this semantic requirement by overwriting the entire data payload. This change was unblocked by the fix for an `infinity`-related bug in the `_replace` planner. For a detailed log of the investigation and resolution, see `journal.md`.

---
## 11. Phase 5: Proposal for a "Batch Fence" Mechanism for Intra-Batch Dependencies

### 11.1. Problem Recap: The Challenge of Intra-Batch Dependencies

A critical challenge during the processing phase is handling intra-batch data dependencies. This occurs when multiple rows within the same processing batch refer to the same conceptual entity, but that entity does not yet exist in the database.

A common scenario:
1.  **Row A**: An `INSERT` operation for a new legal unit identified by `tax_ident='123'`. This operation will generate a new `legal_unit.id`.
2.  **Row B**: A `REPLACE` operation for the same legal unit (`tax_ident='123'`), representing a subsequent historical slice. This operation *needs* the `legal_unit.id` generated by Row A.

If both Row A and Row B are in the same batch, the `process_legal_unit` procedure must ensure that the ID generated from processing Row A is correctly propagated and available for Row B before Row B is processed.

### 11.2. Current Solution and Its Fragility

The current system solves this with ID propagation logic embedded within each `process_*` procedure (e.g., `process_legal_unit`, `process_establishment`). This logic is responsible for:
1.  Identifying `INSERT` operations within the batch.
2.  Executing them to generate new entity IDs.
3.  Updating the job's `_data` table to back-fill these new IDs into all other rows in the batch that refer to the same conceptual entity.
4.  Finally, calling the `set_*` function with the fully resolved batch.

As documented in "Phase 4: Final Regression Fixes," this propagation logic, while functional, is complex and has been a source of subtle bugs. Its duplication across multiple `process_*` procedures increases the maintenance burden and risk of future regressions.

### 11.3. Proposed Alternative: The "Batch Fence"

To create a more robust and decoupled solution, we propose the "Batch Fence" mechanism. This approach makes dependencies explicit in the data and simplifies the processing logic.

**Implementation Sketch:**

1.  **New Data Column**: Add a `batch_fence BOOLEAN NOT NULL DEFAULT FALSE` column to the `_data` table schema. A row with `batch_fence = TRUE` signifies that a batch must end *before* this row.

2.  **New Analysis Step**: Introduce a new, holistic analysis step (e.g., `analyse_dependencies`) that runs after `analyse_external_idents`.
    *   This step scans the entire `_data` table to build a dependency graph based on external identifiers.
    *   For each group of dependent rows (like the `INSERT`/`REPLACE` example above), it would sort them chronologically or by operation type (`INSERT` first).
    *   It would then set `batch_fence = TRUE` on every row except the first in each dependent sequence.
    *   *Example*: For `tax_ident='123'`, Row A (`INSERT`) would have `batch_fence=FALSE`, while Row B (`REPLACE`) would have `batch_fence=TRUE`.

3.  **Modified Batching Logic**: The `admin.import_job_processing_phase` procedure would be modified. When selecting a batch of rows to process, it would also scan for the first row with `batch_fence = TRUE`. If a fence is found within the potential batch size, the batch is truncated to include only the rows *before* the fence.

**Workflow with Batch Fences:**

1.  The `analyse_dependencies` step runs once, marking all dependent rows.
2.  The processing phase begins. It selects a batch, but the batch is stopped by the fence on Row B. The first batch contains only Row A.
3.  `process_legal_unit` executes for Row A. The new `legal_unit.id` is created and stored in the `_data` table for Row A. A separate mechanism (or a re-run of `analyse_external_idents` on unresolved rows) would then need to propagate this ID to other rows like B.
4.  The worker commits and is re-queued.
5.  On the next run, the `_data` table is fully consistent. Row B now has the required `legal_unit_id`, and processing can continue with the next batch, which starts with Row B.

### 11.4. Benefits and Drawbacks

*   **Benefits**:
    *   **Robustness**: Eliminates complex, stateful ID propagation logic from `process_*` procedures, making them simpler and less error-prone.
    *   **Explicitness**: Dependencies are explicitly declared in the data, making the system's behavior easier to trace and debug.
    *   **Centralization**: Dependency logic is handled in one place (`analyse_dependencies`) rather than being scattered across multiple procedures.

*   **Drawbacks**:
    *   **Performance**: The mechanism would likely result in more, smaller batches. This could increase transactional overhead and potentially slow down the overall import process, although it guarantees correctness.
    *   **Complexity Shift**: The complexity moves from the `process_*` procedures to the `analyse_dependencies` step and the batch selection logic. The ID propagation logic also needs to be re-thought; perhaps `analyse_external_idents` is re-run between fenced batches.

### 11.5. Recommendation

The current ID propagation mechanism, now fixed, is functional. The "Batch Fence" is a powerful architectural alternative that prioritizes robustness and explicit state over potentially more performant, larger batches.

This proposal should be kept as a candidate for future implementation if the current in-procedure propagation logic proves to be a recurring source of maintenance issues or bugs.

---
## 12. Phase 6: Final Test Suite Refactoring

*   **Status**: **COMPLETED**.
*   **Task**: Consolidate and specialize the test suites to improve clarity and maintainability.
*   **Details**: The original planner and orchestrator tests (`113` through `117`) were refactored to create a more logical structure.
    *   **Planner Tests (`113`, `114`)**: Remain as comprehensive, case-by-case validators for the `plan_*` functions.
    *   **Single-Key Orchestrator Tests (`115`, `116`)**: These files now contain a curated set of the most important orchestrator tests for single-key entities, focusing on the final database state for both `_replace` and `_update` modes.
    *   **Composite/Surrogate Key Test (`117`)**: This file has been specialized to exclusively test scenarios involving composite and surrogate (`SERIAL`/`IDENTITY`) keys for both `_replace` and `_update` modes.
*   **Outcome**: The test suite is now more organized, with a clear separation of concerns that makes it easier to maintain and extend. This concludes the development and testing cycle for the set-based temporal functions.

---
## 13. Phase 7: Semantic Correction for NOOP on Non-Existent Entities

*   **Problem**: A semantic bug was discovered where `set_insert_or_replace` and `set_insert_or_update` incorrectly perform an `INSERT` when called for an entity that doesn't exist in the target table.
*   **Required Behavior**: A `REPLACE` or `UPDATE` operation on a non-existent entity should be a NOOP (No Operation). The function must return a `status` column of type `import.set_result_status` with the value `'MISSING_TARGET'`. This behavior, however, must be explicitly requested by the caller to resolve the API ambiguity.
*   **Action**:
    1.  **Create `mode` ENUM**: Create a new `ENUM` type `import.set_operation_mode` with values (`'insert_or_update'`, `'update_only'`, `'insert_or_replace'`, `'replace_only'`) to make the caller's intent explicit.
    2.  **Update Function API**: Add a `p_mode import.set_operation_mode` parameter to all `set_*` and `plan_*` functions.
    3.  **Refactor Planner**: The logic in `plan_set_*` functions will be refactored. A new `source_initial` CTE will be introduced. The main `source_rows` CTE will then filter rows from `source_initial` based on the `p_mode`. If the mode is `update_only` or `replace_only`, source rows for entities not present in the target table will be discarded.
    4.  **Fix Regressions**: The flawed logic that caused the regressions will be reverted as part of this refactoring, ensuring the default `insert_or_*` modes work correctly.
*   **Status**: **PENDING**. The final, robust API has been designed. Awaiting implementation.

---
## 14. Phase 8: Code Consolidation and Final Implementation

This phase implements the final, unified API by consolidating the separate `_update` and `_replace` functions into a single, robust `temporal_merge` implementation.

### 14.1. Rationale

The separate development of `_update` and `_replace` functions was crucial for ensuring semantic correctness. With the semantics now finalized, maintaining two separate, largely identical codebases is inefficient. This consolidation will reduce code duplication, improve maintainability, and align the implementation with the final `sql_saga` vision.

### 14.2. Detailed Plan

1.  **Create New Consolidated Files**:
    *   Create a single new migration file: `migrations/YYYYMMDDHHmmSS_create_temporal_merge_functions.up.sql`.
    *   Create new, unified test files:
        *   `test/sql/118_test_temporal_merge.sql` (replaces `113`, `114`, `115`, `116`).
        *   `test/sql/119_test_temporal_merge_composite_key.sql` (replaces `117`).

2.  **Implement Unified `temporal_merge` Functions**:
    *   In the new migration file, create `temporal_merge_plan` and `temporal_merge`, porting and unifying the logic from the old `_update` and `_replace` functions.

3.  **Port and Consolidate Tests**:
    *   Create the new test files (`118` and `119`) with a new, unified structure. Each file will begin with a commented "Table of Contents" that clearly lists every scenario being tested.
    *   Each scenario will be a self-contained block that validates the entire workflow:
        1.  **Setup**: Define the initial state of the source and target tables.
        2.  **Test Planner**: Execute `temporal_merge_plan` and compare `Actual Plan` vs. `Expected Plan`.
        3.  **Test Orchestrator**: Execute `temporal_merge` and compare `Actual Feedback` and `Actual Final State` vs. expected values.
    *   Port all test cases from the old files (`113`-`117`) into this new structure.

4.  **Verification (Pause Point)**:
    *   After the new test files are created and populated, work will **pause**.
    *   An instruction will be generated for a separate Verification Agent. This agent's task is to perform a detailed review of the new test files (`118`, `119`) against the old ones (`113`-`117`).
    *   The verification must confirm two key points:
        1.  **Completeness**: All test scenarios from the old files have been correctly ported.
        2.  **Coverage**: The new suite continues to provide comprehensive coverage for all relevant Allen's Interval Algebra relations.

5.  **Cleanup (Post-Verification)**:
    *   **Only after the verification is approved**, the old migration files (`..._replace_functions.up.sql`, `..._update_functions.up.sql`) and old test files (`113`, `114`, `115`, `116`, `117`) will be deleted.

*   **Status**: **PENDING**. Awaiting approval to begin this refactoring.

