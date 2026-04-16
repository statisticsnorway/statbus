```sql
CREATE OR REPLACE FUNCTION public.upgrade_retention_plan(p_context text, p_installed_id integer DEFAULT NULL::integer)
 RETURNS TABLE(id integer, action text, reason text, log_relative_file_path text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
    WITH installed AS (
        SELECT u.*, public.upgrade_family(u) AS family
          FROM public.upgrade u
         WHERE u.id = p_installed_id
    ),
    -- Rule A: just-installed release → purge same-family prereleases in
    -- non-evidence states. Families line up; these are now "the old rc's
    -- for the thing that shipped". Gated by install_purge = true on the
    -- candidate's (release_status, state) cell so the operator can opt out.
    install_same_family_prereleases AS (
        SELECT u.id,
               'delete'::text AS action,
               format('prerelease/%s install-purge: same family %s as just-installed release',
                      u.state, i.family) AS reason,
               u.log_relative_file_path
          FROM public.upgrade u
          JOIN installed i ON TRUE
          JOIN public.upgrade_retention_caps c
            ON c.release_status = u.release_status
           AND c.state          = u.state
         WHERE i.release_status = 'release'
           AND u.release_status = 'prerelease'
           AND u.state IN ('available','superseded','dismissed','skipped')
           AND c.install_purge  = true
           AND public.upgrade_family(u) = i.family
    ),
    -- Rule B: just-installed release → purge commits committed_at-older
    -- than the most recent OTHER completed release. Gives commit-channel
    -- a safety hold-back to the previous release cycle, not to the just-
    -- installed one (which would be the trivial "everything before now").
    -- Gated by install_purge on the candidate commit's state cell.
    install_old_commits_vs_release AS (
        SELECT u.id,
               'delete'::text AS action,
               format('commit/%s install-purge: older (committed_at=%s) than last completed release',
                      u.state, u.committed_at::text) AS reason,
               u.log_relative_file_path
          FROM public.upgrade u
          JOIN installed i ON TRUE
          JOIN public.upgrade_retention_caps c
            ON c.release_status = u.release_status
           AND c.state          = u.state
         WHERE i.release_status = 'release'
           AND u.release_status = 'commit'
           AND u.state IN ('available','superseded','dismissed','skipped')
           AND c.install_purge  = true
           AND u.committed_at < (
               SELECT max(committed_at) FROM public.upgrade
                WHERE release_status = 'release'
                  AND state = 'completed'
                  AND id <> i.id
           )
    ),
    -- Rule C: just-installed prerelease → purge commits older than the
    -- most recent OTHER completed prerelease. Symmetric to Rule B but on
    -- the prerelease channel — gives rc-driven dogfood a similar hold-back.
    -- Gated by install_purge on the candidate commit's state cell.
    install_old_commits_vs_prerelease AS (
        SELECT u.id,
               'delete'::text AS action,
               format('commit/%s install-purge: older (committed_at=%s) than last completed prerelease',
                      u.state, u.committed_at::text) AS reason,
               u.log_relative_file_path
          FROM public.upgrade u
          JOIN installed i ON TRUE
          JOIN public.upgrade_retention_caps c
            ON c.release_status = u.release_status
           AND c.state          = u.state
         WHERE i.release_status = 'prerelease'
           AND u.release_status = 'commit'
           AND u.state IN ('available','superseded','dismissed','skipped')
           AND c.install_purge  = true
           AND u.committed_at < (
               SELECT max(committed_at) FROM public.upgrade
                WHERE release_status = 'prerelease'
                  AND state = 'completed'
                  AND id <> i.id
           )
    ),
    -- Rule D: time-safety sweep. AND-gate on time AND count:
    --   age(committed_at) > time_cap   AND
    --   channel population > count_cap AND
    --   this row ranks older than count_cap in its (release_status,state) bucket.
    -- Ranking by committed_at DESC → row_number ascending from newest; rn
    -- > count_cap → this row is beyond the "newest N kept" window.
    time_safety AS (
        SELECT ranked.id,
               'delete'::text AS action,
               format('%s/%s time-safety: age=%s > cap=%s AND channel_count=%s > cap=%s (rank #%s)',
                      ranked.release_status, ranked.state,
                      (now() - ranked.committed_at)::text, ranked.time_cap::text,
                      ranked.chan_count::text, ranked.count_cap::text, ranked.rn::text) AS reason,
               ranked.log_relative_file_path
          FROM (
              SELECT u.id, u.log_relative_file_path, u.release_status, u.state, u.committed_at,
                     c.time_cap, c.count_cap,
                     row_number() OVER (PARTITION BY u.release_status, u.state
                                        ORDER BY u.committed_at DESC) AS rn,
                     count(*)     OVER (PARTITION BY u.release_status, u.state) AS chan_count
                FROM public.upgrade u
                JOIN public.upgrade_retention_caps c
                  ON c.release_status = u.release_status
                 AND c.state          = u.state
               WHERE c.time_cap  IS NOT NULL
                 AND c.count_cap IS NOT NULL
                 AND (p_context = 'all' OR u.release_status::text = p_context)
          ) ranked
         WHERE now() - ranked.committed_at > ranked.time_cap
           AND ranked.chan_count           > ranked.count_cap
           AND ranked.rn                   > ranked.count_cap
    )
    SELECT DISTINCT ON (all_rules.id)
           all_rules.id, all_rules.action, all_rules.reason, all_rules.log_relative_file_path
      FROM (
          SELECT * FROM install_same_family_prereleases
          UNION ALL SELECT * FROM install_old_commits_vs_release
          UNION ALL SELECT * FROM install_old_commits_vs_prerelease
          UNION ALL SELECT * FROM time_safety
      ) AS all_rules
     ORDER BY all_rules.id, all_rules.action;
$function$
```
