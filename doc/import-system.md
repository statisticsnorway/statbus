# Statbus Import System (`import_job`)

## Introduction

The Statbus import system provides a flexible and robust way to load external data into the statistical unit register. It replaces the older, view-based import mechanism with a declarative, multi-stage, batch-oriented process managed through the `import_job` table and associated metadata.

This system allows defining complex import processes that can affect multiple related tables (like legal units, establishments, locations, activities, contacts, etc.) within a single, manageable import job.

## Core Concepts

The import system is built around several key database tables and concepts:

1.  **Import Definition (`import_definition`)**:
    *   Represents a specific *type* of import (e.g., "Import Legal Units for Current Year", "Import Establishments with Explicit Dates").
    *   Defines the overall behavior, such as the final database operation (`strategy`: `insert_or_replace`, `insert_only`, `replace_only`).
    *   Is linked to the specific `import_step` records it utilizes via the `import_definition_step` table.
    *   Links together all the necessary components for the chosen steps: source columns, data columns, and mappings.
    *   Can optionally reference a `time_context` for automatic validity period calculation.

2.  **Import Step (`import_step`)**:
    *   Represents a logical *step* or *component* available for use within an import definition (e.g., processing `legal_unit` data, handling `physical_location`, linking `external_idents`). Identified by a unique `code` (using `snake_case`).
    *   Has a human-readable `name` for display purposes.
    *   Steps have a defined `priority` which dictates the execution order when multiple steps are included in a definition.
    *   Each step can have an associated `analyse_procedure` and/or `process_procedure` which contain the specific PL/pgSQL logic for that step. Procedure names should generally correspond to the step `code` (e.g., `admin.analyse_legal_unit`, `admin.process_location`).

3.  **Definition Steps (`import_definition_step`)**:
    *   A linking table connecting an `import_definition` to the specific `import_step` records it will execute. This allows a definition to use a subset of available steps in the correct order.

4.  **Source Columns (`import_source_column`)**:
    *   Defines the expected columns and their order (`priority`) in the source file (e.g., CSV) for a given `import_definition`.

5.  **Data Columns (`import_data_column`)**:
    *   Declaratively defines the *complete schema* of the intermediate `_data` table created specifically for each import job. This table includes a dedicated `row_id` column (e.g., `SERIAL` or `IDENTITY`) for stable row identification.
    *   Specifies which columns (with `purpose='source_input'`) uniquely identify a row (`is_uniquely_identifying`) for the `UPSERT` logic during the prepare step.
    *   Columns have a defined `purpose` (enum `public.import_data_column_purpose`):
        *   `source_input`: Holds data directly mapped from the source file - always `TEXT`.
        *   `internal`: Stores intermediate results from analysis steps, such as looked-up foreign keys (`sector_id`), type-casted values (`typed_birth_date`), context-derived values (`computed_valid_from`), or the intended row action (`operation`, `action`). Data type matches the intermediate value (e.g., `INTEGER`, `DATE`, `public.import_row_action_type`).
        *   `pk_id`: Stores the primary key(s) of the record(s) inserted/updated into a final Statbus table by a `process_procedure` (e.g., `legal_unit_id`, `physical_location_id`, `contact_info_ids`). Data type is typically `INTEGER` or `INTEGER[]`.
        *   `metadata`: Internal columns for tracking row status and errors (`state`, `error`, `last_completed_priority`).
    *   Each data column is linked to an `import_step` that primarily produces or consumes it (via `step_id`). Metadata columns have `step_id = NULL`.

6.  **Mapping (`import_mapping`)**:
    *   Connects an `import_source_column` (or a fixed value/expression) for a specific `import_definition` to an `import_data_column` (found via the steps linked to the definition) with `purpose = 'source_input'`.
    *   Defines how data flows from the uploaded file into the job's intermediate `_data` table.

