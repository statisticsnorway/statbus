```sql
CREATE OR REPLACE FUNCTION admin.safe_cast_to_ltree(p_text_ltree text)
 RETURNS ltree
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
    IF p_text_ltree IS NULL OR p_text_ltree = '' THEN
        RETURN NULL;
    END IF;
    RETURN p_text_ltree::public.LTREE;
EXCEPTION WHEN invalid_text_representation THEN
    RAISE DEBUG 'Invalid ltree format: "%". Returning NULL.', p_text_ltree;
    RETURN NULL;
END;
$function$
```
