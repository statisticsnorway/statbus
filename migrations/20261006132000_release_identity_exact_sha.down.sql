BEGIN;
DROP FUNCTION public.release_identity(text);
COMMENT ON FUNCTION public.running_identity() IS
    'Public runtime identity read model for GET /rest/rpc/running_identity. Selects the installed commit from the latest completed upgrade row, resolves its current name through public.display_name(upgrade), and retains commit_version separately as immutable build provenance.';
NOTIFY pgrst, 'reload schema';
END;
