```sql
CREATE OR REPLACE FUNCTION auth.has_statbus_role(user_uuid uuid, type statbus_role_type)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
AS $function$
  SELECT EXISTS (
    SELECT su.id
    FROM public.statbus_user AS su
    JOIN public.statbus_role AS sr
      ON su.role_id = sr.id
    WHERE ((su.uuid = $1) AND (sr.type = $2))
  );
$function$
```
