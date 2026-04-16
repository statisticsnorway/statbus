```sql
CREATE OR REPLACE PROCEDURE public.upgrade_retention_apply(IN p_context text, IN p_installed_id integer DEFAULT NULL::integer, INOUT p_deleted integer DEFAULT 0)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $procedure$
DECLARE
    r record;
BEGIN
    -- Temp table lets us both log and delete from the same plan without
    -- calling the STABLE function twice (it's stable within a statement
    -- boundary, not within a transaction — concurrent INSERT between
    -- plan and delete could otherwise produce divergent sets).
    IF to_regclass('pg_temp._upgrade_retention_plan') IS NOT NULL THEN
        DROP TABLE _upgrade_retention_plan;
    END IF;
    CREATE TEMP TABLE _upgrade_retention_plan ON COMMIT DROP AS
        SELECT * FROM public.upgrade_retention_plan(p_context, p_installed_id);

    FOR r IN SELECT id, action, reason FROM _upgrade_retention_plan LOOP
        RAISE NOTICE 'upgrade_retention: id=% action=% reason=%', r.id, r.action, r.reason;
    END LOOP;

    DELETE FROM public.upgrade
     WHERE id IN (SELECT id FROM _upgrade_retention_plan WHERE action = 'delete');
    GET DIAGNOSTICS p_deleted = ROW_COUNT;
END;
$procedure$
```
