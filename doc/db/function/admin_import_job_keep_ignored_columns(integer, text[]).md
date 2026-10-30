```sql
CREATE OR REPLACE FUNCTION admin.import_job_keep_ignored_columns(p_job_id integer, p_column_names text[])
 RETURNS text[]
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'admin', 'pg_temp'
AS $function$
DECLARE
    v_job public.import_job;
    v_added text[] := ARRAY[]::text[];
    v_col text;
    v_role text;
BEGIN
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Import job % not found', p_job_id;
    END IF;
    -- The caller must be allowed to change this job: the job owner or an admin.
    -- Inside SECURITY DEFINER current_user is the owner, so the caller's role
    -- is read from the role setting (SET ROLE by PostgREST or test.set_user_from_email);
    -- 'none' means no SET ROLE, i.e. a direct superuser session such as a migration.
    v_role := current_setting('role', true);
    IF NOT (
        (v_role = 'none' AND (SELECT rolsuper FROM pg_roles WHERE rolname = session_user))
        OR (v_role <> 'none' AND pg_has_role(v_role::name, 'admin_user', 'MEMBER'))
        OR v_job.user_id = (SELECT u.id FROM auth.user AS u WHERE u.email = v_role)
    ) THEN
        RAISE EXCEPTION 'Not allowed to change import job %', p_job_id USING ERRCODE = 'insufficient_privilege';
    END IF;

    FOR v_col IN
        SELECT DISTINCT trim(c) FROM unnest(p_column_names) AS c
        WHERE trim(c) <> ''
          AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_job.definition_snapshot->'import_source_column_list') AS sc
                          WHERE sc->>'column_name' = trim(c))
          AND NOT EXISTS (SELECT 1 FROM information_schema.columns
                          WHERE table_schema = 'public' AND table_name = v_job.upload_table_name AND column_name = trim(c))
        ORDER BY 1
    LOOP
        EXECUTE format('ALTER TABLE public.%I ADD COLUMN %I TEXT', v_job.upload_table_name, v_col);
        EXECUTE format('ALTER TABLE public.%I ADD COLUMN %I TEXT', v_job.data_table_name, v_col || '_raw');
        UPDATE public.import_job
           SET definition_snapshot = jsonb_set(
                   definition_snapshot, '{import_data_column_list}',
                   (definition_snapshot->'import_data_column_list') || jsonb_build_array(jsonb_build_object(
                       'id', NULL, 'step_id', NULL, 'priority', NULL,
                       'column_name', v_col || '_raw', 'column_type', 'TEXT',
                       'purpose', 'ignored', 'is_nullable', true, 'default_value', NULL,
                       'is_uniquely_identifying', false, 'target_pg_type', NULL,
                       'created_at', NULL, 'updated_at', NULL)))
         WHERE id = p_job_id
        RETURNING * INTO v_job;
        v_added := v_added || v_col;
    END LOOP;

    IF cardinality(v_added) > 0 THEN
        NOTIFY pgrst, 'reload schema';
    END IF;
    RETURN v_added;
END;
$function$
```
