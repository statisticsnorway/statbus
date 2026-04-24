-- Rc.63 commit-canonical-naming: align the upgrade-table schema with
-- the four canonical names used in the Go codebase. One name, one
-- semantic; no `sha-` prefix anywhere. See doc/upgrade-system.md +
-- cli/internal/upgrade/commit.go for the naming rules.
--
-- Changes:
-- 1. Rename 3 columns in public.upgrade:
--    version              → commit_version
--    from_version         → from_commit_version
--    tags                 → commit_tags
-- 2. Strip the legacy `sha-` prefix from existing from_version values
--    (the only polymorphic column — held either CalVer or `sha-<hex>`).
-- 3. Update public.display_name() to use new column names AND drop the
--    `sha-` prefix + align length from 12 to 8 (canonical commit_short).
-- 4. Update upgrade_notify_daemon() trigger to emit bare commit_sha
--    (rc.63 canonical) — Go receiver strips the legacy `sha-` prefix
--    during a transitional window, so either form is understood by
--    the rc.63 service.
-- 5. Relax chk_upgrade_state_attributes: allow `error` to be written
--    on available/scheduled/in_progress rows (was forbidden before).
--    markCIImagesFailed writes a CI-failure-diagnostic string to error
--    before the upgrade reaches a terminal state; the prior CHECK
--    rejected it and the service escalated via CI_FAILURE_DETECTED_
--    TRANSITIONS_ROW as a false positive. The `error` column now
--    doubles as a most-recent-diagnostic on pre-terminal states while
--    remaining the terminal-failure reason on failed/rolled_back.
BEGIN;

-- 1. Column renames. All indexes, RLS policies, constraints, and the
--    PostgREST computed-column function track column names by reference,
--    so RENAME is a metadata-only operation (no table rewrite).
ALTER TABLE public.upgrade RENAME COLUMN version      TO commit_version;
ALTER TABLE public.upgrade RENAME COLUMN from_version TO from_commit_version;
ALTER TABLE public.upgrade RENAME COLUMN tags         TO commit_tags;

-- 2. Value migration on from_commit_version.
--    Pre-rc.63 writers stored "sha-<hex>" for untagged commits and
--    CalVer tags for tagged ones. Post-rc.63 the column holds bare
--    strings only (CalVer or 8-char commit_short). Strip any legacy
--    prefix in place; rows that don't match the prefix are unchanged.
UPDATE public.upgrade
   SET from_commit_version = regexp_replace(from_commit_version, '^sha-', '')
 WHERE from_commit_version ~ '^sha-';

-- 3. PostgREST computed column: display_name.
--    Previous definition used the renamed column and a 12-char "sha-"
--    prefixed fallback. Redefine against the new column names and
--    align to the canonical 8-char bare form.
DROP FUNCTION IF EXISTS public.display_name(public.upgrade);
CREATE FUNCTION public.display_name(u public.upgrade)
RETURNS text LANGUAGE sql STABLE AS $display_name$
  SELECT COALESCE(
    (SELECT t FROM unnest(u.commit_tags) AS t WHERE t NOT LIKE '%-%' LIMIT 1),
    u.commit_tags[array_upper(u.commit_tags, 1)],
    left(u.commit_sha, 8)
  );
$display_name$;

COMMENT ON FUNCTION public.display_name(public.upgrade) IS
  'PostgREST computed column. Returns the best display name: '
  'stable release tag > last tag > 8-char commit_short (no sha- prefix). '
  'Usage: GET /rest/upgrade?select=*,display_name';

-- 4. upgrade_notify_daemon trigger: emit bare commit_sha (rc.63) instead
--    of "sha-<40>" (rc.62 and earlier). The rc.63 receiver strips the
--    legacy prefix during the transition window, so both forms are
--    accepted. Once all deploys are on rc.63+ the legacy-compat branch
--    in cli/internal/upgrade/commit.go can be deleted.
CREATE OR REPLACE FUNCTION public.upgrade_notify_daemon()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $upgrade_notify_daemon$
BEGIN
  IF NEW.scheduled_at IS NOT NULL AND (OLD.scheduled_at IS NULL OR OLD.scheduled_at != NEW.scheduled_at) THEN
    RAISE NOTICE 'upgrade_notify_daemon: commit_sha=%', NEW.commit_sha;
    PERFORM pg_notify('upgrade_apply', NEW.commit_sha);
  END IF;
  RETURN NEW;
