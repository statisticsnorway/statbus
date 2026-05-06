-- Migration 20260506112552: drop topological_order, enforce
-- "no available/scheduled row may be a strict ancestor of a completed row"
-- via a BEFORE-trigger, add a backstop procedure for ops, and heal the
-- two retroactive-tagging defects observed on edge-channel installations
-- (statbus_dev, channel=edge).
--
-- ── Background ─────────────────────────────────────────────────────────
-- Edge-channel installations land on a master commit *before* tags exist
-- for it. When tags are then applied retroactively to that commit AND to
-- ancestor commits, two distinct defects compound:
--
-- A) Discovery never reaps newly-discovered ancestors. The supersede
--    machinery is invoked from install/upgrade lifecycle paths with the
--    just-installed or running SHA — never from the discovery loop with
--    the running SHA *after* discovery has inserted ancestor rows. So
--    rows like {state=available, sha=ancestor-of-running} sit forever.
--
-- B) Promotion in place is partial. The discovery UPSERT
--    (cli/internal/upgrade/service.go ON CONFLICT DO UPDATE) refreshes
--    commit_tags and release_status when a tag lands on an existing row,
--    but does NOT refresh commit_version. The row's own version label
--    drifts (e.g. "v2026.04.0-rc.69-1-g01b96ce76" while the binary self-
--    reports "v2026.04.0-rc.70" via the freshly-attached commit_tags[0]).
--
-- topological_order: the column has been NULL on every row for ~6 weeks
-- since 20260415183106 renamed it from `position`. Empirical analysis
-- of master shows the chronological proxy (committed_at) and topological
-- order disagree on only 3.4% of recent commits with worst gap of 18
-- positions — none of the disagreement intersects upgrade rows in
-- practice. Drop the column and the topo-arms in the supersede WHERE
-- clauses; the chronological proxy carries the load.
--
-- ── Order matters ──────────────────────────────────────────────────────
-- 1. Replace the two existing supersede procedures (drop topo arm).
-- 2. Drop the column.
-- 3. Create the backstop procedure (calls supersede_older per completed row).
-- 4. Create the BEFORE-INSERT-OR-UPDATE trigger that enforces the invariant.
-- 5. Heal data: refresh stale commit_version on already-promoted rows;
--    reap orphan ancestors of any completed row.

BEGIN;

-- 1. upgrade_supersede_older — drop topo arm.
--    Body otherwise identical to its prior definition at
--    20260418204304_supersede_respects_release_status_hierarchy.up.sql:9-63.
CREATE OR REPLACE PROCEDURE public.upgrade_supersede_older(
    IN p_commit_sha text,
    INOUT p_superseded integer DEFAULT 0
)
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $upgrade_supersede_older$
DECLARE
    _committed timestamptz;
    _status    public.release_status_type;
BEGIN
    SELECT committed_at, release_status
      INTO _committed, _status
      FROM public.upgrade
     WHERE commit_sha = p_commit_sha
     LIMIT 1;

    IF NOT FOUND THEN
        RAISE NOTICE 'upgrade_supersede_older: no row for commit_sha=%', p_commit_sha;
        RETURN;
    END IF;

    -- Filter by STATE — the single source of truth — not timestamps.
    -- States superseded: available, scheduled, failed, rolled_back
    -- States left alone: in_progress, completed, superseded, skipped, dismissed
    --
    -- Hierarchy guard: a row can only supersede rows with equal or lower
    -- release_status. A plain commit must never supersede a tagged prerelease
    -- or release — those have published artifacts and represent deliberate
    -- milestones. The enum ordering (commit < prerelease < release) makes
    -- the comparison natural.
    WITH superseded AS (
        UPDATE public.upgrade SET
            state = 'superseded',
            superseded_at = COALESCE(superseded_at, now())
         WHERE state IN ('available', 'scheduled', 'failed', 'rolled_back')
           AND commit_sha != p_commit_sha
           AND release_status <= _status
           AND committed_at < _committed
        RETURNING id
    )
    SELECT count(*) INTO p_superseded FROM superseded;

    IF p_superseded > 0 THEN
        RAISE NOTICE 'upgrade_supersede_older: superseded % row(s) older than % (status=%)',
            p_superseded, p_commit_sha, _status;
    END IF;
END;
$upgrade_supersede_older$;

-- 2. upgrade_supersede_completed_prereleases — drop topo arm.
--    Body otherwise identical to
--    20260417163407_supersede_completed_prereleases_same_family.up.sql:15-74.
CREATE OR REPLACE PROCEDURE public.upgrade_supersede_completed_prereleases(
    IN p_commit_sha text,
    INOUT p_superseded integer DEFAULT 0
)
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $upgrade_supersede_completed_prereleases$
DECLARE
    _committed      timestamptz;
    _family         text;
    _release_status public.release_status_type;
