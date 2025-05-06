# Future Improvements for the Import System (`import_job`)

This document outlines potential future improvements and design considerations for the `import_job` system, following the initial refactoring. The core system is documented in `doc/import-system.md`.

## Next Steps / TODO

*   **Testing:** Thoroughly test the implemented flow with various scenarios (valid data, different `strategy` settings, errors during analysis, errors during operation phase, large files, concurrent jobs). Run and potentially expand pg_regress tests (`test/sql/52_revised_import_jobs_for_norway_small_history.sql`). Verify `SKIP LOCKED` behavior under concurrency.
*   **Code Review:** Review the implemented migrations and procedures for correctness, efficiency, and adherence to conventions, particularly the batch analysis logic (`analyse_*` procedures using `ctid`s and `SKIP LOCKED`), the batch operation logic (`process_*` procedures using triggers where applicable), the snapshot handling within `import_job_derive`, and the lifecycle callbacks for dynamic columns.
*   **Batch Operations Design Review:** Review the design proposal below for implementing *direct* batch DML in the `process_*` procedures (instead of relying solely on triggers). Decide whether to proceed with implementation, considering the complexity vs. potential performance gains, especially for non-temporal tables. Note that `external_idents` no longer has a process procedure.
*   **UI Integration:** Update the frontend application to interact with the new import job system (creating jobs, uploading files, monitoring progress via `get_import_job_progress`).
*   **Error Reporting:** Improve the granularity and presentation of errors stored in the `_data` table's `error` JSONB column. Consider linking errors back to specific source file lines if possible (might require adding a line number column to `_upload` and `_data`).
*   **Definition Management UI:** Create a UI for administrators to manage `import_definition` records, including steps, data columns, source columns, and mappings.
*   **Performance Optimization:** Profile the import process with large datasets and identify bottlenecks in the orchestrator or specific processing procedures.

## Design Proposal: Direct Batch Operations (`process_*` Procedures)

The current implementation of the `process_*` procedures leverages existing `_era` table triggers to handle the final database modifications, simplifying the procedure logic to just perform batch `INSERT`s into the `_era` table. While functional and leveraging existing temporal logic, this section outlines an alternative design for refactoring these procedures to use *direct* batch DML operations against the target tables, potentially offering performance benefits but increasing complexity.

### Goal

Perform `INSERT`, `UPDATE`, or `UPSERT` operations *directly* against the final target tables (e.g., `legal_unit`, `location`, `activity`) using single SQL statements that process the entire batch of rows (`p_batch_ctids`) provided to the `process_*` procedure, respecting the `import_definition.strategy`, and *manually handling temporal logic* within the procedure if necessary.

### Proposed Approach

Modify each `process_*` procedure to:

1.  **Fetch Batch Data**: Select all necessary data for the batch from the job's `_data` table into a temporary table or CTE. This includes source values, `typed_input` values (like looked-up FKs), and `target_primary_id` values from previous steps (e.g., `legal_unit_id`).
    ```sql
    CREATE TEMP TABLE temp_batch_data AS
    SELECT dt.* -- Select all needed columns
    FROM public.%I dt -- The job's _data table
    WHERE dt.ctid = ANY(p_batch_ctids);
    ```
2.  **Determine Existing Records (for Update/Upsert)**: If `strategy` is `update_only` or `upsert`, join `temp_batch_data` with the target table(s) based on the appropriate unique identifiers (e.g., external IDs looked up previously, or the base table PK if available) to identify existing records that correspond to the batch rows. Store these existing target table PKs in the temporary table.
    ```sql
    ALTER TABLE temp_batch_data ADD COLUMN existing_target_id INT;
    UPDATE temp_batch_data tbd SET existing_target_id = tt.id
    FROM public.target_table tt -- e.g., legal_unit
    -- JOIN based on unique identifier match (e.g., external ID value)
    WHERE tt.unique_ident_column = tbd.unique_ident_source_column;
    ```
3.  **Execute Batch DML based on `strategy`**:
    *   **`insert_only`**:
        *   Perform `INSERT INTO target_table (...) SELECT ... FROM temp_batch_data WHERE existing_target_id IS NULL;`.
        *   For temporal `_era` tables, this is straightforward.
    *   **`update_only`**:
        *   Perform `UPDATE target_table tt SET ... FROM temp_batch_data tbd WHERE tt.id = tbd.existing_target_id;`.
        *   For temporal `_era` tables, this is complex. It might require inserting *new* eras based on the updated data and potentially closing off old eras, which is difficult to do purely in batch. **Alternative:** See "Temporal Table Handling" below.
    *   **`upsert`**:
        *   Use `INSERT INTO target_table (...) SELECT ... FROM temp_batch_data ON CONFLICT (unique_constraint_columns) DO UPDATE SET ...;`.
        *   This works well for non-temporal tables with clear unique constraints.
        *   For temporal `_era` tables, `ON CONFLICT` is tricky due to the time dimension. **Alternative:** See "Temporal Table Handling" below.