7.  **Processing Procedures (`analyse_procedure`, `process_procedure`)**:
    *   PL/pgSQL functions linked to `import_step` records.
    *   They contain the actual logic for:
        *   **Analysis (`analyse_procedure`):**
            *   Reads `source_input` columns.
            *   Performs lookups (e.g., finding `sector_id` from `sector_code`), type casting (e.g., `admin.safe_cast_to_date`), and validations.
            *   Stores results in `internal` columns (e.g., `sector_id`, `typed_birth_date`).
            *   **Error Handling (JSONB Columns `error` and `invalid_codes`)**:
                *   Each `analyse_procedure` is authoritative for specific keys within the `error` and `invalid_codes` JSONB columns. A key typically corresponds to an input data column name (e.g., `sector_code`, `physical_latitude`) or a specific validation type (e.g., `inconsistent_legal_unit`, `invalid_period_source`).
                *   **Hard Errors (`error` column)**: Critical issues (e.g., malformed mandatory dates, missing essential identifiers for `external_idents` step) that prevent further processing.
                    *   These populate the `error` JSONB column with a key-value pair, where the key indicates the error type/source and the value describes the error (e.g., `{"valid_from_source": "Invalid format"}`).
                    *   The procedure sets `state = 'error'` and `action = 'skip'`.
                    *   When adding a new hard error, a step should merge its error JSONB object with the existing `dt.error` (e.g., `COALESCE(dt.error, '{}'::jsonb) || new_error_details_jsonb`).
                    *   If a step resolves a hard error it previously reported (or if the condition for the error no longer applies after re-evaluation), it should clear *only its specific key(s)* from the `error` column (e.g., `dt.error - 'my_error_key'`). It must not clear keys reported by other steps.
                *   **Soft Errors / Invalid Codes (`invalid_codes` column)**: Non-critical issues where specific input codes (e.g., `sector_code`) are not found, or optional data is malformed but doesn't halt further analysis by other steps.
                    *   These populate the `invalid_codes` JSONB column, typically storing the original problematic value (e.g., `{"sector_code": "INVALID_XYZ"}`).
                    *   They do *not* directly set `state = 'error'` or `action = 'skip'`. The row continues analysis.
                    *   `invalid_codes` should be treated as additive. A step appends its new soft errors by merging its `invalid_codes` JSONB object with the existing `dt.invalid_codes` (e.g., `COALESCE(dt.invalid_codes, '{}'::jsonb) || new_invalid_codes_jsonb`).
                    *   If a step resolves a soft error it previously reported (e.g., an invalid code becomes valid upon re-evaluation or data correction), it should clear *only its specific key(s)* from the `invalid_codes` column (e.g., `dt.invalid_codes - 'my_invalid_code_key'`).
                    *   If a `process_` step relies on a resolved ID that couldn't be derived due to an invalid code, that specific attribute might not be set, or the `process_` step might skip that part of the operation for the row.
            *   The `external_idents` step specifically determines the potential `operation` (`insert`, `replace`, `update`) based on identifier lookups, and the final `action` (`insert`, `replace`, `update`, or `skip`) based on the `operation`, job's `strategy`, and any hard errors.
            *   Updates the row's `state` (to `analysing`, or `error` for hard errors), `error` (for hard errors), `invalid_codes` (for soft errors), and `last_completed_priority`.
        *   **Operation (`process_procedure`):** Reads `source_input` and `internal` columns, including the `action` column. Performs the final `INSERT` (for `action='insert'`), `REPLACE` (for `action='replace'`), or `UPDATE` (for `action='update'`) into the target Statbus tables, respecting the job's `strategy`. Skips rows where `action='skip'`. Stores the resulting primary key(s) in the corresponding `pk_id` column. Updates the row's `state` (to `processing` or `error` if the DML fails), `error`, and `last_completed_priority`. *Note: Some steps like `external_idents` only perform analysis and do not have a process procedure.*
    *   **Temporal Slicing Principle**: A new temporal slice (i.e., a new row with adjusted `valid_after`/`valid_to`) is created in a specific target table (e.g., `public.legal_unit`, `public.location`) *only* when "core" data fields *within that specific table* change. Changes in related tables (e.g., a `location` change for a `legal_unit`) will create new slices in the related table (`public.location`) but not necessarily in the parent table (`public.legal_unit`) unless the parent table's own core data also changes (e.g., if the `legal_unit`'s `status_id` changes due to the location change). The `public.statistical_unit` view then joins these tables to present a consolidated timeline. This timeline may appear more fragmented if related data changes frequently. Furthermore, the `public.statistical_unit` view will also create distinct temporal slices if the *source data itself* defines different `valid_from`/`valid_to` periods for an entity, even if the core attributes of the primary target table (e.g., `public.legal_unit`) do not change across these source-defined periods. This ensures `statistical_unit` reflects the most granular temporal segmentation available from all contributing data sources and underlying tables.
    *   These procedures operate on batches of rows identified by an array of their `row_id` values (e.g., `INTEGER[]`). The `row_id` is a stable, dedicated identifier within the job-specific `_data` table, used instead of PostgreSQL's system column `ctid` because `ctid` can change during row updates or table maintenance, making it unreliable for this multi-stage process. When these `row_id`s are temporarily stored (e.g., in a `TEMP TABLE` for batch processing), the column holding them in the temporary table is typically named `data_row_id` for clarity. They use `FOR UPDATE SKIP LOCKED` when selecting batches to handle concurrency.

