-- Migration 20260828225222: repair tag object sha pollution rc14 rc15
--
-- STATBUS-304. Two release tags, v2026.08.0-rc.14 and v2026.08.0-rc.15, were
-- registered by pre-STATBUS-255 (August) era code that resolved a tag
-- reference without peeling to ^{commit}. Our release tags are ANNOTATED
-- (cut with `git tag -m`), so a bare `git rev-parse <tag>` returns the TAG
-- OBJECT's own SHA rather than the commit it points at — two different
-- objects that always differ for an annotated tag. The wrong object was
-- recorded in commit_sha, silently, on every box that discovered these two
-- tags under the old code.
--
-- SCOPE (STATBUS-303's operator collection, tmp/304-and-demo-report.md,
-- 2026-08-28): five boxes — tcc, et, jo, ma, ug — each carry exactly one
-- polluted row per tag (commit_sha is UNIQUE, so at most one row per SHA
-- per box). All five show the IDENTICAL wrong SHAs, consistent with the
-- same pre-255 binary running the same releases-API discovery everywhere.
-- This migration runs on every box; only boxes that actually have a
-- matching polluted row are touched — the other four's non-matching WHERE
-- clauses simply update zero rows.
--
-- STOPPED, NOT ONGOING (architect ruling, STATBUS-304 comment #1, mechanic
-- verification comment #2): DiscoverTagsViaGit (the current git-based
-- discovery, STATBUS-255) already peels correctly, and the one unverified
-- non-test rev-parse site (CommitLookup.RevParse, service.go:5605-5619) was
-- confirmed to append ^{commit} explicitly. No current code path can write
-- a fresh instance of this defect — this migration repairs PAST damage
-- only.
--
-- THE VALUES (verified independently via `git rev-parse <tag>` and
-- `git rev-parse <tag>^{commit}` against this repository, matching the
-- operator's collection exactly):
--
--   v2026.08.0-rc.14:
--     tag object (WRONG, currently stored): 00f346039e26cf94dd70e8a57b06df4abb427ad2
--     commit     (CORRECT, target value):   50b13d70db8c83199fadc2c58eb5d406301de8a9
--
--   v2026.08.0-rc.15:
--     tag object (WRONG, currently stored): 0eb4c45ef880ba5150edc812fbced384f402164c
--     commit     (CORRECT, target value):   2b3862bccb9716db4bb327b6946f99c25e5efef4
--
-- THE SAFETY PROPERTY: each UPDATE's WHERE clause requires BOTH
-- commit_version = the exact affected tag AND commit_sha = the exact wrong
-- object SHA. Matching on the wrong SHA alone would already be extremely
-- precise (SHAs do not collide by accident), but requiring the tag too
-- means a row can only be touched if it matches the FULL documented defect
-- shape — never a row that merely happens to share one of the two values
-- for an unrelated reason.
--
-- THE UNIQUE-CONSTRAINT GUARD: commit_sha carries upgrade_commit_sha_key
-- (UNIQUE). If a box's post-255 discovery has ALREADY registered the
-- correct commit as its own separate row (e.g. via later re-discovery),
-- writing the correct SHA onto the polluted row would collide and abort
-- the whole migration. Each UPDATE below is therefore additionally guarded
-- with NOT EXISTS against that correct SHA already being present — on the
-- (expected-empty) boxes where that guard trips, the polluted row is left
-- untouched rather than crashing the migration, and the NOTICE below names
-- exactly which box/tag needs a human follow-up.
--
-- Idempotent: after this migration runs once on a given box, its polluted
-- rows (if any) now hold the correct commit_sha, so the WHERE clauses no
-- longer match anything on a re-run. Safe to re-run, matching the house
-- pattern (20260425163029_dismiss_corrupt_upgrade_lifecycle_rows).

BEGIN;

UPDATE public.upgrade
   SET commit_sha = '50b13d70db8c83199fadc2c58eb5d406301de8a9'
 WHERE commit_version = 'v2026.08.0-rc.14'
   AND commit_sha = '00f346039e26cf94dd70e8a57b06df4abb427ad2'
   AND NOT EXISTS (
         SELECT 1 FROM public.upgrade AS existing
          WHERE existing.commit_sha = '50b13d70db8c83199fadc2c58eb5d406301de8a9'
       );

UPDATE public.upgrade
   SET commit_sha = '2b3862bccb9716db4bb327b6946f99c25e5efef4'
 WHERE commit_version = 'v2026.08.0-rc.15'
   AND commit_sha = '0eb4c45ef880ba5150edc812fbced384f402164c'
   AND NOT EXISTS (
         SELECT 1 FROM public.upgrade AS existing
          WHERE existing.commit_sha = '2b3862bccb9716db4bb327b6946f99c25e5efef4'
       );

-- VISIBILITY, NOT SILENCE: if either polluted row is STILL present after
-- the UPDATEs above (either it never existed on this box — the common
-- case for 3 of the 5 boxes' non-matching tags — or the UNIQUE guard
-- tripped), name it explicitly rather than leaving a future reader to
-- rediscover the same pollution from scratch. A box where neither tag was
-- ever recorded prints nothing extra beyond confirming zero remain.
DO $do$
DECLARE
    v_still_polluted text;
BEGIN
    SELECT string_agg(commit_version || ' (id=' || id || ')', ', ' ORDER BY id)
      INTO v_still_polluted
      FROM public.upgrade
     WHERE (commit_version, commit_sha) IN (
               ('v2026.08.0-rc.14', '00f346039e26cf94dd70e8a57b06df4abb427ad2'),
               ('v2026.08.0-rc.15', '0eb4c45ef880ba5150edc812fbced384f402164c')
           );
    IF v_still_polluted IS NOT NULL THEN
        RAISE NOTICE 'STATBUS-304: % still stores a tag-object SHA after the repair UPDATEs — the UNIQUE-constraint guard likely tripped (a correct row for that commit already exists on this box). Needs a human look, not a re-run of this migration.', v_still_polluted;
    END IF;
END;
$do$;

COMMIT;
