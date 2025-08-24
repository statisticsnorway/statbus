# Advanced Data Flow: Intra-Batch Dependencies and the Two-Stage Process

## 1. Introduction

This document provides a detailed, step-by-step explanation of how the import system's architecture robustly handles the most complex intra-batch dependency scenario: processing a batch of historical records for a **new entity** whose database ID is not yet known.

This scenario proves why a "Batch Fence" mechanism is unnecessary. The combination of the two-stage logic within the `process_*` procedures and the explicit `mode` parameter passed to the `temporal_merge` function solves this problem efficiently and safely within a single transaction.

## 2. The Scenario: A New Legal Unit's History

Imagine a batch of rows passed to `import.process_legal_unit`. This batch represents the entire history of a new legal unit that does not yet exist in the database.

*   **The Data**: The batch contains multiple rows for this new legal unit.
    *   `legal_unit_id` is `NULL` for all rows.
    *   All rows share the same `founding_row_id` (e.g., `5`), which is the `row_id` of the first historical record. This is how the system knows they belong to the same conceptual entity.
    *   The core data for the `legal_unit` table (e.g., `name`) is identical across all rows. The historical changes are in related data (like `location` or `employees`), which will be handled by later steps.

*   **Source Batch in `_data` Table (Simplified):**
| `row_id` | `founding_row_id` | `action` | `legal_unit_id` | `valid_from` | `name` |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **5** | 5 | `insert` | `NULL` | 2020-01-01 | Statbus Inc. |
| 6 | 5 | `replace`| `NULL` | 2021-01-01 | Statbus Inc. |
| 7 | 5 | `replace`| `NULL` | 2022-01-01 | Statbus Inc. |

## 3. Step-by-Step Execution Flow

The `import.process_legal_unit` procedure executes the following logic within a **single database transaction**.

### Stage 1: Process `INSERT` Actions to Create New Entities

1.  **Isolate Inserts**: The procedure first identifies all rows in the batch with `action = 'insert'`.
    *   **Result**: It finds only **Row 5**.

2.  **Call Orchestrator for Inserts**: It makes a call to `temporal_merge` for the batch containing just **Row 5**, using the mode `'upsert_replace'`.
    *   The planner sees this is a simple `INSERT` for a new entity.
    *   The orchestrator executes the `INSERT` into the `public.legal_unit` table. The database generates a new, unique `legal_unit_id` (e.g., `123`).
    *   The orchestrator returns a `SUCCESS` result, mapping the new `legal_unit_id=123` back to the `source_row_id=5`.

3.  **Propagate the New ID**: This is a critical step. The procedure receives the result for Row 5. It then uses the `founding_row_id` to propagate the new ID to **all other related rows** in the main `_data` table.
    *   **Logic**: `UPDATE ..._data SET legal_unit_id = 123 WHERE founding_row_id = 5;`
    *   **Result**: Rows 6 and 7 in the `_data` table now have `legal_unit_id = 123`. The entire conceptual entity is now anchored to a stable database ID.

### Stage 2: Process `REPLACE` Actions for Existing Entities

4.  **Isolate Replaces**: The procedure now identifies all rows with `action = 'replace'`.
    *   **Result**: It finds Rows 6 and 7. Both now have `legal_unit_id = 123`.

5.  **Call Orchestrator for Replaces**: It makes a *second* call to `temporal_merge` for the batch containing **Rows 6 and 7**, but this time it critically uses the mode `'replace_only'`.
    *   **Why `replace_only` is crucial**: This provides a safety guarantee. It tells the function to *only* modify the timeline for an entity that already exists. If, for some reason, the ID propagation in Stage 1 had failed and `legal_unit_id` was still `NULL`, this call would result in a `MISSING_TARGET` status instead of accidentally creating a new, duplicate legal unit.

6.  **Planner Merges and Aggregates**:
    *   The planner receives Rows 6 and 7. Since the mode is `'replace_only'` and `legal_unit_id=123` exists, it proceeds.
    *   It sees they are for the same `legal_unit_id`, are contiguous in time, and have identical core data (`name: 'Statbus Inc.'`).
    *   It correctly **merges** them into a single, longer historical slice.
    *   Crucially, it aggregates their `row_id`s into the `source_row_ids` array: `{6, 7}`.
    *   It generates a single plan operation for this merged slice.

7.  **Orchestrator Executes and Reports Completely**:
    *   The orchestrator executes the single DML operation from the plan.
    *   It sees the `source_row_ids: {6, 7}`. It unnests this array and returns a `SUCCESS` result for **both** `source_row_id=6` and `source_row_id=7`, associating both with `legal_unit_id=123`.

## 4. Final State and Conclusion

*   **Final `_data` Table State**:
| `row_id` | `founding_row_id` | `action` | `legal_unit_id` | `valid_from` | `name` |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 5 | 5 | `insert` | `123` | 2020-01-01 | Statbus Inc. |
| 6 | 5 | `replace`| `123` | 2021-01-01 | Statbus Inc. |
| 7 | 5 | `replace`| `123` | 2022-01-01 | Statbus Inc. |

*   **Final `legal_unit` Table State**: A clean, correct history for the new legal unit with `id=123`.

This entire, complex dependency chain is resolved correctly **within a single transaction**. Subsequent processing steps (like `process_location` or `process_statistical_variables`) can now run, and they will find the correct `legal_unit_id` for all rows (5, 6, and 7), allowing them to link related data correctly.

This demonstrates that the combination of the two-stage processing logic and the explicit `mode` parameter provides a robust, efficient, and sufficient solution for handling intra-batch dependencies.
