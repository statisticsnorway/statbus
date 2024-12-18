```sql
CREATE OR REPLACE FUNCTION auth.assert_is_super_user()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No authenticated user found';
  END IF;

  IF NOT auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type) THEN
    RAISE EXCEPTION 'Only super users can update user roles';
  END IF;
END;
$function$
```
