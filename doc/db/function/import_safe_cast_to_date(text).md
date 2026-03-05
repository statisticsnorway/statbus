```sql
CREATE OR REPLACE FUNCTION import.safe_cast_to_date(p_text_date text, OUT p_value date, OUT p_error_message text)
 RETURNS record
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
    p_value := NULL;
    p_error_message := NULL;

    IF p_text_date IS NULL OR p_text_date = '' THEN
        RETURN; -- p_value and p_error_message remain NULL
    END IF;

    BEGIN
        p_value := p_text_date::DATE;
    EXCEPTION
        WHEN invalid_datetime_format THEN
            p_error_message := 'Invalid date format: ''' || p_text_date || '''. SQLSTATE: ' || SQLSTATE;
            RAISE DEBUG '%', p_error_message;
        WHEN others THEN
            p_error_message := 'Failed to cast ''' || p_text_date || ''' to date. SQLSTATE: ' || SQLSTATE || ', SQLERRM: ' || SQLERRM;
            RAISE DEBUG '%', p_error_message;
    END;
END;
$function$
```
