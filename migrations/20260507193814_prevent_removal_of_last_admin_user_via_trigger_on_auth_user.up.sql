-- Migration 20260507193814: prevent removal of the last active admin user.
--
-- Without an active admin, the system is unrecoverable: every protected RLS
-- policy on auth.user, the public.user view, the *_access tables, and the
-- entire admin-only DML surface becomes inaccessible.
--
-- An "active admin" is a row in auth.user with statbus_role = 'admin_user'
-- AND deleted_at IS NULL. The trigger blocks any UPDATE that takes a row out
-- of that state, and any DELETE of a row currently in that state, when no
-- other active admin would remain.
--
-- Removal paths covered:
--   1. UPDATE … SET statbus_role = '<not admin>' WHERE id = <last admin>  (demote)
--   2. UPDATE … SET deleted_at  = now()           WHERE id = <last admin>  (soft delete)
--   3. DELETE … WHERE id = <last admin>                                    (hard delete)
--
-- Same-transaction swap (promote a regular user to admin first, then demote
-- the old admin) is supported: each statement evaluates the trigger
-- independently, so the new admin is already active by the time the old
-- one is demoted.

BEGIN;

CREATE FUNCTION auth.prevent_removal_of_last_admin()
RETURNS trigger
LANGUAGE plpgsql
AS $prevent_removal_of_last_admin$
DECLARE
  v_was_active_admin BOOLEAN;
  v_will_be_active_admin BOOLEAN;
  v_other_active_admin_count INTEGER;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    v_was_active_admin     := (OLD.statbus_role = 'admin_user' AND OLD.deleted_at IS NULL);
    v_will_be_active_admin := (NEW.statbus_role = 'admin_user' AND NEW.deleted_at IS NULL);
    IF v_was_active_admin AND NOT v_will_be_active_admin THEN
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
$prevent_removal_of_last_admin$;

CREATE TRIGGER prevent_removal_of_last_admin_trigger
  BEFORE UPDATE OR DELETE ON auth.user
  FOR EACH ROW
  EXECUTE FUNCTION auth.prevent_removal_of_last_admin();

END;
