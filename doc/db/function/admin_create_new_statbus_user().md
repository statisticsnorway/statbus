```sql
CREATE OR REPLACE FUNCTION admin.create_new_statbus_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  role_id INTEGER;
BEGIN
  -- Start with a minimal set of rights upon auto creation by trigger.
  SELECT id INTO role_id FROM public.statbus_role WHERE type = 'external_user';
  INSERT INTO public.statbus_user (uuid, role_id) VALUES (new.id, role_id);
  RETURN new;
END;
$function$
```
