```sql
CREATE OR REPLACE FUNCTION admin.import_job_notify()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM pg_notify('import_job', json_build_object('verb', TG_OP, 'id', OLD.id)::text);
        RETURN OLD;
    ELSE
        PERFORM pg_notify('import_job', json_build_object('verb', TG_OP, 'id', NEW.id)::text);
        RETURN NEW;
    END IF;
END;
$function$
```
