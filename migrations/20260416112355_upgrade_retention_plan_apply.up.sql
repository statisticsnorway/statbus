-- Migration 20260416112355: upgrade retention plan/apply
--
-- Retention policy for public.upgrade — introduced per the v2 plan/apply
-- design at tmp/partner-retention-strategy-v2-plan-apply-2026-04-15.md.
--
-- Structure:
--   1. version_family / upgrade_family helpers (IMMUTABLE, reusable)
--   2. upgrade_retention_caps — operator-tunable per (release_status,state) cell.
--      NULL time_cap OR NULL count_cap  → NEVER purge this cell.
--   3. upgrade_retention_plan(p_context, p_installed_id) — pure STABLE SELECT
--      returning (id, action, reason, log_relative_file_path).
--   4. upgrade_retention_apply(p_context, p_installed_id, OUT p_deleted) — thin
--      executor that materializes the plan, RAISE NOTICEs, DELETEs.
--
-- Key invariants:
--   - Planner uses committed_at for age AND ranking (git-timeline, always set).
--     scheduled_at is NULL for available/superseded/dismissed rows by
--     chk_upgrade_state_attributes CHECK — it would be useless as a ranker.
--   - DISTINCT ON (id) collapses rule overlaps (install-purge + time-safety
--     hitting the same row) to a single action so the executor DELETEs each
--     id at most once.
--   - Zombie protection (scheduled/in_progress) is implicit: the caps seed
--     leaves those cells without a time_cap/count_cap pair, so they never
--     match the time_safety WHERE gate. No explicit NOT IN filter needed.

BEGIN;

-- 1. Family helpers.
--
-- version_family('v2026.04.0-rc.3') → 'v2026.04.0'.  Pure string op.
CREATE FUNCTION public.version_family(tag text) RETURNS text
LANGUAGE sql IMMUTABLE
AS $version_family$
    SELECT split_part(tag, '-', 1)
$version_family$;

COMMENT ON FUNCTION public.version_family(text) IS
    'Extracts the family root of a tag by taking everything before the first dash. '
    'Used by upgrade_retention_plan to group prereleases with their stable release.';

-- upgrade_family(upgrade) — picks the "primary" tag for a row:
--   prefer a stable tag (no dash) if present; else last element of tags[].
-- NULL if tags is empty (commit-only row has nothing to derive family from).
CREATE FUNCTION public.upgrade_family(u public.upgrade) RETURNS text
LANGUAGE sql IMMUTABLE
AS $upgrade_family$
    SELECT public.version_family(COALESCE(
        (SELECT t FROM unnest(u.tags) AS t WHERE t NOT LIKE '%-%' LIMIT 1),
        u.tags[array_upper(u.tags, 1)]
    ))
$upgrade_family$;

COMMENT ON FUNCTION public.upgrade_family(public.upgrade) IS
    'Returns the version family root for an upgrade row based on its tags. '
    'Prefers stable tags over prerelease tags when both are present.';

-- 2. Retention caps — operator-tunable, per (release_status, state) cell.
--
-- time_cap NULL AND/OR count_cap NULL  → cell is NEVER time-purged.
-- install_purge = TRUE marks cells eligible for contextual install-triggered
--   deletion (the planner's install_* rules still apply their own semantic
--   filters; the flag is a policy gate the operator can flip off).
CREATE TABLE public.upgrade_retention_caps (
    release_status public.release_status_type NOT NULL,
    state          public.upgrade_state       NOT NULL,
    time_cap       interval,
    count_cap      integer,
    install_purge  boolean NOT NULL DEFAULT false,
    PRIMARY KEY (release_status, state)
);

COMMENT ON TABLE public.upgrade_retention_caps IS
    'Per-(release_status, state) retention policy for public.upgrade. '
    'NULL time_cap or NULL count_cap = never time-purge this cell. '
    'install_purge = eligible for contextual install-triggered purge.';

-- Seed from the decision table in the v2 design doc. Pattern:
--   (release_status, state, time_cap, count_cap, install_purge)
--   NULL time/count  → NEVER / audit-forever.
--   install_purge=TRUE only on non-terminal states where install context
--     gives a cheap semantic to delete rows rendered obsolete by the install.
INSERT INTO public.upgrade_retention_caps (release_status, state, time_cap, count_cap, install_purge) VALUES
    -- release channel ------------------------------------------------------
    ('release',    'scheduled',   NULL,              NULL,  false),  -- zombie
    ('release',    'in_progress', NULL,              NULL,  false),  -- zombie
    ('release',    'completed',   '10 years'::interval, 100, false),
    ('release',    'rolled_back', '10 years'::interval,  50, false),
    ('release',    'failed',      '10 years'::interval,  50, false),
    ('release',    'available',   '1 year'::interval,    20, false),
    ('release',    'superseded',  '1 year'::interval,    20, false),
    ('release',    'dismissed',   '1 year'::interval,    20, false),
    ('release',    'skipped',     '1 year'::interval,    20, false),
    -- prerelease channel ---------------------------------------------------
    ('prerelease', 'scheduled',   NULL,              NULL,  false),
    ('prerelease', 'in_progress', NULL,              NULL,  false),
    ('prerelease', 'completed',   '1 year'::interval,    50, false),
    ('prerelease', 'rolled_back', '2 years'::interval,   50, false),
    ('prerelease', 'failed',      '2 years'::interval,   50, false),
    ('prerelease', 'available',   '60 days'::interval,   30, true),
    ('prerelease', 'superseded',  '60 days'::interval,   30, true),
    ('prerelease', 'dismissed',   '60 days'::interval,   30, true),
    ('prerelease', 'skipped',     '60 days'::interval,   30, true),
    -- commit channel -------------------------------------------------------
    ('commit',     'scheduled',   NULL,              NULL,  false),
    ('commit',     'in_progress', NULL,              NULL,  false),
    ('commit',     'completed',   '90 days'::interval,   30, false),
    ('commit',     'rolled_back', '180 days'::interval,  30, false),
    ('commit',     'failed',      '180 days'::interval,  30, false),
    ('commit',     'available',   '14 days'::interval,   20, true),
    ('commit',     'superseded',  '14 days'::interval,   20, true),
    ('commit',     'dismissed',   '14 days'::interval,   20, true),
    ('commit',     'skipped',     '14 days'::interval,   20, true);

