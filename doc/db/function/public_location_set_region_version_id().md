```sql
CREATE OR REPLACE FUNCTION public.location_set_region_version_id()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.region_version_id := (
    SELECT r.version_id FROM public.region AS r WHERE r.id = NEW.region_id
  );
  RETURN NEW;
END;
$function$
```
