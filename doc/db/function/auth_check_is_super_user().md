```sql
CREATE OR REPLACE FUNCTION auth.check_is_super_user()
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  RETURN (auth.uid() IS NOT NULL)
    AND auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type);
END;
$function$
```
