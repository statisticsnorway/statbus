```sql
CREATE OR REPLACE FUNCTION public.running_identity()
 RETURNS TABLE(commit_sha text, resolved_name text, release_status release_status_type, build_name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER ROWS 1
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT
        u.commit_sha,
        public.display_name(u) AS resolved_name,
        u.release_status,
        u.commit_version AS build_name
    FROM public.upgrade AS u
    WHERE u.state = 'completed'
    ORDER BY u.completed_at DESC, u.id DESC
    LIMIT 1
$function$
```
