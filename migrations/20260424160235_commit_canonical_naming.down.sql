-- Rollback of rc.63 commit-canonical-naming.
--
-- Restores:
-- 1. Column names: commit_version → version, from_commit_version →
--    from_version, commit_tags → tags.
-- 2. Re-adds the `sha-` prefix to from_version rows that look like
--    bare 40-char hex (best-effort — the up migration destroyed the
--    distinction between "originally had prefix" and "originally was
--    bare CalVer or 8-char", but every untagged-commit form pre-rc.63
--    was `sha-<hex>` so this reconstruction is faithful for those).
-- 3. display_name() with the old 12-char "sha-" prefix fallback and
--    old column names.
-- 4. upgrade_notify_daemon() trigger emits "sha-<40>" again.
BEGIN;

-- 1. Restore column names.
ALTER TABLE public.upgrade RENAME COLUMN commit_tags         TO tags;
ALTER TABLE public.upgrade RENAME COLUMN from_commit_version TO from_version;
ALTER TABLE public.upgrade RENAME COLUMN commit_version      TO version;

-- 2. Re-add the sha- prefix to from_version rows that look like bare
--    hex. Rows matching the CalVer shape are left alone; rows that
--    were neither (e.g. "dev") pass through unchanged.
UPDATE public.upgrade
   SET from_version = 'sha-' || from_version
 WHERE from_version ~ '^[a-f0-9]{7,40}$';

-- 3. Restore display_name() at rc.62 shape.
DROP FUNCTION IF EXISTS public.display_name(public.upgrade);
CREATE FUNCTION public.display_name(u public.upgrade)
RETURNS text LANGUAGE sql STABLE AS $display_name$
  SELECT COALESCE(
    (SELECT t FROM unnest(u.tags) AS t WHERE t NOT LIKE '%-%' LIMIT 1),
    u.tags[array_upper(u.tags, 1)],
    'sha-' || left(u.commit_sha, 12)
  );
$display_name$;

COMMENT ON FUNCTION public.display_name(public.upgrade) IS
  'PostgREST computed column. Returns the best display name: '
  'stable tag > last tag > short SHA. '
  'Usage: GET /rest/upgrade?select=*,display_name';

-- 3b. Restore upgrade_family() at rc.62 shape (uses u.tags).
CREATE OR REPLACE FUNCTION public.upgrade_family(u public.upgrade)
RETURNS text LANGUAGE sql IMMUTABLE AS $upgrade_family$
    SELECT public.version_family(COALESCE(
        (SELECT t FROM unnest(u.tags) AS t WHERE t NOT LIKE '%-%' LIMIT 1),
        u.tags[array_upper(u.tags, 1)]
    ))
$upgrade_family$;

-- 4. Restore the rc.62 notify trigger (emits "sha-<40>").
CREATE OR REPLACE FUNCTION public.upgrade_notify_daemon()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $upgrade_notify_daemon$
DECLARE
  v_payload text;
BEGIN
  IF NEW.scheduled_at IS NOT NULL AND (OLD.scheduled_at IS NULL OR OLD.scheduled_at != NEW.scheduled_at) THEN
    v_payload := 'sha-' || NEW.commit_sha;
    RAISE NOTICE 'upgrade_notify_daemon: sha=% payload=%', NEW.commit_sha, v_payload;
    PERFORM pg_notify('upgrade_apply', v_payload);
  END IF;
  RETURN NEW;
END;
$upgrade_notify_daemon$;

-- 5. Restore the strict chk_upgrade_state_attributes from
--    migration 20260421113653 — (error IS NULL) re-required on
--    available/scheduled/in_progress rows. Before re-adding the
--    constraint, clear any rc.63-era diagnostic strings that would
--    now violate it; they were most-recent-diagnostic markers, not
--    lifecycle failure reasons.
UPDATE public.upgrade
   SET error = NULL
 WHERE state IN ('available', 'scheduled', 'in_progress')
   AND error IS NOT NULL;

ALTER TABLE public.upgrade DROP CONSTRAINT chk_upgrade_state_attributes;

ALTER TABLE public.upgrade ADD CONSTRAINT chk_upgrade_state_attributes CHECK (
CASE state
    WHEN 'available'::upgrade_state THEN ((scheduled_at IS NULL) AND (started_at IS NULL) AND (completed_at IS NULL) AND (error IS NULL) AND (rolled_back_at IS NULL) AND (skipped_at IS NULL) AND (dismissed_at IS NULL) AND (superseded_at IS NULL))
    WHEN 'scheduled'::upgrade_state THEN ((scheduled_at IS NOT NULL) AND (started_at IS NULL) AND (completed_at IS NULL) AND (error IS NULL) AND (rolled_back_at IS NULL))
    WHEN 'in_progress'::upgrade_state THEN ((scheduled_at IS NOT NULL) AND (started_at IS NOT NULL) AND (completed_at IS NULL) AND (error IS NULL) AND (rolled_back_at IS NULL))
    WHEN 'completed'::upgrade_state THEN ((completed_at IS NOT NULL) AND (error IS NULL) AND (rolled_back_at IS NULL) AND (log_relative_file_path IS NOT NULL))
    WHEN 'failed'::upgrade_state THEN ((error IS NOT NULL) AND (started_at IS NOT NULL) AND (completed_at IS NULL) AND (rolled_back_at IS NULL))
    WHEN 'rolled_back'::upgrade_state THEN ((rolled_back_at IS NOT NULL) AND (error IS NOT NULL) AND (completed_at IS NULL))
    WHEN 'dismissed'::upgrade_state THEN ((dismissed_at IS NOT NULL) AND ((error IS NOT NULL) OR (rolled_back_at IS NOT NULL)))
    WHEN 'skipped'::upgrade_state THEN (skipped_at IS NOT NULL)
    WHEN 'superseded'::upgrade_state THEN (superseded_at IS NOT NULL)
    ELSE false
END);

COMMENT ON CONSTRAINT chk_upgrade_state_attributes ON public.upgrade IS
    'Invariant LOG_POINTER_STAMPED (state=completed arm): DB-enforced. '
    'Prior to 2026-04-21, enforced only by the Go-side C5 fail-fast block in '
    'cli/internal/upgrade/service.go. DB layer now binds any future bypass '
    'path (manual UPDATE, recovery tooling). '
    'Pre-ship: 33 historical NULL rows fleet-wide, backfilled to the '
    'sentinel ''unknown-pre-2026-04-15'' in the same migration.';

COMMIT;
