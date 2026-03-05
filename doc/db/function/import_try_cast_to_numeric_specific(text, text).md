```sql
CREATE OR REPLACE FUNCTION import.try_cast_to_numeric_specific(p_text_value text, p_target_type text, OUT p_value numeric, OUT p_error_message text)
 RETURNS record
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
    v_sql TEXT;
BEGIN
    p_value := NULL;
    p_error_message := NULL;

    IF p_text_value IS NULL OR p_text_value = '' THEN
        RETURN;
    END IF;

    BEGIN
        v_sql := format($$SELECT %1$L::%2$s$$, p_text_value /* %1$L */, p_target_type /* %2$s */);
        RAISE DEBUG 'try_cast_to_numeric_specific: Executing cast: %', v_sql;
        EXECUTE v_sql INTO p_value;
    EXCEPTION
        WHEN numeric_value_out_of_range THEN -- SQLSTATE 22003
            p_error_message := 'Value ''' || p_text_value || ''' is out of range for type ' || p_target_type || '. SQLSTATE: ' || SQLSTATE;
            RAISE DEBUG '%', p_error_message;
        WHEN invalid_text_representation THEN -- SQLSTATE 22P02
            p_error_message := 'Value ''' || p_text_value || ''' is not a valid numeric representation for type ' || p_target_type || '. SQLSTATE: ' || SQLSTATE;
            RAISE DEBUG '%', p_error_message;
        WHEN others THEN -- Catch any other potential errors during cast
            p_error_message := 'Unexpected error casting value ''' || p_text_value || ''' to type ' || p_target_type || '. SQLSTATE: ' || SQLSTATE || ', SQLERRM: ' || SQLERRM;
            RAISE DEBUG '%', p_error_message;
    END;
END;
$function$
```
