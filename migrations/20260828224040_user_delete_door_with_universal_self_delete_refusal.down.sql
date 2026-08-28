BEGIN;

-- Reverse of STATBUS-309's door. Drops in dependency order: the trigger before
-- the function it calls, then the two exposed functions.
--
-- NOTE ON WHAT THIS DOES NOT UNDO: rows already soft-deleted keep their
-- deleted_at. That is deliberate — deleted_at is pre-existing column state,
-- not something this migration introduced, and public.login has always refused
-- USER_DELETED. Clearing it here would silently REACTIVATE accounts an
-- administrator deliberately removed, which is a far worse outcome than a
-- down-migration leaving true data in place.

DROP TRIGGER IF EXISTS prevent_self_soft_delete_trigger ON auth."user";
DROP FUNCTION IF EXISTS auth.prevent_self_soft_delete();

DROP FUNCTION IF EXISTS public.user_restore(integer);
DROP FUNCTION IF EXISTS public.user_delete(integer);

END;
