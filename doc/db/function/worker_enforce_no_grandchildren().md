```sql
CREATE OR REPLACE FUNCTION worker.enforce_no_grandchildren()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_grandparent_id BIGINT;
BEGIN
    IF NEW.parent_id IS NOT NULL THEN
        -- Check if the parent itself has a parent
        SELECT parent_id INTO v_grandparent_id
        FROM worker.tasks
        WHERE id = NEW.parent_id;
        
        IF v_grandparent_id IS NOT NULL THEN
            RAISE EXCEPTION 'Cannot create grandchild tasks. Parent task % already has parent %. Children can only spawn siblings (same parent_id) or uncles (parent_id = NULL).', 
                NEW.parent_id, v_grandparent_id;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$function$
```
