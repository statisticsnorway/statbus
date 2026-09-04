-- Migration 20260904111126: publish running identity
-- STATBUS-355: publish the current name of the installed commit without
-- rewriting build/install provenance when the same commit gains a newer tag.
BEGIN;

CREATE FUNCTION public.running_identity()
RETURNS TABLE (
    commit_sha text,
    resolved_name text,
    release_status public.release_status_type,
    build_name text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
ROWS 1
AS $running_identity$
    SELECT
        u.commit_sha,
        public.display_name(u) AS resolved_name,
        u.release_status,
        u.commit_version AS build_name
    FROM public.upgrade AS u
    WHERE u.state = 'completed'
    ORDER BY u.completed_at DESC, u.id DESC
    LIMIT 1
$running_identity$;

COMMENT ON FUNCTION public.running_identity() IS
    'Public runtime identity read model for GET /rest/rpc/running_identity. '
    'Selects the installed commit from the latest completed upgrade row, '
    'resolves its current name through public.display_name(upgrade), and '
    'retains commit_version separately as immutable build provenance.';

NOTIFY pgrst, 'reload schema';

END;
