```sql
CREATE OR REPLACE FUNCTION import.safe_cast_to_boolean(p_text_value text, OUT p_value boolean, OUT p_error_message text)
 RETURNS record
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
    p_value := NULL;
    p_error_message := NULL;

    IF p_text_value IS NULL OR p_text_value = '' THEN
        RETURN;
    END IF;

    BEGIN
        p_value := p_text_value::BOOLEAN;
    EXCEPTION
        WHEN invalid_text_representation THEN -- Common for boolean cast errors
            p_error_message := 'Invalid boolean format: ''' || p_text_value || '''. SQLSTATE: ' || SQLSTATE;
            RAISE DEBUG '%', p_error_message;
        WHEN others THEN
            p_error_message := 'Failed to cast ''' || p_text_value || ''' to boolean. SQLSTATE: ' || SQLSTATE || ', SQLERRM: ' || SQLERRM;
            RAISE DEBUG '%', p_error_message;
    END;
END;
$function$
```
