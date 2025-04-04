```sql
CREATE OR REPLACE FUNCTION admin.import_job_prepare(job import_job)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    merge_stmt text;
    add_separator BOOLEAN := FALSE;
    info RECORD;
    v_timestamp TIMESTAMPTZ;
    error_message TEXT;
BEGIN
    -- This function will move data from the upload table to the data table
    -- with appropriate transformations based on the import definition
    RAISE DEBUG 'Preparing import job % by moving data from % to %',
                 job.id, job.upload_table_name, job.data_table_name;

    /*
    -- Example of generated merge statement:
    INSERT INTO public.import_job_123_data_table (
      tax_ident, name, legal_form_code, primary_activity_category_code
    ) SELECT
      tax_ident, name, legal_form_code, primary_activity_category_code
    FROM public.import_job_123_upload_table
    ON CONFLICT (tax_ident) DO UPDATE SET
      name = EXCLUDED.name,
      legal_form_code = EXCLUDED.legal_form_code,
      primary_activity_category_code = EXCLUDED.primary_activity_category_code;
    */

    -- Build dynamic INSERT statement with ON CONFLICT handling
    merge_stmt := format('INSERT INTO public.%I (', job.data_table_name);

    -- Add target columns
    add_separator := FALSE;
    FOR info IN
        SELECT * FROM public.import_information AS ii
        WHERE ii.job_id = job.id
          AND target_column IS NOT NULL
    LOOP
        IF NOT add_separator THEN
            add_separator := true;
        ELSE
            merge_stmt := merge_stmt || ', ';
        END IF;

        merge_stmt := merge_stmt || format('%I', info.target_column);
    END LOOP;

    merge_stmt := merge_stmt || format(') SELECT ');

    -- Add source columns, values and expressions
    add_separator := FALSE;
    FOR info IN
        SELECT *
        FROM public.import_information AS ii
        WHERE ii.job_id = job.id
          AND target_column IS NOT NULL
          AND (source_column IS NOT NULL
              OR source_value IS NOT NULL
              OR source_expression IS NOT NULL)
    LOOP
        IF NOT add_separator THEN
            add_separator := true;
        ELSE
            merge_stmt := merge_stmt || ', ';
        END IF;

        CASE
            WHEN info.source_value IS NOT NULL THEN
                merge_stmt := merge_stmt || quote_literal(info.source_value);
            WHEN info.source_expression IS NOT NULL THEN
                merge_stmt := merge_stmt || CASE info.source_expression
                    WHEN 'now' THEN 'statement_timestamp()'
                    WHEN 'default' THEN
                        CASE info.target_column
                            WHEN 'valid_from' THEN quote_literal(job.default_valid_from)
                            WHEN 'valid_to' THEN quote_literal(job.default_valid_to)
                            WHEN 'data_source_code' THEN quote_literal(job.default_data_source_code)
                            ELSE 'NULL'
                        END
                    ELSE 'NULL'
                    END;
            WHEN info.source_column IS NOT NULL THEN
                merge_stmt := merge_stmt || CASE info.target_column
                    WHEN 'valid_from' THEN format('COALESCE(NULLIF(%I,%L), %L)', info.source_column, '', job.default_valid_from)
                    WHEN 'valid_to' THEN format('COALESCE(NULLIF(%I,%L), %L)', info.source_column, '', job.default_valid_to)
                    ELSE format('NULLIF(%I,%L)', info.source_column, '')
                    END;
            ELSE
                RAISE EXCEPTION 'No valid source (column/value/expression) found for job %', job_id;
        END CASE;
    END LOOP;

    merge_stmt := merge_stmt || format(' FROM public.%I ', job.upload_table_name);

    -- Add ON CONFLICT clause using uniquely identifying columns
    merge_stmt := merge_stmt || ' ON CONFLICT (';

    add_separator := FALSE;
    FOR info IN
        SELECT *
        FROM public.import_information AS ii
        WHERE ii.job_id = job.id
          AND uniquely_identifying = TRUE
          AND target_column IS NOT NULL
    LOOP
        IF NOT add_separator THEN
            add_separator := true;
        ELSE
            merge_stmt := merge_stmt || ', ';
        END IF;

        merge_stmt := merge_stmt || format('%I', info.target_column);
    END LOOP;

    merge_stmt := merge_stmt || ') DO UPDATE SET ';

    -- Add update assignments
    add_separator := FALSE;
    FOR info IN
        SELECT *
        FROM public.import_information AS ii
        WHERE ii.job_id = job.id
          AND source_column IS NOT NULL
          AND target_column IS NOT NULL
          AND NOT uniquely_identifying
    LOOP
        IF NOT add_separator THEN
            add_separator := true;
        ELSE
            merge_stmt := merge_stmt || ', ';
        END IF;

        merge_stmt := merge_stmt || format('%I = EXCLUDED.%I',
                                        info.target_column,
                                        info.target_column);
    END LOOP;

    -- Execute the insert
    BEGIN
        RAISE DEBUG 'Executing upsert: %', merge_stmt;
        EXECUTE merge_stmt;

        DECLARE
          data_table_count INT;
        BEGIN
          EXECUTE format('SELECT count(*) FROM public.%I', job.data_table_name) INTO data_table_count;
          RAISE DEBUG 'There are % rows in %', data_table_count, job.data_table_name;
        END;
    EXCEPTION
        WHEN OTHERS THEN
            error_message := SQLERRM;
            RAISE DEBUG 'Error in import_job_prepare: %', error_message;

            -- Update the job with the error
            UPDATE public.import_job
            SET error = format('Error preparing data: %s', error_message)
            WHERE id = job.id;

            RAISE EXCEPTION 'Error preparing data: %', error_message;
    END;
END;
$function$
```
