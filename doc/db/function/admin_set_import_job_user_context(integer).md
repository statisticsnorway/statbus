```sql
CREATE OR REPLACE FUNCTION admin.set_import_job_user_context(job_id integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_email text;
    v_original_claims jsonb;
BEGIN
    -- Save the current user context if any
    v_original_claims := COALESCE(
        nullif(current_setting('request.jwt.claims', true), '')::jsonb,
        '{}'::jsonb
    );
    
    -- Store the original claims for reset
    PERFORM set_config('admin.original_claims', v_original_claims::text, true);

    -- Get the user email from the job
    SELECT u.email INTO v_email
    FROM public.import_job ij
    JOIN auth.user u ON ij.user_id = u.id
    WHERE ij.id = job_id;

    IF v_email IS NOT NULL THEN
        -- Set the user context
        PERFORM auth.set_user_context_from_email(v_email);
        RAISE DEBUG 'Set user context to % for import job %', v_email, job_id;
    ELSE
        RAISE DEBUG 'No user found for import job %, using current context', job_id;
    END IF;
END;
$function$
```
