```sql
CREATE OR REPLACE FUNCTION admin.is_valid_ltree(p_text_ltree text)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
    v_ltree public.LTREE;
BEGIN
    IF p_text_ltree IS NULL OR p_text_ltree = '' THEN
        RETURN true; -- Or false depending on whether NULL/empty is considered valid input
    END IF;
    v_ltree := p_text_ltree::public.LTREE;
    RETURN true;
EXCEPTION WHEN invalid_text_representation THEN
    RETURN false;
END;
$function$
```
