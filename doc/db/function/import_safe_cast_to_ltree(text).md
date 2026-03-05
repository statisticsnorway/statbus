```sql
CREATE OR REPLACE FUNCTION import.safe_cast_to_ltree(p_text_ltree text, OUT p_value ltree, OUT p_error_message text)
 RETURNS record
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
    p_value := NULL;
    p_error_message := NULL;

    IF p_text_ltree IS NULL OR p_text_ltree = '' THEN
        RETURN; -- p_value and p_error_message remain NULL, indicating successful cast of empty/null to NULL
    END IF;

    BEGIN
        p_value := p_text_ltree::public.LTREE;
    EXCEPTION
        WHEN invalid_text_representation THEN
            p_error_message := 'Invalid ltree format (invalid_text_representation): ''' || p_text_ltree || '''. SQLSTATE: ' || SQLSTATE;
            RAISE DEBUG '%', p_error_message;
        WHEN OTHERS THEN
            p_error_message := 'Failed to cast ''' || p_text_ltree || ''' to ltree. SQLSTATE: ' || SQLSTATE || ', SQLERRM: ' || SQLERRM;
            RAISE DEBUG '%', p_error_message;
    END;
END;
$function$
```
