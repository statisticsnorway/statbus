```sql
CREATE OR REPLACE FUNCTION worker.ensure_collect_changes_for_legal_relationship()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Only schedule collection if any changed row has a PG assigned.
    -- During initial import, LR rows are inserted with derived_power_group_id = NULL,
    -- then process_power_group_link assigns PG IDs (triggering this again).
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        IF NOT EXISTS (SELECT 1 FROM new_rows WHERE derived_power_group_id IS NOT NULL) THEN
            RETURN NULL;
        END IF;
    END IF;

    PERFORM worker.publish_base_change_wakeup();
    RETURN NULL;
END;
$function$
```
