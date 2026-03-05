```sql
CREATE OR REPLACE FUNCTION import.safe_cast_to_numeric(p_text_numeric text, OUT p_value numeric, OUT p_error_message text)
 RETURNS record
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
    p_value := NULL;
    p_error_message := NULL;

    IF p_text_numeric IS NULL OR p_text_numeric = '' THEN
        RETURN;
    END IF;

    BEGIN
        p_value := p_text_numeric::NUMERIC;
    EXCEPTION
        WHEN invalid_text_representation THEN
            p_error_message := 'Invalid numeric format: ''' || p_text_numeric || '''. SQLSTATE: ' || SQLSTATE;
            RAISE DEBUG '%', p_error_message;
        WHEN others THEN
            p_error_message := 'Failed to cast ''' || p_text_numeric || ''' to numeric. SQLSTATE: ' || SQLSTATE || ', SQLERRM: ' || SQLERRM;
            RAISE DEBUG '%', p_error_message;
    END;
END;
$function$
```
