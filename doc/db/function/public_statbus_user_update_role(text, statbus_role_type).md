```sql
CREATE OR REPLACE FUNCTION public.statbus_user_update_role(p_email text, p_role_type statbus_role_type)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    UPDATE public.statbus_user
    SET role_id = (SELECT id FROM public.statbus_role WHERE type = p_role_type)
    WHERE uuid IN (
        SELECT au.id
        FROM auth.users au
        WHERE au.email = p_email
    );
END;
$function$
```