8.  **Import Job (`import_job`)**:
    *   Represents a specific instance of an import, created by a user based on an `import_definition`.
    *   Tracks the overall state (`waiting_for_upload`, `upload_completed`, `preparing_data`, `analysing_data`, `processing_data`, `finished`, etc.).
    *   Manages the job-specific tables (`_upload`, `_data`).
    *   Keeps a snapshot of the import definition and related tables in the `definition_snapshot` JSONB column.
    *   Processed asynchronously by the `worker` system.

9.  **Job-Specific Tables & Snapshot**:
    *   `<job_slug>_upload`: Stores the raw data exactly as uploaded from the source file. Columns match `import_source_column`.
    *   `<job_slug>_data`: The intermediate table structured according to `import_data_column`. This table includes a dedicated `row_id` column (e.g., `SERIAL` or `IDENTITY`) for stable row identification throughout the import process. It holds source data (`source_input`), analysis results (`internal`, including `operation` and `action`), final primary keys (`pk_id`), and row-level state (`pending`, `analysing`, `analysed`, `processing`, `processed`, `error`) and progress (`last_completed_priority`).
    *   `definition_snapshot` (column in `import_job`): Contains a JSONB snapshot of the `import_definition` and its related metadata as they existed when the job was created. This ensures the job runs consistently even if the definition is modified later.
        *   `import_definition`: The `import_definition` row.
        *   `import_step_list`: An array of `import_step` objects.
        *   `import_data_column_list`: An array of `import_data_column` objects relevant to the definition's steps.
        *   `import_source_column_list`: An array of `import_source_column` objects for the definition.
        *   `import_mapping_list`: An array of objects, where each object contains:
            *   `mapping`: The `import_mapping` row itself.
            *   `source_column`: The full `import_source_column` object (if mapped from a source column, else null).
            *   `target_data_column`: The full `import_data_column` object that is the target of the mapping.
        This enriched `import_mapping_list` simplifies access to related source and target column details during job processing.

## Import Process Flow

1.  **Job Creation**: A user selects an `import_definition` via the UI and creates a new `import_job`.
    *   The system generates the job-specific `_upload` and `_data` tables based on the definition metadata. The `_data` table will include a `row_id` column.
    *   The `definition_snapshot` column in `import_job` is populated.
    *   The job starts in the `waiting_for_upload` state.
2.  **Upload**: The user uploads a source file (e.g., CSV) matching the `import_source_column` records associated with the job's `definition_id`.
    *   Data is copied into the job's `_upload` table.
    *   The job state transitions to `upload_completed`.
