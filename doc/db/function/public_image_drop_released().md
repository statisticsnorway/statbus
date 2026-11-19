```sql
CREATE OR REPLACE FUNCTION public.image_drop_released()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'admin', 'pg_temp'
AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.legal_unit AS lu WHERE lu.image_id = NEW.image_id)
     AND NOT EXISTS (SELECT 1 FROM public.establishment AS es WHERE es.image_id = NEW.image_id) THEN
    DELETE FROM public.image AS i WHERE i.id = NEW.image_id;
  END IF;
  DELETE FROM admin.image_released AS r WHERE r.image_id = NEW.image_id;
  RETURN NULL;
END;
$function$
```