-- Grants — keep caps readable to authenticated users (UI/CLI visibility)
-- and writable only to admin. Policy mirrors public.upgrade.
ALTER TABLE public.upgrade_retention_caps ENABLE ROW LEVEL SECURITY;
CREATE POLICY upgrade_retention_caps_admin_manage ON public.upgrade_retention_caps
    TO admin_user USING (true) WITH CHECK (true);
CREATE POLICY upgrade_retention_caps_authenticated_view ON public.upgrade_retention_caps
    FOR SELECT TO authenticated USING (true);
GRANT SELECT ON public.upgrade_retention_caps TO authenticated;
GRANT ALL    ON public.upgrade_retention_caps TO admin_user;

-- 3. The planner: pure STABLE SELECT. Enumerates candidates per rule-CTE,
--    then DISTINCT ON (id) ORDER BY id for deterministic test output.
--
-- p_context values:
--   'all'        — no filter on candidate release_status (time-safety sweep)
--   'commit'/'prerelease'/'release' — only rows in that channel (scoped tick)
-- p_installed_id: the row that just transitioned to 'completed'. NULL for
-- time-safety-only sweeps. The install_* CTEs resolve to empty when NULL.
CREATE FUNCTION public.upgrade_retention_plan(
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
$upgrade_retention_plan$;

COMMENT ON FUNCTION public.upgrade_retention_plan(text, integer) IS
    'Pure SELECT planner for public.upgrade retention. Returns (id, action, reason, log_relative_file_path) '
    'rows that upgrade_retention_apply will delete. Safe to call for preview or testing.';

-- 4. The executor. Thin: materializes the plan, RAISE NOTICE per row,
--    DELETE. Out-parameter returns the delete count.
CREATE PROCEDURE public.upgrade_retention_apply(
    p_context      text,
    p_installed_id integer DEFAULT NULL,
    INOUT p_deleted integer DEFAULT 0
)
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $upgrade_retention_apply$
DECLARE
    r record;
BEGIN
    -- Temp table lets us both log and delete from the same plan without
    -- calling the STABLE function twice (it's stable within a statement
    -- boundary, not within a transaction — concurrent INSERT between
    -- plan and delete could otherwise produce divergent sets).
    IF to_regclass('pg_temp._upgrade_retention_plan') IS NOT NULL THEN
        DROP TABLE _upgrade_retention_plan;
    END IF;
    CREATE TEMP TABLE _upgrade_retention_plan ON COMMIT DROP AS
        SELECT * FROM public.upgrade_retention_plan(p_context, p_installed_id);

    FOR r IN SELECT id, action, reason FROM _upgrade_retention_plan LOOP
        RAISE NOTICE 'upgrade_retention: id=% action=% reason=%', r.id, r.action, r.reason;
    END LOOP;

    DELETE FROM public.upgrade
     WHERE id IN (SELECT id FROM _upgrade_retention_plan WHERE action = 'delete');
    GET DIAGNOSTICS p_deleted = ROW_COUNT;
END;
$upgrade_retention_apply$;

COMMENT ON PROCEDURE public.upgrade_retention_apply(text, integer, integer) IS
    'Executes upgrade_retention_plan: RAISE NOTICEs each planned row and deletes by id. '
    'Caller is expected to remove sibling log files before calling (file-first cascade).';

-- Grants. Planner: both admin + authenticated (UI preview). Apply: admin
-- only (mutating, caller is the upgrade service running as admin role).
GRANT EXECUTE ON FUNCTION  public.upgrade_retention_plan(text, integer)         TO authenticated;
GRANT EXECUTE ON FUNCTION  public.upgrade_retention_plan(text, integer)         TO admin_user;
GRANT EXECUTE ON PROCEDURE public.upgrade_retention_apply(text, integer, integer) TO admin_user;

GRANT EXECUTE ON FUNCTION public.version_family(text)                  TO authenticated;
GRANT EXECUTE ON FUNCTION public.upgrade_family(public.upgrade)        TO authenticated;

END;
