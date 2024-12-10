```sql
CREATE OR REPLACE FUNCTION auth.has_activity_category_access(user_uuid uuid, activity_category_id integer)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
AS $function$
    SELECT EXISTS(
        SELECT su.id
        FROM public.statbus_user AS su
        INNER JOIN public.activity_category_role AS acr ON acr.role_id = su.role_id
        WHERE su.uuid = $1
          AND acr.activity_category_id  = $2
   )
$function$
```
