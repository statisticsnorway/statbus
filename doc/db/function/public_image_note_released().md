```sql
CREATE OR REPLACE FUNCTION public.image_note_released()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'admin', 'pg_temp'
AS $function$
BEGIN
  INSERT INTO admin.image_released (image_id) VALUES (OLD.image_id);
  RETURN NULL;
END;
$function$
```
