-- Down Migration: Revert O(n²) fix for timeline_legal_unit refresh
BEGIN;

-- Restore original timeline_legal_unit_refresh procedure that uses the generic timeline_refresh
CREATE OR REPLACE PROCEDURE public.timeline_legal_unit_refresh(p_unit_id_ranges int4multirange DEFAULT NULL)
LANGUAGE plpgsql
AS $timeline_legal_unit_refresh$
BEGIN
    ANALYZE public.timesegments, public.legal_unit, public.activity, public.location, public.contact, public.stat_for_unit, public.timeline_establishment;
    CALL public.timeline_refresh('timeline_legal_unit', 'legal_unit', p_unit_id_ranges);
END;
$timeline_legal_unit_refresh$;

END;
