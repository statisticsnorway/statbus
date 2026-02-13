-- Migration 20260203131143: add_activity_category_code_index
--
-- PERF: Add index on activity_category(standard_id, code) for import lookups.
--
-- The import analysis phase looks up activity categories by code using the
-- activity_category_available view. Without this index, the planner may choose
-- a nested loop join that scans all active categories for each import row,
-- resulting in O(n × m) comparisons (e.g., 24k rows × 2k categories = 53M).
--
-- With this partial index (WHERE enabled = true), lookups are O(1) per row.
-- Observed improvement: 40s → 0.4s for batch activity lookup (100x faster).
BEGIN;

CREATE INDEX idx_activity_category_standard_code_enabled
ON public.activity_category (standard_id, code)
WHERE enabled = true;

END;
