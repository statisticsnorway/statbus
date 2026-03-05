```sql
CREATE OR REPLACE PROCEDURE worker.notify_is_importing_stop()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
  PERFORM pg_notify('worker_status',
    json_build_object(
      'type', 'is_importing',
      'status', (public.is_importing()->>'active')::boolean
    )::text
  );
END;
$procedure$
```