4.  **Capture Resulting IDs**: Use the `RETURNING id` clause in the DML statements to capture the IDs of the inserted/updated rows. Update the `pk_id` column in the `_data` table via the `ctid` link (potentially joining back to `temp_batch_data`).
    ```sql
    WITH inserted_rows AS (
        INSERT INTO ... SELECT ... FROM temp_batch_data RETURNING id, ctid -- Assuming ctid was carried through
    )
    UPDATE public.%I dt SET pk_id_column_name = ir.id -- Replace pk_id_column_name
    FROM inserted_rows ir
    WHERE dt.ctid = ir.ctid;
    ```
5.  **Error Handling**: Batch DML makes row-level error handling difficult. If a single row violates a constraint (e.g., NOT NULL, FK), the entire batch statement typically fails.
    *   **Option 1 (Fail Fast - Current Approach for Batch Errors):** Catch the exception, mark the *entire batch* (identified by `p_batch_ctids`) as `error` in the `_data` table with the SQLERRM, and let the orchestrator continue with other batches/targets. Requires manual intervention for the failed batch.
    *   **Option 2 (Pre-computation/Validation):** Perform more rigorous checks during the *analysis* phase to minimize the chance of errors during the operation phase. This is the preferred approach.
    *   **Option 3 (Row-by-Row Fallback):** Attempt the batch operation. If it fails, fall back to a row-by-row loop *for that specific batch* (using the `p_batch_ctids`) to identify the problematic row(s) and mark only those as error. More complex but provides better granularity for DML errors.
6.  **Update `_data` Table Status**: Update `last_completed_priority` and `state` for successful rows in the `_data` table (identified by `p_batch_ctids`).

### Temporal Table Handling (`_era` tables)

Direct batch `UPDATE` or `UPSERT` on `_era` tables (like `location_era`, `activity_era`) is problematic because modifications often require inserting new rows and adjusting the `valid_to` of previous rows.

**Current Approach (Recommended):**

The implemented `process_*` procedures (like `process_location`, `process_activity`) handle temporal tables by performing a batch `INSERT` directly into the `_era` table (e.g., `location_era`, `activity_era`). They determine the `existing_target_id` beforehand and pass it as the `id` column in the `INSERT`. The existing `INSTEAD OF INSERT` triggers on the `_era` tables then handle the temporal logic correctly (closing old eras, inserting new ones).

**Advantages:**
*   Leverages existing, tested temporal logic in triggers.
*   Keeps `process_*` procedures simpler.
*   Handles `insert_only`, `update_only`, and `upsert` strategies correctly via the trigger logic based on whether `existing_target_id` is NULL or not.

**Disadvantages:**
*   Relies on trigger performance. Might be slightly slower than direct DML *if* the trigger logic could be perfectly replicated in batch SQL.

**Direct Batch DML Alternative (Complex, Not Recommended for Temporal):**

Implementing direct batch `UPDATE`/`UPSERT` *without* triggers would require replicating the temporal consistency logic within the batch procedure itself, involving steps like:
1.  Identifying rows for update vs. insert.
2.  Batch closing old eras (`UPDATE ... SET valid_to = ...`).
3.  Batch inserting new eras (`INSERT ...`).

This adds significant complexity, duplicates logic, and makes handling concurrency harder. It's generally not recommended unless the trigger approach proves to be a major, measurable bottleneck.

### Non-Temporal Table Handling

For non-temporal target tables (like `tag_for_unit`), the `process_*` procedures *can* perform direct batch DML (`INSERT ... ON CONFLICT`, `UPDATE`, `INSERT`) as shown in `admin.process_tags`, because the logic is much simpler.

### Dependencies

The batch operation for a step (e.g., `location`) must only run after the dependencies (e.g., `legal_unit`) have successfully completed their operation phase and populated the necessary `pk_id` (e.g., `legal_unit_id`) in the `_data` table. The orchestrator (`admin.import_job_process_phase`) handles this by processing steps in `priority` order and checking `last_completed_priority` when selecting batches. The batch select within the `process_*` procedure (Step 1) needs to include these dependency IDs from the `_data` table.

### Conclusion

The current implementation uses batch processing effectively in both the `analyse_*` and `process_*` phases. It leverages triggers for complex temporal logic in `process_*` procedures, simplifying the procedures themselves while still processing data in batches. Direct batch DML is used for simpler, non-temporal targets. Refactoring temporal `process_*` procedures to bypass triggers is possible but likely adds more complexity than benefit.
