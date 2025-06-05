```sql
CREATE OR REPLACE FUNCTION admin.notify_schema_change()
 RETURNS event_trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  PERFORM pg_notify('schema_change', 'Schema structure has been modified');
END;
$function$
```
