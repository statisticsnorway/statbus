```sql
CREATE OR REPLACE FUNCTION admin.reset_import_job_user_context()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_original_claims jsonb;
BEGIN
    -- Get the original claims
    v_original_claims := COALESCE(
        nullif(current_setting('admin.original_claims', true), '')::jsonb,
        '{}'::jsonb
    );

    IF v_original_claims != '{}'::jsonb THEN
        -- Reset to the original claims
        PERFORM auth.use_jwt_claims_in_session(v_original_claims);
        RAISE DEBUG 'Reset user context to original claims';
    ELSE
        -- Clear the user context
        PERFORM auth.reset_session_context();
        RAISE DEBUG 'Cleared user context (no original claims)';
    END IF;
END;
$function$
```
