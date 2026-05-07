```sql
CREATE OR REPLACE FUNCTION auth.prevent_removal_of_last_admin()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_was_active_admin BOOLEAN;
  v_will_be_active_admin BOOLEAN;
  v_other_active_admin_count INTEGER;
  v_caller_id INTEGER;
BEGIN
  v_caller_id := auth.uid();

  IF TG_OP = 'UPDATE' THEN
    v_was_active_admin     := (OLD.statbus_role = 'admin_user' AND OLD.deleted_at IS NULL);
    v_will_be_active_admin := (NEW.statbus_role = 'admin_user' AND NEW.deleted_at IS NULL);

    IF v_was_active_admin AND NOT v_will_be_active_admin THEN
      IF v_caller_id IS NOT NULL AND v_caller_id = OLD.id THEN
        RAISE EXCEPTION 'Admins cannot remove themselves (%)', OLD.email
          USING HINT = 'Ask another admin to demote or soft-delete this account.';
      END IF;

      SELECT COUNT(*) INTO v_other_active_admin_count
        FROM auth.user u
       WHERE u.statbus_role = 'admin_user'
         AND u.deleted_at IS NULL
         AND u.id <> NEW.id;
      IF v_other_active_admin_count = 0 THEN
        RAISE EXCEPTION 'Cannot remove the last active admin user (%)', OLD.email
          USING HINT = 'Promote another user to admin_user before demoting or soft-deleting this one.';
      END IF;
    END IF;
    RETURN NEW;

  ELSIF TG_OP = 'DELETE' THEN
    v_was_active_admin := (OLD.statbus_role = 'admin_user' AND OLD.deleted_at IS NULL);
    IF v_was_active_admin THEN
      IF v_caller_id IS NOT NULL AND v_caller_id = OLD.id THEN
        RAISE EXCEPTION 'Admins cannot delete themselves (%)', OLD.email
          USING HINT = 'Ask another admin to delete this account.';
      END IF;

      SELECT COUNT(*) INTO v_other_active_admin_count
        FROM auth.user u
       WHERE u.statbus_role = 'admin_user'
         AND u.deleted_at IS NULL
         AND u.id <> OLD.id;
      IF v_other_active_admin_count = 0 THEN
        RAISE EXCEPTION 'Cannot delete the last active admin user (%)', OLD.email
          USING HINT = 'Promote another user to admin_user before deleting this one.';
      END IF;
    END IF;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$function$
```
