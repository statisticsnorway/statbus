```sql
CREATE OR REPLACE PROCEDURE worker.teardown()
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
        -- Drop new triggers
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', 'a_' || v_table_name || '_log_insert', v_table_name);
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', 'a_' || v_table_name || '_log_update', v_table_name);
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', 'a_' || v_table_name || '_log_delete', v_table_name);
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', 'b_' || v_table_name || '_ensure_collect', v_table_name);
        -- Also drop legacy triggers if they still exist
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', v_table_name || '_deletes_trigger', v_table_name);
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', v_table_name || '_statement_changes_trigger', v_table_name);
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', v_table_name || '_row_changes_trigger', v_table_name);
    END LOOP;
END;
$procedure$
```
