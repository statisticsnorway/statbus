-- ================================================
-- Migration Script: get_statistical_unit_history & get_statistical_unit_history_for_highcharts
-- Schema: public
-- Erik August 2025
-- ================================================

-- Drop existing functions if they exist
DROP FUNCTION IF EXISTS public.get_statistical_unit_history(int, statistical_unit_type) CASCADE;
DROP FUNCTION IF EXISTS public.get_statistical_unit_history_for_highcharts(int, statistical_unit_type) CASCADE;
