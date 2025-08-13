-- ================================================
-- Migration Script: statistical_unit_history & statistical_unit_history_highcharts
-- Schema: public
-- Erik August 2025
-- ================================================

-- Drop existing functions if they exist
DROP FUNCTION IF EXISTS public.statistical_unit_history(int, statistical_unit_type) CASCADE;
DROP FUNCTION IF EXISTS public.statistical_unit_history_highcharts(int, statistical_unit_type) CASCADE;
