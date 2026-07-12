```sql
CREATE OR REPLACE FUNCTION public.upgrade_block_terminal_resurrection()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- The trigger's WHEN clause already gates this to exactly the forbidden
    -- transition (terminal → completed); raise the named-remedy error.
    RAISE EXCEPTION
        'upgrade row % (state=%) cannot be completed: terminal rows are not resurrectable — re-dispatch via ./sb upgrade schedule to run it through the pipeline (it completes honestly only if health passes)',
        OLD.id, OLD.state;
    RETURN NEW;
END;
$function$
```
