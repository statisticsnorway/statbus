-- Down migration for 20260417085502: revert to Rules A-D only (no Rule E).
-- Restore the original upgrade_retention_plan function from the parent migration.

BEGIN;

CREATE OR REPLACE FUNCTION public.upgrade_retention_plan(
    p_context      text,
    p_installed_id integer DEFAULT NULL
) RETURNS TABLE(
    id                     integer,
    action                 text,
    reason                 text,
    log_relative_file_path text
)
LANGUAGE sql STABLE
SET search_path = public, pg_temp
AS $upgrade_retention_plan$
    WITH installed AS (
        SELECT u.*, public.upgrade_family(u) AS family
          FROM public.upgrade u
         WHERE u.id = p_installed_id
    ),
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
$upgrade_retention_plan$;

COMMENT ON FUNCTION public.upgrade_retention_plan(text, integer) IS
    'Pure SELECT planner for public.upgrade retention. Returns (id, action, reason, log_relative_file_path) '
    'rows that upgrade_retention_apply will delete. Safe to call for preview or testing.';

END;
