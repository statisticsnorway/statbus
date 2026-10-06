```sql
CREATE OR REPLACE FUNCTION public.release_identity(p_commit_sha text)
 RETURNS TABLE(commit_sha text, resolved_name text, release_status release_status_type, build_name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER ROWS 1
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT u.commit_sha,
           public.display_name(u) AS resolved_name,
           u.release_status,
           u.commit_version AS build_name
    FROM public.upgrade AS u
    WHERE u.commit_sha = p_commit_sha
$function$
```

This is public release **metadata**, not an observer of running processes. The caller
must first prove a full SHA independently. The app refreshes `/_statbus-build.json`
from the responding artifact with request and response `no-store`, then calls
`/rest/rpc/release_identity?p_commit_sha=<full SHA>`. Image publication stamps the
actual clean checkout SHA before compilation. Local builds are explicitly unknown.
Runtime environment/configured checkout does not change the static artifact.

Exact equality uses the existing unique upgrade SHA, regardless of lifecycle state
or history order. A missing/pruned row yields no metadata. Clients retain proven
artifact SHA but clear the label, reject ambiguous/malformed/mismatched responses,
and do not substitute recent history. Promotion can change release metadata without
changing the artifact SHA or registered build name.

The CLI supplies its positively resolved executable SHA and labels it as the invoked
program, not the separately serving app or the source of an install. The zero-argument
`running_identity()` remains a legacy history-derived query for released clients,
not updated clients' identity source. Security and public metadata access match that
legacy function. No singleton, identity writer or retention policy is introduced.
