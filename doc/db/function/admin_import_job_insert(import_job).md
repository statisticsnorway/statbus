```sql
CREATE OR REPLACE FUNCTION admin.import_job_insert(job import_job)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    target_columns TEXT;
    batch_size INTEGER := 1000; -- Process 1000 rows at a time
    pending_count INTEGER;
    imported_count INTEGER := 0;
    error_count INTEGER := 0;
    batch_insert_stmt TEXT;
    batch_count INTEGER;
    uniquely_identifying_columns TEXT;
    should_continue BOOLEAN := TRUE;
    max_batches_per_transaction INTEGER := 1; -- Only process one batch per transaction
    current_batch INTEGER := 0;
BEGIN
    -- This function will copy data from the data table to the target table
    RAISE DEBUG 'IMPORT_JOB_INSERT: Starting import from % to %.%',
                 job.data_table_name, job.target_schema_name, job.target_table_name;

    -- Get target columns from the snapshot table (excluding state)
    EXECUTE format(
        'SELECT string_agg(quote_ident(target_column), '','')
        FROM public.%I
        WHERE target_column IS NOT NULL',
        job.import_information_snapshot_table_name
    ) INTO target_columns;

    RAISE DEBUG 'IMPORT_JOB_INSERT: Target columns: %', target_columns;

    -- Get uniquely identifying columns for the WHERE clause in batch processing
    EXECUTE format(
        'SELECT string_agg(quote_ident(target_column), '','')
        FROM public.%I
        WHERE uniquely_identifying = TRUE
          AND target_column IS NOT NULL',
        job.import_information_snapshot_table_name
    ) INTO uniquely_identifying_columns;

    RAISE DEBUG 'IMPORT_JOB_INSERT: Uniquely identifying columns: %', uniquely_identifying_columns;

    -- Count rows in different states
    DECLARE
        pending_count INTEGER;
        importing_count INTEGER;
        error_count INTEGER;
    BEGIN
        -- Get counts for all states in a single query using window functions
        EXECUTE format('
            WITH counts AS (
                SELECT
                    COUNT(*) FILTER (WHERE state = ''pending'') AS pending,
                    COUNT(*) FILTER (WHERE state = ''importing'') AS importing,
                    COUNT(*) FILTER (WHERE state = ''imported'') AS imported,
                    COUNT(*) FILTER (WHERE state = ''error'') AS error
                FROM public.%I
            )
            SELECT pending, importing, imported, error FROM counts',
            job.data_table_name
        ) INTO pending_count, importing_count, imported_count, error_count;

        RAISE DEBUG 'IMPORT_JOB_INSERT: Initial state - Pending: %, Processing: %, Imported: %, Error: %',
                    pending_count, importing_count, imported_count, error_count;

        -- If there are rows stuck in processing state, mark them as pending to retry
        IF importing_count > 0 THEN
            EXECUTE format('UPDATE public.%I SET state = ''pending'' WHERE state = ''importing''',
                          job.data_table_name);
            RAISE DEBUG 'IMPORT_JOB_INSERT: Reset % rows from processing to pending state', importing_count;
            pending_count := pending_count + importing_count;
        END IF;

        -- Update job with already imported rows (for resumability)
        -- Note: total_rows is set once when state changes to upload_completed and never changes
        -- import_completed_pct is now a generated column
        -- last_progress_update is set by the trigger
        UPDATE public.import_job
        SET imported_rows = imported_count
        WHERE id = job.id
        RETURNING * INTO job;
    END;

    -- Process in batches until all pending rows are processed
    DECLARE
        remaining_count INTEGER;
    BEGIN
        -- Initialize remaining count from pending rows
        EXECUTE format('SELECT COUNT(*) FROM public.%I WHERE state = ''pending''',
                      job.data_table_name) INTO remaining_count;

        RAISE DEBUG 'IMPORT_JOB_INSERT: Starting batch processing with % pending rows', remaining_count;

        -- Process until no pending rows remain or we've reached our batch limit
        WHILE remaining_count > 0 AND current_batch < max_batches_per_transaction LOOP
            -- Increment batch counter
            current_batch := current_batch + 1;
        BEGIN
            RAISE DEBUG 'IMPORT_JOB_INSERT: Starting new batch, remaining rows: %', remaining_count;

            -- Mark batch as processing (with row locking)
            DECLARE
                mark_batch_sql TEXT;
                marked_count INTEGER;
            BEGIN
                mark_batch_sql := format($format$
                    UPDATE public.%I
                    SET state = 'importing'
                    WHERE state = 'pending'
                    AND ctid IN (
                        SELECT ctid
                        FROM public.%I
                        WHERE state = 'pending'
                        ORDER BY %s
                        LIMIT %s
                    );
                $format$,
                job.data_table_name,
                job.data_table_name,
                COALESCE(uniquely_identifying_columns, 'ctid'),
                batch_size);

                RAISE DEBUG 'IMPORT_JOB_INSERT: Marking batch SQL: %', mark_batch_sql;
                EXECUTE mark_batch_sql;

                GET DIAGNOSTICS marked_count = ROW_COUNT;
                RAISE DEBUG 'IMPORT_JOB_INSERT: Marked % rows as processing', marked_count;

                -- If no rows were marked as processing, exit the loop
                IF marked_count = 0 THEN
                    RAISE DEBUG 'IMPORT_JOB_INSERT: No rows marked as processing, exiting loop';
                    EXIT;
                ELSE
                    batch_count := marked_count;
                END IF;
            END;

            -- Create batch insert statement for rows marked as processing
            batch_insert_stmt := format($format$
                WITH batch AS (
                    SELECT %s, ctid AS source_ctid
                    FROM public.%I
                    WHERE state = 'importing'
                    ORDER BY %s
                    FOR UPDATE
                ),
                inserted AS (
                    INSERT INTO %I.%I (%s)
                    SELECT %s FROM batch
                    RETURNING 1 AS inserted_row
                )
                SELECT COUNT(*) FROM inserted;
            $format$,
            target_columns,
            job.data_table_name,
            COALESCE(uniquely_identifying_columns, 'ctid'),
            job.target_schema_name,
            job.target_table_name,
            target_columns,
            target_columns
            );

            RAISE DEBUG 'IMPORT_JOB_INSERT: Batch insert SQL: %', batch_insert_stmt;

            -- Execute batch insert
            -- Execute and capture actual inserted count
            DECLARE
                reported_inserted INTEGER;
                is_view BOOLEAN;
                v_error TEXT;
            BEGIN
                -- Execute with error handling
                BEGIN
                    EXECUTE batch_insert_stmt INTO reported_inserted;
                EXCEPTION WHEN OTHERS THEN
                    -- Capture the specific error for this statement with enhanced diagnostics
                    DECLARE
                        v_detail TEXT;
                        v_context TEXT;
                        v_hint TEXT;
                        v_state TEXT;
                        v_message TEXT;
                        v_column_name TEXT;
                        v_constraint_name TEXT;
                        v_table_name TEXT;
                        v_schema_name TEXT;
                    BEGIN
                        GET STACKED DIAGNOSTICS
                            v_state = RETURNED_SQLSTATE,
                            v_message = MESSAGE_TEXT,
                            v_detail = PG_EXCEPTION_DETAIL,
                            v_hint = PG_EXCEPTION_HINT,
                            v_context = PG_EXCEPTION_CONTEXT,
                            v_column_name = COLUMN_NAME,
                            v_constraint_name = CONSTRAINT_NAME,
                            v_table_name = TABLE_NAME,
                            v_schema_name = SCHEMA_NAME;

                        RAISE DEBUG 'IMPORT_JOB_INSERT: Error executing batch insert: %', v_message;
                        RAISE DEBUG 'IMPORT_JOB_INSERT: Error details: %, Hint: %', v_detail, v_hint;
                        RAISE DEBUG 'IMPORT_JOB_INSERT: Error state: %, Context: %', v_state, v_context;
                        RAISE DEBUG 'IMPORT_JOB_INSERT: Related objects - Table: %.%, Column: %, Constraint: %',
                                    v_schema_name, v_table_name, v_column_name, v_constraint_name;

                        -- Format the error message while all variables are in scope
                        v_error := format('Import failed: %s. Details: %s. Hint: %s. Related to: %s.%s%s%s',
                                      v_message,
                                      v_detail,
                                      v_hint,
                                      COALESCE(v_schema_name, ''),
                                      COALESCE(v_table_name, ''),
                                      CASE WHEN v_column_name IS NOT NULL THEN '.' || v_column_name ELSE '' END,
                                      CASE WHEN v_constraint_name IS NOT NULL THEN ' (constraint: ' || v_constraint_name || ')' ELSE '' END);
                    END;

                    -- Mark rows with error - this won't be rolled back since it's outside the exception block
                    EXECUTE format($format$
                        UPDATE public.%I
                        SET state = 'error'
                        WHERE state = 'importing';
                    $format$, job.data_table_name);

                    -- Count error rows
                    EXECUTE format('SELECT COUNT(*) FROM public.%I WHERE state = ''error''',
                                  job.data_table_name) INTO error_count;

                    -- Log the error
                    RAISE WARNING 'Error importing batch: %. % rows marked as error.', SQLERRM, error_count;

                    -- Get the actual count of successfully imported rows
                    DECLARE
                        actual_imported_count INTEGER;
                    BEGIN
                        EXECUTE format('SELECT COUNT(*) FROM public.%I WHERE state = ''imported''',
                                      job.data_table_name) INTO actual_imported_count;

                        -- Update the job with the error, mark as finished, and set correct imported_rows count
                        UPDATE public.import_job
                        SET state = 'finished',
                            error = v_error,
                            imported_rows = actual_imported_count
                        WHERE id = job.id;

                        RAISE DEBUG 'IMPORT_JOB_INSERT: Import job marked as finished due to error with % imported rows', actual_imported_count;
                    END;

                    -- Prevent further processing, since the job is already marked as finished.
                    RETURN;
                END;

                -- If rows were inserted successfully, use that count
                IF reported_inserted > 0 THEN
                    RAISE DEBUG 'IMPORT_JOB_INSERT: Inserted % rows in this batch (reported by INSERT)', reported_inserted;
                    batch_count := reported_inserted;
                ELSE
                    -- Check if the target is a view
                    EXECUTE format(
                        'SELECT EXISTS (
                            SELECT 1 FROM information_schema.views
                            WHERE table_schema = %L AND table_name = %L
                        )',
                        job.target_schema_name, job.target_table_name
                    ) INTO is_view;

                    IF is_view THEN
                        -- For views, we can't rely on the INSERT returning count
                        -- so we'll preserve the batch_count set in the marking phase.
                        RAISE DEBUG 'IMPORT_JOB_INSERT: Target is a view, assuming all marked rows were processed successfully';
                    ELSE
                        -- For tables, if nothing was inserted, that's an error
                        RAISE EXCEPTION 'Failed to insert any rows into table %.%', job.target_schema_name, job.target_table_name;
                    END IF;
                END IF;
            END;

            -- Mark processed rows as imported
            DECLARE
                mark_imported_sql TEXT;
                marked_count INTEGER;
            BEGIN
                mark_imported_sql := format($format$
                    UPDATE public.%I
                    SET state = 'imported'
                    WHERE state = 'importing';
                $format$, job.data_table_name);

                RAISE DEBUG 'IMPORT_JOB_INSERT: Marking as imported SQL: %', mark_imported_sql;
                EXECUTE mark_imported_sql;

                GET DIAGNOSTICS marked_count = ROW_COUNT;
                RAISE DEBUG 'IMPORT_JOB_INSERT: Marked % rows as imported', marked_count;

                -- Update the imported_rows count immediately after marking rows as imported
                -- This ensures we don't lose track of progress between batches
                IF marked_count > 0 THEN
                    UPDATE public.import_job
                    SET imported_rows = imported_rows + marked_count
                    WHERE id = job.id;
                    RAISE DEBUG 'IMPORT_JOB_INSERT: Updated imported_rows count by adding % rows', marked_count;
                END IF;
            END;

            -- Update imported count
            imported_count := imported_count + batch_count;

            -- Recalculate remaining count directly from database
            EXECUTE format('SELECT COUNT(*) FROM public.%I WHERE state = ''pending''',
                          job.data_table_name) INTO remaining_count;

            RAISE DEBUG 'IMPORT_JOB_INSERT: Updated counts - imported: %, remaining: %', imported_count, remaining_count;

            -- Update progress in job table
            DECLARE
                current_progress numeric(5,2);
                imported_count INTEGER;
            BEGIN
                -- Get the actual count of imported rows from the data table
                EXECUTE format('SELECT COUNT(*) FROM public.%I WHERE state = ''imported''',
                              job.data_table_name) INTO imported_count;

                UPDATE public.import_job
                SET imported_rows = imported_count
                WHERE id = job.id
                RETURNING import_completed_pct INTO current_progress;

                RAISE DEBUG 'IMPORT_JOB_INSERT: Updated job progress to % complete', current_progress;
            END;

        END;
    END LOOP;

    -- Do a final count to ensure we have the correct numbers
    EXECUTE format('
        WITH counts AS (
            SELECT
                COUNT(*) FILTER (WHERE state = ''pending'') AS pending,
                COUNT(*) FILTER (WHERE state = ''imported'') AS imported,
                COUNT(*) FILTER (WHERE state = ''error'') AS error
            FROM public.%I
        )
        SELECT pending, imported, error FROM counts',
        job.data_table_name
    ) INTO pending_count, imported_count, error_count;

    RAISE DEBUG 'IMPORT_JOB_INSERT: Batches processed. Counts - Pending: %, Imported: %, Errors: %',
                pending_count, imported_count, error_count;

    -- Update job with current counts - ensure we use the actual count from the data table
    -- This is critical for ensuring the final count is accurate
    UPDATE public.import_job
    SET imported_rows = imported_count
    WHERE id = job.id;

    RAISE DEBUG 'IMPORT_JOB_INSERT: Final update of imported_rows to %', imported_count;

    -- Check if there were any errors during processing
    IF error_count > 0 THEN
        -- We've already marked the job as finished with an error in the exception handler
        RAISE DEBUG 'IMPORT_JOB_INSERT: Import failed with % errors', error_count;
    -- If there are still pending rows, we need to continue in the next transaction
    ELSIF pending_count > 0 THEN
        RAISE DEBUG 'IMPORT_JOB_INSERT: Still have % rows to import, will continue in next transaction', pending_count;
    ELSE
        -- No more pending rows and no errors, we're done successfully
        -- Update job state to finished and ensure the imported_rows count is accurate
        EXECUTE format('
            WITH counts AS (
                SELECT COUNT(*) FILTER (WHERE state = ''imported'') AS imported
                FROM public.%I
            )
            UPDATE public.import_job
            SET state = ''finished'',
                imported_rows = (SELECT imported FROM counts)
            WHERE id = %L',
            job.data_table_name,
            job.id
        );

        RAISE DEBUG 'IMPORT_JOB_INSERT: Set state to finished and ensured final imported_rows count is accurate';
        RAISE DEBUG 'IMPORT_JOB_INSERT: Import completed successfully';
    END IF;
END;
END;
$function$
```
