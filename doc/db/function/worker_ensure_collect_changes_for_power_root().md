```sql
CREATE OR REPLACE FUNCTION worker.ensure_collect_changes_for_power_root()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        IF NOT EXISTS (SELECT 1 FROM new_rows WHERE custom_root_legal_unit_id IS NOT NULL) THEN
            RETURN NULL;
        END IF;
    END IF;

    PERFORM worker.publish_base_change_wakeup();
    RETURN NULL;
END;
$function$
```
