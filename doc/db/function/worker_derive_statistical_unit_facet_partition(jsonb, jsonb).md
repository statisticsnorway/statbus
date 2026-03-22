```sql
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet_partition(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    -- Support both single partition_seq (legacy/backward compat) and range
    v_partition_seq_from INT := COALESCE(
        (payload->>'partition_seq_from')::int,
        (payload->>'partition_seq')::int
    );
    v_partition_seq_to INT := COALESCE(
        (payload->>'partition_seq_to')::int,
        (payload->>'partition_seq')::int
    );
    v_row_count bigint;
BEGIN
    RAISE DEBUG 'derive_statistical_unit_facet_partition: partition_seq_from=%, partition_seq_to=%',
        v_partition_seq_from, v_partition_seq_to;

    DELETE FROM public.statistical_unit_facet_staging
    WHERE partition_seq BETWEEN v_partition_seq_from AND v_partition_seq_to;

    INSERT INTO public.statistical_unit_facet_staging
    SELECT su.report_partition_seq,
           su.valid_from, su.valid_to, su.valid_until, su.unit_type,
           su.physical_region_path, su.primary_activity_category_path,
           su.sector_path, su.legal_form_id, su.physical_country_id, su.status_id,
           COUNT(*)::INT,
           jsonb_stats_merge_agg(su.stats_summary)
    FROM public.statistical_unit AS su
    WHERE su.used_for_counting
      AND su.report_partition_seq BETWEEN v_partition_seq_from AND v_partition_seq_to
    GROUP BY su.report_partition_seq, su.valid_from, su.valid_to, su.valid_until, su.unit_type,
             su.physical_region_path, su.primary_activity_category_path,
             su.sector_path, su.legal_form_id, su.physical_country_id, su.status_id;
    GET DIAGNOSTICS v_row_count := ROW_COUNT;

    RAISE DEBUG 'derive_statistical_unit_facet_partition: range [%, %] done, % rows',
        v_partition_seq_from, v_partition_seq_to, v_row_count;

    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$procedure$
```
