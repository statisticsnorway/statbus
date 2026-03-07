```sql
CREATE OR REPLACE PROCEDURE worker.setup_base_change_triggers()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_table_name TEXT;
BEGIN
    FOREACH v_table_name IN ARRAY ARRAY[
        'enterprise', 'external_ident', 'legal_unit', 'establishment',
        'activity', 'location', 'contact', 'stat_for_unit'
    ]
    LOOP
        -- Statement triggers with REFERENCING for ID capture
        -- Named a_* to fire before b_* (PG fires alphabetically)
        EXECUTE format(
            'CREATE TRIGGER %I
            AFTER INSERT ON public.%I
            REFERENCING NEW TABLE AS new_rows
            FOR EACH STATEMENT
            EXECUTE FUNCTION worker.log_base_change()',
            'a_' || v_table_name || '_log_insert',
            v_table_name
        );

        EXECUTE format(
            'CREATE TRIGGER %I
            AFTER UPDATE ON public.%I
            REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
            FOR EACH STATEMENT
            EXECUTE FUNCTION worker.log_base_change()',
            'a_' || v_table_name || '_log_update',
            v_table_name
        );

        EXECUTE format(
            'CREATE TRIGGER %I
            AFTER DELETE ON public.%I
            REFERENCING OLD TABLE AS old_rows
            FOR EACH STATEMENT
            EXECUTE FUNCTION worker.log_base_change()',
            'a_' || v_table_name || '_log_delete',
            v_table_name
        );

        -- Statement trigger for task ensurance (fires after a_* triggers)
        EXECUTE format(
            'CREATE TRIGGER %I
            AFTER INSERT OR UPDATE OR DELETE ON public.%I
            FOR EACH STATEMENT
            EXECUTE FUNCTION worker.ensure_collect_changes()',
            'b_' || v_table_name || '_ensure_collect',
            v_table_name
        );
    END LOOP;
END;
$procedure$
```
