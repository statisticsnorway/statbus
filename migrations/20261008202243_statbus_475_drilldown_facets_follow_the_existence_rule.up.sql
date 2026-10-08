-- STATBUS-475: the Reports drilldown counts units that EXIST at the selected
-- instant, by the canonical existence rule of STATBUS-460.
--
-- WHY. statistical_unit_facet pre-aggregates statistical_unit by record window
-- (valid_from, valid_to, valid_until) and facet dimensions, and
-- statistical_unit_facet_drilldown selects the rows with
-- valid_from <= valid_on < valid_until. That counted RECORDS whose window covers
-- the instant, so a unit with a record window from 2023-01-01 but born
-- 2024-11-01 (the STATBUS-458 demo rows), or a unit that died inside its
-- window, was counted where the dashboard cards and the Units-over-time chart
-- (both on the existence rule since STATBUS-460) did not count it.
--
-- WHAT. The facet's window is now the unit's EXISTENCE window within the
-- record, [unit_existence_from(valid_from, birth_date),
-- unit_existence_until(valid_until, death_date)), with valid_to = that end
-- minus one day (the inclusive form the table already carries). The
-- drilldown's predicate stays exactly as it is and therefore applies the
-- canonical rule. Records whose life does not overlap their window
-- (existence_from >= existence_until) exist at no instant and are left out.
-- The facet table keeps its shape and its unique key, so the reduce MERGE,
-- the dirty-hash-slot machinery and the drilldown are unchanged.
--
-- Both derivation paths are updated: the worker partition procedure (the
-- production path, hash-partitioned into staging then reduced) and the
-- statistical_unit_facet_def view used by public.statistical_unit_facet_derive.
--
-- REBUILD. The facet rows on an existing box were derived with record windows;
-- they are rebuilt from statistical_unit here, so no box keeps serving the old
-- numbers until its next import. Fresh installs have no rows: no-op.
BEGIN;

CREATE OR REPLACE VIEW public.statistical_unit_facet_def
 WITH (security_invoker='on') AS
 SELECT public.unit_existence_from(valid_from, birth_date) AS valid_from,
    (public.unit_existence_until(valid_until, death_date) - 1) AS valid_to,
    public.unit_existence_until(valid_until, death_date) AS valid_until,
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
    AND public.unit_existence_from(valid_from, birth_date) < public.unit_existence_until(valid_until, death_date)
  GROUP BY (public.unit_existence_from(valid_from, birth_date)), (public.unit_existence_until(valid_until, death_date)), unit_type, physical_region_path, primary_activity_category_path, sector_path, legal_form_id, physical_country_id, status_id;

COMMENT ON VIEW public.statistical_unit_facet_def IS
  'STATBUS-475: facet windows are the unit EXISTENCE window within each record (public.unit_existence_from/until), so the Reports drilldown counts existing units, like the dashboard cards and the Units-over-time chart.';

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

    -- STATBUS-475: aggregate by the unit's EXISTENCE window within each record
    -- (canonical rule, STATBUS-460), not by the record window, so the
    -- drilldown's valid_from <= valid_on < valid_until counts existing units.
    INSERT INTO public.statistical_unit_facet_staging
    SELECT su.hash_slot,
           e.existence_from, e.existence_until - 1, e.existence_until, su.unit_type,
           su.physical_region_path, su.primary_activity_category_path,
           su.sector_path, su.legal_form_id, su.physical_country_id, su.status_id,
           COUNT(*)::integer,
           public.jsonb_stats_merge_agg(su.stats_summary)
    FROM public.statistical_unit AS su
    CROSS JOIN LATERAL (
        SELECT public.unit_existence_from(su.valid_from, su.birth_date) AS existence_from,
               public.unit_existence_until(su.valid_until, su.death_date) AS existence_until
    ) AS e
    WHERE su.used_for_counting
      AND su.hash_slot >= v_from AND su.hash_slot < v_until
      AND e.existence_from < e.existence_until
    GROUP BY su.hash_slot, e.existence_from, e.existence_until, su.unit_type,
             su.physical_region_path, su.primary_activity_category_path,
             su.sector_path, su.legal_form_id, su.physical_country_id, su.status_id;
    GET DIAGNOSTICS v_row_count := ROW_COUNT;
    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$procedure$;

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
