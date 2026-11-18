-- Migration 20261118041918: upgrade rows link to their release from the tag; release_url is removed
--
-- hzyejk (STATBUS-607). An upgrade row's link to its GitHub release is
-- built by the app from the version tag it shows
-- (https://github.com/statisticsnorway/statbus/releases/tag/<tag>), so the
-- address is never stored. release_url was written only by the sb releases
-- of March 2026 (discovery from the GitHub API); no released sb since reads
-- or writes it, and every row has it NULL.
BEGIN;

ALTER TABLE public.upgrade DROP COLUMN release_url;

END;
