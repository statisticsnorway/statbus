```sql
CREATE OR REPLACE FUNCTION admin.safe_cast_to_numeric(p_text_numeric text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
    IF p_text_numeric IS NULL OR p_text_numeric = '' THEN
        RETURN NULL;
    END IF;
    RETURN p_text_numeric::NUMERIC;
EXCEPTION WHEN others THEN
    RAISE WARNING 'Invalid numeric format: "%". Returning NULL.', p_text_numeric;
    RETURN NULL;
END;
$function$
```
