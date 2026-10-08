-- Down for STATBUS-475: restore the record-window facet derivation verbatim (\sv/\sf dumps), then rebuild.
BEGIN;

CREATE OR REPLACE VIEW public.statistical_unit_facet_def
 WITH (security_invoker='on') AS
 SELECT valid_from,
    valid_to,
    valid_until,
    unit_type,
    physical_region_path,
    primary_activity_category_path,
    sector_path,
    legal_form_id,
    physical_country_id,
    status_id,
    count(*) AS count,
    jsonb_stats_merge_agg(stats_summary) AS stats_summary
   FROM statistical_unit
  WHERE used_for_counting
  GROUP BY valid_from, valid_to, valid_until, unit_type, physical_region_path, primary_activity_category_path, sector_path, legal_form_id, physical_country_id, status_id
;

COMMENT ON VIEW public.statistical_unit_facet_def IS NULL;

CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet_partition(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_hash_partition int4range := (payload->>'hash_partition')::int4range;
    -- Pre-compute explicit half-open bounds so the btree index on hash_slot is
    -- used. Range containment (<@) via a variable int4range is not planned as a
    -- btree scan at 2.2M rows; explicit bounds are. Mirrors the sibling
    -- derive_statistical_history_facet_period which passes scalar bounds.
    v_from  integer := lower(v_hash_partition);
    v_until integer := upper(v_hash_partition);
    v_row_count bigint;
BEGIN
    DELETE FROM public.statistical_unit_facet_staging
     WHERE hash_slot >= v_from AND hash_slot < v_until;

    INSERT INTO public.statistical_unit_facet_staging
    SELECT su.hash_slot,
           su.valid_from, su.valid_to, su.valid_until, su.unit_type,
           su.physical_region_path, su.primary_activity_category_path,
           su.sector_path, su.legal_form_id, su.physical_country_id, su.status_id,
           COUNT(*)::integer,
           public.jsonb_stats_merge_agg(su.stats_summary)
    FROM public.statistical_unit AS su
    WHERE su.used_for_counting
      AND su.hash_slot >= v_from AND su.hash_slot < v_until
    GROUP BY su.hash_slot, su.valid_from, su.valid_to, su.valid_until, su.unit_type,
             su.physical_region_path, su.primary_activity_category_path,
             su.sector_path, su.legal_form_id, su.physical_country_id, su.status_id;
    GET DIAGNOSTICS v_row_count := ROW_COUNT;
    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$procedure$
;

-- REBUILD existing facet rows under the new windows: a full derive (every hash
-- partition) followed by the reduce, exactly what collect_changes schedules
-- after an import. Staging is emptied first so derive_statistical_unit_facet
-- takes its full-rebuild branch.
DO $statbus_475_rebuild_facets$
BEGIN
    IF EXISTS (SELECT 1 FROM public.statistical_unit LIMIT 1) THEN
        TRUNCATE public.statistical_unit_facet_staging;
        PERFORM worker.spawn(
            p_command => 'collect_changes',
            p_payload => jsonb_build_object(
                'establishment_id_ranges', NULL,
                'legal_unit_id_ranges',    NULL,
                'enterprise_id_ranges',    NULL,
                'power_group_id_ranges',   NULL,
                'valid_ranges',            NULL
            )
        );
        PERFORM pg_notify('worker_tasks', 'analytics');
    END IF;
END;
$statbus_475_rebuild_facets$;

END;
