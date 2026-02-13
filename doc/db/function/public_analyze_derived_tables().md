```sql
CREATE OR REPLACE PROCEDURE public.analyze_derived_tables()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    RAISE DEBUG 'Running ANALYZE on derived tables...';
    ANALYZE public.timepoints;
    ANALYZE public.timesegments;
    ANALYZE public.timesegments_years;
    ANALYZE public.timeline_establishment;
    ANALYZE public.timeline_legal_unit;
    ANALYZE public.timeline_enterprise;
    ANALYZE public.statistical_unit;
    RAISE DEBUG 'ANALYZE on derived tables complete.';
END;
$procedure$
```
