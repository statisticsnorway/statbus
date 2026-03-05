```sql
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet_partition(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_partition_seq INT := (payload->>'partition_seq')::int;
BEGIN
    RAISE DEBUG 'derive_statistical_unit_facet_partition: partition_seq=%', v_partition_seq;

    -- Delete existing rows for this logical partition (indexed by partition_seq)
    DELETE FROM public.statistical_unit_facet_staging
    WHERE partition_seq = v_partition_seq;

    -- Recompute facets for this partition's units
    INSERT INTO public.statistical_unit_facet_staging
    SELECT v_partition_seq,
           su.valid_from, su.valid_to, su.valid_until, su.unit_type,
           su.physical_region_path, su.primary_activity_category_path,
           su.sector_path, su.legal_form_id, su.physical_country_id, su.status_id,
           COUNT(*)::INT,
           jsonb_stats_merge_agg(su.stats_summary)
    FROM public.statistical_unit AS su
    WHERE su.used_for_counting
      AND su.report_partition_seq = v_partition_seq
    GROUP BY su.valid_from, su.valid_to, su.valid_until, su.unit_type,
             su.physical_region_path, su.primary_activity_category_path,
             su.sector_path, su.legal_form_id, su.physical_country_id, su.status_id;

    RAISE DEBUG 'derive_statistical_unit_facet_partition: partition_seq=% done', v_partition_seq;
END;
$procedure$
```
