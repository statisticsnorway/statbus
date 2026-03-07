-- Migration 20260203134134: remove_duplicate_valid_range_gist_indices
--
-- Remove duplicate GIST indices on valid_range.
--
-- These ix_*_valid_range indices were created manually before sql_saga existed.
-- Now sql_saga.add_era() automatically creates *_valid_range_gist_idx indices 
-- with fillfactor=90 for optimal temporal_merge performance.
--
-- Keeping both is redundant and slows down INSERT/UPDATE operations.
-- We keep sql_saga's indices and remove the manual ones.

BEGIN;

-- Drop duplicate indices (manual versions that predate sql_saga)
DROP INDEX IF EXISTS public.ix_legal_unit_valid_range;
DROP INDEX IF EXISTS public.ix_establishment_valid_range;
DROP INDEX IF EXISTS public.ix_activity_valid_range;
DROP INDEX IF EXISTS public.ix_contact_valid_range;
-- power_group (formerly enterprise_group) is non-temporal, no index to drop
DROP INDEX IF EXISTS public.ix_location_valid_range;
DROP INDEX IF EXISTS public.ix_person_for_unit_valid_range;
DROP INDEX IF EXISTS public.ix_stat_for_unit_valid_range;

END;
