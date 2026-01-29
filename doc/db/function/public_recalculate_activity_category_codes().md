```sql
CREATE OR REPLACE FUNCTION public.recalculate_activity_category_codes()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Touch all activity_category rows for this standard
    -- This triggers lookup_parent_and_derive_code() to recalculate code
    UPDATE public.activity_category
    SET updated_at = statement_timestamp()
    WHERE standard_id = NEW.id;
    RETURN NEW;
END;
$function$
```
