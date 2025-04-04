```sql
CREATE OR REPLACE FUNCTION admin.trigger_update_user_with_role()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE DEBUG 'Trigger executing for user: %, session user: %, current user: %',
                auth.uid(), session_user, current_user;
    RAISE DEBUG 'Attempting to update role from % to % for email %',
                OLD.statbus_role, NEW.statbus_role, NEW.email;
    RAISE DEBUG 'Checking system account: %', auth.check_is_system_account();
    RAISE DEBUG 'Checking admin user: %', auth.check_is_admin_user();

    PERFORM auth.assert_is_admin_user_or_system_account();

    PERFORM public.user_update_role(OLD.email, NEW.statbus_role);
    RETURN NEW;
END;
$function$
```
