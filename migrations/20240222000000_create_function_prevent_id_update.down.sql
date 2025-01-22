BEGIN;

-- Drop all prevent_id_update triggers from public tables
DO $$
DECLARE
    trigger_record record;
BEGIN
    FOR trigger_record IN
        SELECT tgname, relname
        FROM pg_trigger t
        JOIN pg_class c ON t.tgrelid = c.oid
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'public'
        AND tgname LIKE 'trigger_prevent_%_id_update'
    LOOP
        RAISE NOTICE 'Dropping trigger % on table public.%', 
                    trigger_record.tgname, 
                    trigger_record.relname;
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I',
                      trigger_record.tgname,
                      trigger_record.relname);
    END LOOP;
END $$;

-- Drop the functions after removing all triggers that depend on them
DROP FUNCTION admin.prevent_id_update_on_public_tables();
DROP FUNCTION admin.prevent_id_update();

END;