END;
$upgrade_notify_daemon$;

-- 5. Relax chk_upgrade_state_attributes on pre-terminal states.
--    Original CHECK (migration 20260421113653) forbade `error` on
--    available/scheduled/in_progress. Rc.63 relaxes that: markCIImagesFailed
--    writes a CI-failure diagnostic to error before the upgrade lifecycle
--    reaches its own terminal state, so the column doubles as a
--    most-recent-diagnostic on pre-terminal rows.
--
--    Follows the same DROP/ADD pattern as migration 20260421113653 so
--    the constraint keeps its name and can be rolled back cleanly.
ALTER TABLE public.upgrade DROP CONSTRAINT chk_upgrade_state_attributes;

ALTER TABLE public.upgrade ADD CONSTRAINT chk_upgrade_state_attributes CHECK (
CASE state
    WHEN 'available'::upgrade_state   THEN ((scheduled_at IS NULL) AND (started_at IS NULL) AND (completed_at IS NULL) AND (rolled_back_at IS NULL) AND (skipped_at IS NULL) AND (dismissed_at IS NULL) AND (superseded_at IS NULL))
    WHEN 'scheduled'::upgrade_state   THEN ((scheduled_at IS NOT NULL) AND (started_at IS NULL) AND (completed_at IS NULL) AND (rolled_back_at IS NULL))
    WHEN 'in_progress'::upgrade_state THEN ((scheduled_at IS NOT NULL) AND (started_at IS NOT NULL) AND (completed_at IS NULL) AND (rolled_back_at IS NULL))
    WHEN 'completed'::upgrade_state   THEN ((completed_at IS NOT NULL) AND (error IS NULL) AND (rolled_back_at IS NULL) AND (log_relative_file_path IS NOT NULL))
    WHEN 'failed'::upgrade_state      THEN ((error IS NOT NULL) AND (started_at IS NOT NULL) AND (completed_at IS NULL) AND (rolled_back_at IS NULL))
    WHEN 'rolled_back'::upgrade_state THEN ((rolled_back_at IS NOT NULL) AND (error IS NOT NULL) AND (completed_at IS NULL))
    WHEN 'dismissed'::upgrade_state   THEN ((dismissed_at IS NOT NULL) AND ((error IS NOT NULL) OR (rolled_back_at IS NOT NULL)))
    WHEN 'skipped'::upgrade_state     THEN (skipped_at IS NOT NULL)
    WHEN 'superseded'::upgrade_state  THEN (superseded_at IS NOT NULL)
    ELSE false
END);

COMMENT ON CONSTRAINT chk_upgrade_state_attributes ON public.upgrade IS
    'Invariant LOG_POINTER_STAMPED (state=completed arm): DB-enforced. '
    'Prior to 2026-04-21, enforced only by the Go-side C5 fail-fast block in '
    'cli/internal/upgrade/service.go. DB layer now binds any future bypass '
    'path (manual UPDATE, recovery tooling). '
    'Pre-ship: 33 historical NULL rows fleet-wide, backfilled to the '
    'sentinel ''unknown-pre-2026-04-15'' in the same migration. '
    'Rc.63 (2026-04-24): relaxed the available/scheduled/in_progress arms '
    'to permit a non-NULL error. error is REQUIRED on failed/rolled_back '
    '(terminal failure reason); OPTIONAL on available/scheduled/in_progress '
    'as a most-recent-diagnostic (e.g. markCIImagesFailed writes the CI '
    'failure reason before the upgrade lifecycle reaches a terminal state). '
    'completed and skipped/superseded rows stay error-free by design.';

COMMIT;
