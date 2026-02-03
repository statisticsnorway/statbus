-- Down Migration 20260203131143: add_activity_category_code_index
BEGIN;

DROP INDEX IF EXISTS public.idx_activity_category_standard_code_active;

END;
