-- Down Migration 20260831124944: document system_info superuser writes and rls scope
BEGIN;

-- Restores the prior comment verbatim (confirmed via obj_description before this
-- migration existed).
COMMENT ON TABLE public.system_info IS
'System-wide configuration key-value store. Used for upgrade channel, current version, etc.';

END;
