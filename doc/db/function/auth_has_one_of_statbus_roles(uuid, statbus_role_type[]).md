```sql
CREATE OR REPLACE FUNCTION auth.has_one_of_statbus_roles(user_uuid uuid, types statbus_role_type[])
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
AS $function$
  SELECT EXISTS (
    SELECT su.id
    FROM public.statbus_user AS su
    JOIN public.statbus_role AS sr
      ON su.role_id = sr.id
    WHERE ((su.uuid = $1) AND (sr.type = ANY ($2)))
  );
$function$
```