3.  **Worker Processing (`admin.import_job_process`)**: The worker picks up the job.
    *   **Prepare (`admin.import_job_prepare`)**:
        *   Reads the enriched `import_mapping_list` from the `definition_snapshot`. Each item in this list now directly contains the `import_mapping` record, the associated `import_source_column` record (if applicable), and the `import_data_column` record.
        *   Constructs an `UPSERT` statement to move data from the `_upload` table into the `_data` table.
        *   **Crucially, only `source_input` data columns that have a corresponding entry in `import_mapping_list` are included in the `INSERT` and `SELECT` clauses.** The order of columns is determined by the order of mappings (e.g., `ORDER BY mapping.id`).
        *   The `ON CONFLICT` clause uses `target_data_column`s (from the mapping items) that are marked `is_uniquely_identifying`.
        *   The `DO UPDATE SET` clause updates all inserted columns that are not part of the conflict key.
        *   Sets initial row state to `pending` and `last_completed_priority` to 0 in the `_data` table for all newly inserted/updated rows.
        *   Job state moves to `preparing_data`. The worker is rescheduled.
    *   **Analyse (`admin.import_job_process_phase('analyse')`)**:
        *   Job state moves to `analysing_data`.
        *   Iterates through `import_step`s (from the `definition_snapshot`'s `import_step_list`) in `priority` order.
        *   For each step with an `analyse_procedure`:
            *   Selects batches of rows from `_data` (identified by their `row_id`) where `state = 'analysing'` (or `state = 'pending'` for the first analysis step) and `last_completed_priority < step.priority`. Rows with `action = 'skip'` due to a hard error in a *prior* step are typically not re-selected for analysis by subsequent steps, though `last_completed_priority` might still be advanced for them.
            *   Calls the step's `analyse_procedure` with the batch of `row_id`s.
            *   The procedure performs lookups/validations, updates `internal` columns, `error` (for hard errors), and `invalid_codes` (for soft errors).
            *   **Error Handling Rule for Analysis Procedures**:
                *   **Hard Errors**: If an `analyse_procedure` detects a critical error that makes the row unprocessable for its specific domain (or subsequent domains that depend on its output), it *must*:
                    *   Populate the `error` JSONB column with details, merging with existing errors (e.g., `COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object('my_error_key', 'description')`).
                    *   Set the row's `state` to `'error'`.
                    *   Set the row's `action` to `'skip'::public.import_row_action_type`.
                    *   The `last_completed_priority` should be advanced to the current step's priority, even on error, to indicate which step identified the issue.
                *   **Soft Errors / Invalid Codes**: If an `analyse_procedure` detects a non-critical issue (e.g., an unresolvable `sector_code`), it should:
                    *   Populate the `invalid_codes` JSONB column, merging with existing invalid codes (e.g., `COALESCE(dt.invalid_codes, '{}'::jsonb) || jsonb_build_object('my_code_key', 'original_value')`).
                    *   It should *not* set `state = 'error'` or `action = 'skip'` solely for this reason.
                    *   The row's `state` remains `'analysing'` (or proceeds as normal).
                    *   `last_completed_priority` is advanced.
            *   If no hard error is found by the current step, it updates `last_completed_priority = step.priority`. The `state` remains `'analysing'` (or advances if this is the last analysis step for the row). The `action` (e.g., 'insert', 'replace', 'update') determined by `analyse_external_idents` (or potentially modified to 'skip' by a prior analysis step that found a hard error) is preserved if no new hard error is found by the current step.
            *   When a step successfully processes data or resolves a previously reported issue, it should clear *only its specific keys* from the `error` and `invalid_codes` columns (e.g., `dt.error - 'my_error_key'`, `dt.invalid_codes - 'my_code_key'`). This ensures that errors or invalid codes reported by other steps are preserved.
            *   *Note: The `edit_info` step populates `edit_by_user_id` and `edit_at`. The `analyse_external_idents` step is primarily responsible for determining the initial `operation` and `action` based on identifier lookups and job strategy. It also identifies hard errors related to identifiers, including "unstable identifiers." An unstable identifier error occurs if an input row identifies an existing unit but attempts to *change the value* of one of its existing external identifiers of a specific type; this results in `action = 'skip'`. Adding a new identifier type to an existing unit, or omitting an identifier type (which might imply removal by a `process_` step), are not considered unstable identifier errors by this specific check.*
        *   Continues processing batches across steps until `max_batches_per_transaction` is reached or no more rows are found for analysis in the current state/priority range.
        *   If work remains (either batch limit hit or rows still in `analysing` state), the job is rescheduled by the worker system.
        *   Once all analysis steps for all rows are complete (no rows left in `analysing` state, or all remaining rows are in `error` state with `action = 'skip'`), the job state moves to `processing_data` (or `waiting_for_review` if `job.review=true`). The worker is rescheduled if moving to `processing_data`.
    *   **Process (`admin.import_job_process_phase('process')`)**:
        *   Job state is `processing_data`.
        *   Iterates through `import_step`s (from the `definition_snapshot`'s `import_step_list`) in `priority` order.
        *   For each step with a `process_procedure`:
            *   Selects batches of rows from `_data` (identified by their `row_id`) where `state = 'processing'` and `last_completed_priority < step.priority` and crucially `action != 'skip'` using `FOR UPDATE SKIP LOCKED`. This ensures rows marked as error (and thus skip) in the analysis phase are not processed.
            *   Calls the step's `process_procedure` with the batch of `row_id`s.
            *   The procedure reads data (including `internal` results, audit info, and `action`), performs the final `INSERT` (for `action='insert'`) or `REPLACE` (for `action='replace'`, using `admin.batch_insert_or_replace_generic_valid_time_table` for temporal data), updates `pk_id` columns, and sets `last_completed_priority = step.priority`. If a `process_procedure` encounters an unrecoverable error for a row (which should be rare if analysis is robust), it should set that row's `state` to `'error'` and `action` to `'skip'`.
        *   Continues processing batches across steps until `max_batches_per_transaction` is reached or no more rows are found for processing in the current state/priority range.
        *   If work remains, the job is rescheduled.
        *   Once all operation steps for all rows are complete (no rows left in `processing` state), the job state moves to `finished`.

## Defining a New Import Type

Creating a new import type involves defining the metadata in the database:

1.  **Define Steps (`import_step`)**: Identify the logical steps required for the import (e.g., 'legal_unit', 'physical_location', 'establishment'). Define a unique `code` (using `snake_case`) and a human-readable `name` for each. Assign priorities and specify the names of the (yet to be created) `analyse_procedure` and `process_procedure` for each step (e.g., `admin.analyse_legal_unit`, `admin.process_legal_unit`).
2.  **Define Data Columns (`import_data_column`)**: For the new `step_id`, define *all* columns needed in the intermediate `_data` table:
    *   Columns for each piece of data coming directly from the source file (`purpose='source_input'`, `column_type='TEXT'`). Link each to the relevant `import_step` via `step_id`.
    *   Columns to store intermediate results from analysis steps (`purpose='internal'`, `column_type` matching the expected data type, e.g., `INTEGER`, `DATE`, `NUMERIC`, `public.import_row_action_type`). Link each to the `import_step` (via `step_id`) that produces it. *Includes audit columns like `edit_by_user_id`, `edit_at` produced by the `edit_info` step, and the `operation` and `action` columns produced by `external_idents`.*
    *   Columns to store the final inserted/updated primary keys (`purpose='pk_id'`, `column_type` usually `INTEGER` or `INTEGER[]`). Link each to the `import_step` (via `step_id`) that performs the final database operation.
    *   Set `is_uniquely_identifying = true` for the `source_input` data columns (belonging to the relevant step) that form the unique key for the prepare step's UPSERT logic.
    *   Remember that the `_data` table will also have a system-managed `row_id` column for stable row identification during processing.

3.  **Implement Procedures**: Write the PL/pgSQL functions named in the `import_step` records (`analyse_procedure`, `process_procedure`). These functions must:
    *   Accept `(p_job_id INT, p_batch_row_ids INTEGER[])` (or appropriate array type for `row_id`).
    *   Read `definition_snapshot` from `import_job` if needed.
    *   Determine the job-specific `_data` table name.
    *   Read from/write to the `_data` table using dynamic SQL and `p_batch_row_ids` (e.g., `WHERE row_id = ANY(p_batch_row_ids)`).
    *   Perform logic (lookups, validation, casting for analysis; final DML using audit info and `action` from `_data` for processing).
    *   Correctly update `last_completed_priority`, `state`, `action` (for hard errors), `error` (for hard errors), and `invalid_codes` (for soft errors) columns in `_data`, adhering to the key management principles (each step manages its own keys, `invalid_codes` is additive, `error` is merged, and specific keys are cleared upon resolution).
    *   **Error Handling Rule for Analysis Procedures (reiteration)**:
        *   **Hard Errors**: Set `state = 'error'`, `action = 'skip'`, populate `error` JSONB (merging with existing errors). `last_completed_priority` is advanced to the current step's priority. (Note: The `analyse_external_idents` step specifically flags attempts to *change an existing identifier's value* for an identified unit as a hard error, setting `action='skip'`. Adding new identifier types or omitting existing ones are not flagged by this specific "unstable identifier" check.)
        *   **Soft Errors**: Populate `invalid_codes` JSONB (merging with existing invalid codes). Do *not* set `state = 'error'` or `action = 'skip'` solely for this. `last_completed_priority` advances.
        *   **Clearing Errors**: If a condition is resolved, clear only the step-specific keys from `error` and/or `invalid_codes`.
    *   Handle batch-wide errors (e.g., constraint violation during a batch DML in a `process_procedure`) by marking all rows identified by `p_batch_row_ids` as error (and action='skip') in the `_data` table and potentially failing the job.
4.  **Create Definition (`import_definition`)**: Create a record defining the overall import (e.g., slug='legal_unit_import', name='Legal Unit Import', strategy='insert_or_replace'). Set `valid=false` initially.
5.  **Link Steps to Definition (`import_definition_step`)**: Insert records into `import_definition_step` linking the new `definition_id` to the `step_id`s of the chosen `import_step` records defined in step 1.
6.  **Define Source Columns (`import_source_column`)**: Define the expected columns in the source file and their order (`priority`) for this definition. These should cover the `source_input` data columns required by the *linked steps*.
7.  **Define Mappings (`import_mapping`)**: Create records linking each `import_source_column` (or a fixed `source_value`/`source_expression`) for this `definition_id` to its corresponding `import_data_column` (found via the linked steps, where `purpose='source_input'`). Ensure all necessary `source_input` columns for the linked steps are mapped.
8.  **Set Definition Valid**: Once steps 1-7 are complete and tested, update the `import_definition` record: `SET valid = true, validation_error = NULL`. This allows users to create `import_job`s based on this definition.

## Monitoring Imports

The progress of an import job can be monitored via:

*   The `public.import_job` table (overall state, row counts, timestamps).
*   The job-specific `_data` table (row-level state, errors, `last_completed_priority`, `action`, and individual `row_id`s).
*   The `public.get_import_job_progress(job_id)` function, which provides a JSON summary including row state counts.
*   The application UI, which uses these sources to display progress.

# Example: Defining an Import for Legal Units

Let's illustrate how to define an import for `legal_unit` data using the system. Assume we want an import definition named `legal_unit_explicit_dates` that takes a CSV with explicit `valid_from` and `valid_to` dates.

1.  **Identify Required Steps (`import_step`)**: We need steps to handle:
    *   Populating audit info (`edit_info`, priority 100).
    *   External identifiers (e.g., `tax_ident`) to find/create the `legal_unit` and determine the `operation` and `action` (`external_idents`, priority 10).
    *   Linking to an enterprise (`enterprise_link_for_legal_unit`, priority 18).
    *   Validity dates from the source file (`valid_time_from_source`, priority 15).
    *   Core `legal_unit` data (`legal_unit`, priority 20).
    *   Physical location (`physical_location`, priority 30).
    *   Postal location (`postal_location`, priority 40).
    *   Primary activity (`primary_activity`, priority 50).
    *   Secondary activity (`secondary_activity`, priority 60).
    *   Contact info (`contact`, priority 70).
    *   Statistical variables (`statistical_variables`, priority 80).
    *   Tags (`tags`, priority 90).
    *   Metadata (`metadata`, priority 110).

2.  **Define Data Columns (`import_data_column`)**: For this definition, we need columns in the `_data` table associated with the chosen steps (linked via `step_id`):
    *   **`edit_info` step:**
        *   `edit_by_user_id` (purpose: `internal`, type: `INTEGER`)
        *   `edit_at` (purpose: `internal`, type: `TIMESTAMPTZ`)
    *   **`external_idents` step:**
        *   `tax_ident` (purpose: `source_input`, type: `TEXT`, uniquely_identifying: `true`) - *Dynamically generated `import_data_column`. Its `column_name` ("tax_ident") matches an `external_ident_type.code`.*
        *   `stat_ident` (purpose: `source_input`, type: `TEXT`) - *Dynamically generated `import_data_column`. Its `column_name` ("stat_ident") matches an `external_ident_type.code`.*
        *   ... (other dynamic external ident columns, where `column_name` matches an `external_ident_type.code`)
        *   `legal_unit_id` (purpose: `pk_id`, type: `INTEGER`) - *Resolved internal ID of the unit identified.*
        *   `establishment_id` (purpose: `pk_id`, type: `INTEGER`) - *Resolved internal ID of the unit identified.*
        *   `operation` (purpose: `internal`, type: `public.import_row_operation_type`) - *Determined operation (insert/replace/update) based on identifier lookups.*
        *   `action` (purpose: `internal`, type: `public.import_row_action_type`) - *Determined final action based on operation and job strategy.*
    *   **`enterprise_link_for_legal_unit` step:**
        *   `enterprise_id` (purpose: `internal`, type: `INTEGER`)
        *   `primary_for_enterprise` (purpose: `internal`, type: `BOOLEAN`) -- Renamed from is_primary for consistency
    *   **`valid_time_from_source` step:**
        *   `valid_from` (purpose: `source_input`, type: `TEXT`)
        *   `valid_to` (purpose: `source_input`, type: `TEXT`)
        *   `derived_valid_from` (purpose: `internal`, type: `DATE`)
        *   `derived_valid_to` (purpose: `internal`, type: `DATE`)
    *   **`legal_unit` step:**
        *   `name` (purpose: `source_input`, type: `TEXT`)
        *   `birth_date` (purpose: `source_input`, type: `TEXT`)
        *   `death_date` (purpose: `source_input`, type: `TEXT`) -- Added
        *   `sector_code` (purpose: `source_input`, type: `TEXT`)
        *   `unit_size_code` (purpose: `source_input`, type: `TEXT`) -- Added
        *   `status_code` (purpose: `source_input`, type: `TEXT`)
        *   `legal_form_code` (purpose: `source_input`, type: `TEXT`)
        *   `data_source_code` (purpose: `source_input`, type: `TEXT`)
        *   `legal_unit_id` (purpose: `pk_id`, type: `INTEGER`) - *This step performs the final insert/update.*
        *   `sector_id` (purpose: `internal`, type: `INTEGER`)
        *   `unit_size_id` (purpose: `internal`, type: `INTEGER`) -- Added
        *   `status_id` (purpose: `internal`, type: `INTEGER`)
        *   `legal_form_id` (purpose: `internal`, type: `INTEGER`)
        *   `data_source_id` (purpose: `internal`, type: `INTEGER`)
        *   `typed_birth_date` (purpose: `internal`, type: `DATE`)
        *   `typed_death_date` (purpose: `internal`, type: `DATE`) -- Added
        *   `enterprise_id` (purpose: `internal`, type: `INTEGER`) -- Populated by enterprise_link_for_legal_unit step
        *   `primary_for_enterprise` (purpose: `internal`, type: `BOOLEAN`) -- Populated by enterprise_link_for_legal_unit step
    *   **`physical_location` step:**
        *   `physical_address_part1` (purpose: `source_input`, type: `TEXT`)
        *   `physical_postcode` (purpose: `source_input`, type: `TEXT`)
        *   `physical_region_code` (purpose: `source_input`, type: `TEXT`)
        *   ... (other physical location source/internal/pk_id columns)
        *   `physical_location_id` (purpose: `pk_id`, type: `INTEGER`)
    *   **`postal_location` step:**
        *   `postal_address_part1` (purpose: `source_input`, type: `TEXT`)
        *   ... (other postal location source/internal/pk_id columns)
        *   `postal_location_id` (purpose: `pk_id`, type: `INTEGER`)
    *   **`primary_activity` step:**
        *   `primary_activity_category_code` (purpose: `source_input`, type: `TEXT`)
        *   `primary_activity_category_id` (purpose: `internal`, type: `INTEGER`)
        *   `primary_activity_id` (purpose: `pk_id`, type: `INTEGER`)
    *   **`secondary_activity` step:**
        *   `secondary_activity_category_code` (purpose: `source_input`, type: `TEXT`)
        *   `secondary_activity_category_id` (purpose: `internal`, type: `INTEGER`)
        *   `secondary_activity_id` (purpose: `pk_id`, type: `INTEGER`)
    *   **`contact` step:**
        *   `web_address` (purpose: `source_input`, type: `TEXT`)
        *   ... (other contact source/pk_id columns)
        *   `contact_id` (purpose: `pk_id`, type: `INTEGER`)
    *   **`statistical_variables` step:**
        *   `employees` (purpose: `source_input`, type: `TEXT`) - *Dynamically generated, assumes 'employees' is a stat_definition.code*
        *   ... (other dynamic stat source/pk_id columns)
        *   `stat_for_unit_employees_id` (purpose: `pk_id`, type: `INTEGER`) - *Dynamically generated*
    *   **`tags` step:**
        *   `tag_path` (purpose: `source_input`, type: `TEXT`)
        *   `tag_id` (purpose: `internal`, type: `INTEGER`)
        *   `tag_for_unit_id` (purpose: `pk_id`, type: `INTEGER`)
    *   **`metadata` columns (implicitly added):**
        *   `state` (purpose: `metadata`, type: `public.import_data_state`)
        *   `error` (purpose: `metadata`, type: `JSONB`)
        *   `last_completed_priority` (purpose: `metadata`, type: `INT`)
    *   **And the `row_id` column (implicitly added):**
        *   `row_id` (e.g., `SERIAL PRIMARY KEY` or `BIGSERIAL PRIMARY KEY`)

3.  **Implement Procedures**: Write the PL/pgSQL functions for each step (e.g., `admin.analyse_edit_info`, `admin.analyse_external_idents`, `admin.analyse_enterprise_link_for_legal_unit`, `admin.process_legal_unit`, etc.). These functions must:
    *   Accept `(p_job_id INT, p_batch_row_ids INTEGER[])` (or appropriate array type for `row_id`).
    *   Read `definition_snapshot` from `import_job` if needed.
    *   Determine the job-specific `_data` table name.
    *   Read from/write to the `_data` table using dynamic SQL and `p_batch_row_ids` (e.g., `WHERE row_id = ANY(p_batch_row_ids)`).
    *   Perform logic (lookups, validation, casting for analysis; final DML using audit info and `action` from `_data` for processing).
    *   Correctly update `last_completed_priority`, `state`, `action` (if an error occurs during analysis), and `error`/`invalid_codes` columns in `_data`, following the key management and additive principles.
    *   **Error Handling Rule for Analysis Procedures**: If an `analyse_procedure` detects an error making the row unprocessable, it *must* set `state = 'error'`, `action = 'skip'`, and store details in the `error` JSONB column (merging with existing errors). `last_completed_priority` should be advanced to the current step's priority. Soft errors are added to `invalid_codes` without setting `state='error'` or `action='skip'`.
    *   Handle batch-wide errors (e.g., constraint violation during a batch DML in a `process_procedure`) by marking all rows identified by `p_batch_row_ids` as error (and action='skip') in the `_data` table and potentially failing the job.
4.  **Create Definition (`import_definition`)**:
    ```sql
    INSERT INTO public.import_definition (slug, name, note, strategy, valid)
    VALUES ('legal_unit_explicit_dates', 'Legal Unit - Explicit Dates', 'Imports legal units with explicit dates', 'insert_or_replace', false); -- Start as invalid
    ```

5.  **Link Steps (`import_definition_step`)**:
    ```sql
    INSERT INTO public.import_definition_step (definition_id, step_id)
    SELECT d.id, s.id
    FROM public.import_definition d
    JOIN public.import_step s ON s.code IN ( -- Use code here
        'external_idents', 'enterprise_link_for_legal_unit', 'valid_time_from_source', 'legal_unit',
        'physical_location', 'postal_location', 'primary_activity', 'secondary_activity',
        'contact', 'statistical_variables', 'tags', 'edit_info', 'metadata'
    )
    WHERE d.slug = 'legal_unit_explicit_dates';
    ```

6.  **Define Source Columns (`import_source_column`)**:
    ```sql
    INSERT INTO public.import_source_column (definition_id, column_name, priority)
    SELECT d.id, v.col, v.pri
    FROM public.import_definition d
    CROSS JOIN (VALUES
        ('tax_ident', 1), ('valid_from', 2), ('valid_to', 3), ('name', 4),
        ('birth_date', 5), ('sector_code', 6), ('status_code', 7), ('legal_form_code', 8),
        ('data_source_code', 9), ('physical_address_part1', 10), ('physical_postcode', 11),
        ('physical_region_code', 12), ('primary_activity_category_code', 13)
        -- Add other source columns as needed...
    ) AS v(col, pri)
    WHERE d.slug = 'legal_unit_explicit_dates';
    ```

7.  **Define Mappings (`import_mapping`)**:
    ```sql
    INSERT INTO public.import_mapping (definition_id, source_column_id, target_data_column_id)
    SELECT
        d.id,
        sc.id,
        dc.id
    FROM public.import_definition d
    JOIN public.import_source_column sc ON sc.definition_id = d.id
    JOIN public.import_definition_step ds ON ds.definition_id = d.id
    JOIN public.import_data_column dc ON dc.step_id = ds.step_id AND dc.column_name = sc.column_name AND dc.purpose = 'source_input'
    WHERE d.slug = 'legal_unit_explicit_dates';
    -- Add mappings for fixed values/expressions if needed, e.g.:
    -- INSERT INTO public.import_mapping (definition_id, source_value, target_data_column_id) ...
    ```

8.  **Set Valid**:
    ```sql
    UPDATE public.import_definition
    SET valid = true, validation_error = NULL
    WHERE slug = 'legal_unit_explicit_dates';
    ```
