BEGIN;

CREATE FUNCTION public.release_identity(p_commit_sha text)
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
AS $release_identity$
    SELECT u.commit_sha,
           public.display_name(u) AS resolved_name,
           u.release_status,
           u.commit_version AS build_name
    FROM public.upgrade AS u
    WHERE u.commit_sha = p_commit_sha
$release_identity$;

COMMENT ON FUNCTION public.release_identity(text) IS
    'Public release metadata for an independently proven full artifact or program SHA. '
    'Exact equality only, independent of lifecycle state and history ordering. '
    'An absent/pruned row means unknown metadata, not unknown artifact provenance.';
COMMENT ON FUNCTION public.running_identity() IS
    'Legacy history-derived identity for released clients. Latest completion is not serving-app or invoked-program proof. New clients use release_identity(text) with artifact-owned SHA.';

NOTIFY pgrst, 'reload schema';
END;
