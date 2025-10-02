
-- ============================================================
-- Migration Script:  public.statistical_stats_highcharts
-- Schema: public
-- Erik October 2025
-- ============================================================

-- Drop existing functions if exist

DROP FUNCTION IF EXISTS public.statistical_stats_highcharts(p_resolution history_resolution, p_unit_type statistical_unit_type) CASCADE;