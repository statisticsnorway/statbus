-- Down migration 20260507193814: drop the last-admin protection trigger.

BEGIN;

DROP TRIGGER IF EXISTS prevent_removal_of_last_admin_trigger ON auth.user;
DROP FUNCTION IF EXISTS auth.prevent_removal_of_last_admin();

END;
