-- Migration 20260421113651: upgrade_state_singletons
--
-- Promote two process-level invariants (previously enforced only by the
-- install flock + upgrade-service sequencing) to DB-level singletons:
--   - SINGLE_IN_PROGRESS_UPGRADE_AT_A_TIME
--   - SINGLE_SCHEDULED_UPGRADE_AT_A_TIME
--
-- Both are partial unique indices on `state`. The only value that can
-- appear for rows matching the WHERE clause is the predicate itself, so
-- UNIQUE on a single-value column enforces "at most one such row".
-- Canonical idiom in this repo — see migration 20260317060914:412
-- (idx_tasks_derive_dedup).
--
-- Pre-ship check (tmp/paralegal-db-invariants-preship-2026-04-21.md):
-- fleet-wide 0 in_progress rows + 0 scheduled rows across all 8 cloud
-- servers. Ship unconditionally.
BEGIN;

CREATE UNIQUE INDEX upgrade_single_in_progress
    ON public.upgrade (state) WHERE state = 'in_progress';

CREATE UNIQUE INDEX upgrade_single_scheduled
    ON public.upgrade (state) WHERE state = 'scheduled';

COMMENT ON INDEX public.upgrade_single_in_progress IS
    'Invariant SINGLE_IN_PROGRESS_UPGRADE_AT_A_TIME: DB-enforced cross-row singleton. '
    'Previously enforced only by the install flock; DB layer now binds any '
    'future bypass path (manual UPDATE, split services, recovery tooling). '
    'Pre-ship verified fleet-wide 0 in_progress rows (2026-04-21).';

COMMENT ON INDEX public.upgrade_single_scheduled IS
    'Invariant SINGLE_SCHEDULED_UPGRADE_AT_A_TIME: DB-enforced cross-row singleton. '
    'Pre-ship verified fleet-wide 0 scheduled rows (2026-04-21).';

END;
