```sql
CREATE OR REPLACE FUNCTION auth.has_region_access(user_uuid uuid, region_id integer)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
AS $function$
    SELECT EXISTS(
        SELECT su.id
        FROM public.statbus_user AS su
        INNER JOIN public.region_role AS rr ON rr.role_id = su.role_id
        WHERE su.uuid = $1
          AND rr.region_id  = $2
   )
$function$
```