BEGIN
    SELECT u.committed_at, public.upgrade_family(u), u.release_status
      INTO _committed, _family, _release_status
      FROM public.upgrade u
     WHERE u.commit_sha = p_commit_sha
     LIMIT 1;

    IF NOT FOUND THEN
        RAISE NOTICE 'upgrade_supersede_completed_prereleases: no row for commit_sha=%', p_commit_sha;
        RETURN;
    END IF;

    IF _release_status != 'prerelease' OR _family IS NULL THEN
        RETURN;
    END IF;

    WITH superseded AS (
        UPDATE public.upgrade u_target SET
            state = 'superseded',
            superseded_at = COALESCE(u_target.superseded_at, now())
         WHERE u_target.state = 'completed'
           AND u_target.release_status = 'prerelease'
           AND u_target.commit_sha != p_commit_sha
           AND public.upgrade_family(u_target) = _family
           AND u_target.committed_at < _committed
        RETURNING u_target.id
    )
    SELECT count(*) INTO p_superseded FROM superseded;

    IF p_superseded > 0 THEN
        RAISE NOTICE 'upgrade_supersede_completed_prereleases: superseded % completed prerelease(s) in family %',
            p_superseded, _family;
    END IF;
END;
$upgrade_supersede_completed_prereleases$;

-- 3. Drop the column. Procedures above no longer reference it.
ALTER TABLE public.upgrade DROP COLUMN topological_order;

-- 4. Backstop procedure — operator-callable, also runs at the end of
--    this migration to reap any pre-existing orphan ancestor rows.
--
--    The DB has no notion of "the running version" — only the binary
--    knows via its compile-time ldflag. Iterating every completed row
--    newest-first is the conservative proxy: the supersede WHERE clause
--    already filters by ordering and hierarchy, so each iteration only
--    reaps strict ancestors of THAT completed row. After the first
--    iteration the rest typically find nothing to do.
CREATE PROCEDURE public.upgrade_reap_ancestors_of_completed(
    INOUT p_superseded integer DEFAULT 0
)
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $upgrade_reap_ancestors_of_completed$
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
$upgrade_reap_ancestors_of_completed$;

COMMENT ON PROCEDURE public.upgrade_reap_ancestors_of_completed(integer) IS
    'Backstop for the cross-row invariant: no available/scheduled row may be '
    'a strict ancestor of a completed row. Walks completed rows newest-first '
    'and applies upgrade_supersede_older to each. Idempotent. Safe to call '
    'periodically from operator scripts or maintenance hooks.';

-- 5. Trigger — enforces the cross-row invariant on every INSERT and on
--    UPDATEs that change state, committed_at, or release_status.
--
--    Why a trigger and not a CHECK constraint: CHECK can't reference
--    other rows; the invariant is cross-row. The trigger auto-supersedes
--    instead of erroring — discovery is allowed to *try* inserting a row
--    for an ancestor SHA; we just don't let it land as actionable.
--    Audit trail is preserved (the row exists, with state=superseded
--    and superseded_at timestamp).
CREATE FUNCTION public.upgrade_block_obsolete_pending() RETURNS trigger
LANGUAGE plpgsql AS $upgrade_block_obsolete_pending$
BEGIN
    -- Strict committed_at comparison (>) mirrors upgrade_supersede_older's
    -- "committed_at < _committed" — equal-timestamp rows are NOT ancestors
    -- of each other (no strict ordering), so the trigger leaves them alone.
    -- This matters for test fixtures with deterministic shared timestamps;
    -- in production, distinct commit timestamps make the distinction moot.
    IF NEW.state IN ('available', 'scheduled') THEN
        IF EXISTS (
            SELECT 1 FROM public.upgrade older
             WHERE older.state = 'completed'
               AND older.commit_sha != NEW.commit_sha
               AND older.release_status >= NEW.release_status
               AND older.committed_at > NEW.committed_at
        ) THEN
            NEW.state := 'superseded';
            NEW.superseded_at := COALESCE(NEW.superseded_at, now());
        END IF;
    END IF;
    RETURN NEW;
END;
$upgrade_block_obsolete_pending$;

CREATE TRIGGER upgrade_block_obsolete_pending_trigger
BEFORE INSERT OR UPDATE OF state, committed_at, release_status
ON public.upgrade
FOR EACH ROW EXECUTE FUNCTION public.upgrade_block_obsolete_pending();

-- 6. One-shot data heal.
--
-- 6a. Heal stale commit_version on rows whose tag has overtaken their
--     describe output. Defect B retroactive cleanup — Go-side fix in
--     service.go:2445-2456 prevents new occurrences.
UPDATE public.upgrade
   SET commit_version = commit_tags[1]
 WHERE array_length(commit_tags, 1) >= 1
   AND commit_version IS DISTINCT FROM commit_tags[1];

-- 6b. Reap orphan ancestors of any completed row. Defect A cleanup.
CALL public.upgrade_reap_ancestors_of_completed();

COMMIT;
