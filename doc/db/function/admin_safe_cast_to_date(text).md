```sql
CREATE OR REPLACE FUNCTION admin.safe_cast_to_date(p_text_date text)
 RETURNS date
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
    IF p_text_date IS NULL OR p_text_date = '' THEN
        RETURN NULL;
    END IF;
    -- Add more robust date parsing/validation if needed
    RETURN p_text_date::DATE;
EXCEPTION WHEN others THEN
    RAISE WARNING 'Invalid date format: "%". Returning NULL.', p_text_date;
    RETURN NULL;
END;
$function$
```
