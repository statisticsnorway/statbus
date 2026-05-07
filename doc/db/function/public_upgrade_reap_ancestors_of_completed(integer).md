```sql
CREATE OR REPLACE PROCEDURE public.upgrade_reap_ancestors_of_completed(INOUT p_superseded integer DEFAULT 0)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $procedure$
DECLARE
    r RECORD;
    n integer;
BEGIN
    p_superseded := 0;
    FOR r IN
        SELECT commit_sha
          FROM public.upgrade
         WHERE state = 'completed'
         ORDER BY committed_at DESC, id DESC
    LOOP
        CALL public.upgrade_supersede_older(r.commit_sha, n);
        p_superseded := p_superseded + COALESCE(n, 0);
    END LOOP;
    IF p_superseded > 0 THEN
        RAISE NOTICE 'upgrade_reap_ancestors_of_completed: superseded % row(s)', p_superseded;
    END IF;
END;
$procedure$
```
