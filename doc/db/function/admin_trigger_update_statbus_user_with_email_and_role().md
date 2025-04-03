```sql
CREATE OR REPLACE FUNCTION admin.trigger_update_user_with_role()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE DEBUG 'Trigger executing for user: %, session user: %, current user: %',
                auth.uid(), session_user, current_user;
    RAISE DEBUG 'Attempting to update role from % to % for email %',
                OLD.role_type, NEW.role_type, NEW.email;
    RAISE DEBUG 'Checking system account: %', auth.check_is_system_account();
    RAISE DEBUG 'Checking super user: %', auth.check_is_super_user();

    PERFORM auth.assert_is_super_user_or_system_account();

    PERFORM public.statbus_user_update_role(OLD.email, NEW.role_type);
    RETURN NEW;
END;
$function$
```
