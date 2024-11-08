```sql
CREATE OR REPLACE PROCEDURE lifecycle_callbacks.del(IN label_param text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    higher_priority_label TEXT;
    rows_deleted INT;
BEGIN
    -- CTE to get the priority of the callback to be deleted
    WITH target_callback AS (
        SELECT priority
        FROM lifecycle_callbacks.registered_callback
        WHERE label = label_param
    )
    -- Check for a higher priority callback
    SELECT label
    INTO higher_priority_label
    FROM lifecycle_callbacks.registered_callback
    WHERE priority > (SELECT priority FROM target_callback)
    ORDER BY priority ASC
    LIMIT 1;

    -- If a higher priority callback exists, raise an error
    IF higher_priority_label IS NOT NULL THEN
        RAISE EXCEPTION 'Cannot delete % because a higher priority callback % still exists.', label_param, higher_priority_label;
    END IF;

    -- Proceed with deletion if no higher priority callback exists
    DELETE FROM lifecycle_callbacks.registered_callback
    WHERE label = label_param;

    -- Get the number of rows affected by the DELETE operation
    GET DIAGNOSTICS rows_deleted = ROW_COUNT;

    -- Provide feedback on the deletion
    IF rows_deleted > 0 THEN
        RAISE NOTICE 'Callback % has been successfully deleted.', label_param;
    ELSE
        RAISE NOTICE 'Callback % was not found and thus not deleted.', label_param;
    END IF;
END;
$procedure$
```
