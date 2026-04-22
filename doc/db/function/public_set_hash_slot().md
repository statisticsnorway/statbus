```sql
CREATE OR REPLACE FUNCTION public.set_hash_slot()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.hash_slot := public.hash_slot(NEW.unit_type, NEW.unit_id);
    RETURN NEW;
END;
$function$
```
