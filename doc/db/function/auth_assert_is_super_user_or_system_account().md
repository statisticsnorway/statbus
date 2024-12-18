```sql
CREATE OR REPLACE FUNCTION auth.assert_is_super_user_or_system_account()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NOT (auth.check_is_system_account() OR auth.check_is_super_user()) THEN
    RAISE EXCEPTION 'Only super users or system accounts can perform this action';
  END IF;
END;
$function$
```
