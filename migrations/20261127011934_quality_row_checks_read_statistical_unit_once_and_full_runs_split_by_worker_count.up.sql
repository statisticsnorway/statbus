-- Migration 20261127011934: quality row checks read statistical_unit once, and full runs split by worker count (0pn35h)
--
-- Measured on the Norway copy (3.0 M statistical_unit rows, 2.3 M findings): the view's seven UNION ALL
-- branches each scanned statistical_unit, 86-96 s for a full derive, and 512 partition tasks made a full
-- run 89-182 s against the earlier single task's ~50 s. The four rules that read one statistical_unit row
-- each (missing region, missing activity category, missing physical location, secondary equals primary)
-- now read it in one pass, 4.75 s for their 2.3 M findings; the three comparing a legal unit with its
-- establishments keep their branches. A full run spawns one partition per analytics worker
-- (worker.queue_registry.default_concurrency): 58 s with 4 ranges against 65 s with 8 and 103 s with 16.
-- A partial run keeps the small partitions holding a changed unit.
BEGIN;

CREATE OR REPLACE VIEW public.quality_finding_def
 WITH (security_invoker='on') AS
 SELECT r.rule,
    NULL::integer AS stat_definition_id,
    su.unit_type,
    su.unit_id,
    su.valid_from,
    su.valid_until,
    r.detail,
    su.hash_slot
   FROM statistical_unit su
     CROSS JOIN LATERAL ( VALUES ('missing_region'::quality_rule, su.domestic AND su.physical_country_id IS NOT NULL AND su.physical_region_path IS NULL, NULL::jsonb), ('missing_activity_category'::quality_rule, su.primary_activity_category_path IS NULL, NULL::jsonb), ('missing_physical_location'::quality_rule, su.physical_country_id IS NULL, NULL::jsonb), ('secondary_activity_equals_primary'::quality_rule, su.secondary_activity_category_id = su.primary_activity_category_id, jsonb_build_object('activity_category_id', su.primary_activity_category_id))) r(rule, failed, detail)
  WHERE (su.unit_type = ANY (ARRAY['legal_unit'::statistical_unit_type, 'establishment'::statistical_unit_type])) AND r.failed
UNION ALL
 SELECT 'establishment_activity_differs'::quality_rule AS rule,
    NULL::integer AS stat_definition_id,
    su.unit_type,
    su.unit_id,
    su.valid_from,
    su.valid_until,
    jsonb_build_object('legal_unit_activity_category_id', su.primary_activity_category_id, 'primary_establishment_id', te.unit_id, 'primary_establishment_activity_category_id', te.primary_activity_category_id) AS detail,
    su.hash_slot
   FROM statistical_unit su
     JOIN timeline_establishment te ON te.legal_unit_id = su.unit_id AND te.primary_for_legal_unit AND te.valid_from <= su.valid_from AND su.valid_from < te.valid_until
  WHERE su.unit_type = 'legal_unit'::statistical_unit_type AND su.primary_activity_category_id IS DISTINCT FROM te.primary_activity_category_id
UNION ALL
 SELECT 'establishments_above_legal_unit'::quality_rule AS rule,
    sd.id AS stat_definition_id,
    c.unit_type,
    c.unit_id,
    c.valid_from,
    c.valid_until,
    jsonb_build_object('legal_unit', c.legal_unit_value, 'establishments_sum', c.establishments_sum, 'establishments', c.establishment_count) AS detail,
    c.hash_slot
   FROM legal_unit_establishment_stat_comparison c
     JOIN stat_definition sd ON sd.code::text = c.stat_code::text
  WHERE c.legal_unit_value < c.establishments_sum
UNION ALL
 SELECT 'legal_unit_above_establishments'::quality_rule AS rule,
    sd.id AS stat_definition_id,
    c.unit_type,
    c.unit_id,
    c.valid_from,
    c.valid_until,
    jsonb_build_object('legal_unit', c.legal_unit_value, 'establishments_sum', c.establishments_sum, 'establishments', c.establishment_count) AS detail,
    c.hash_slot
   FROM legal_unit_establishment_stat_comparison c
     JOIN stat_definition sd ON sd.code::text = c.stat_code::text
  WHERE c.establishments_sum < c.legal_unit_value AND c.establishments_with_value = c.establishment_count
;

COMMENT ON VIEW public.quality_finding_def IS
  'The rule of every data-quality check (public.quality_rule), read from the published statistical_unit and the legal unit / establishment comparison; public.quality_finding_derive() makes public.quality_finding equal to it, a hash partition at a time. The rules that read one statistical_unit row share one pass over it (a VALUES row per rule with its test); the rules comparing a legal unit with its establishments are their own branches. Missing region counts only units located in the installation''s own country (domestic): a unit abroad has no region of this country to lack, and a unit without a physical location is missing_physical_location (pkne34). Secondary activity equals primary reads each statistical_unit row, which statistical_unit splits wherever an activity changes, so the row is the period where the two overlap (qjy2eg).';

CREATE OR REPLACE PROCEDURE worker.derive_quality(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_task_id bigint;
    v_hash_partition_size integer := GREATEST(1, 16384 / public.get_partition_count_target());
    -- A full run: one range per analytics worker, so each does one large pass (fewer tasks than the
    -- small partitions, which cost a task's start and commit each).
    v_full_partition_size integer := 16384 / GREATEST(1, (SELECT q.default_concurrency FROM worker.queue_registry AS q WHERE q.queue = 'analytics'));
    v_full boolean;
    v_hash_partition int4range;
    v_child_count integer := 0;
BEGIN
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    -- Every partition on a full recalculation (valid_from -infinity and valid_until infinity, see
    -- worker.enqueue_derive_statistical_unit_all; a full statistical_unit refresh empties
    -- quality_finding). Otherwise the partitions holding a changed unit: the cycle's changed units'
    -- hash slots, recorded by worker.derive_statistical_unit and cleared by
    -- worker.statistical_history_facet_delta_reduce after this step.
    v_full := v_valid_from = '-infinity'::date AND v_valid_until = 'infinity'::date;

    FOR v_hash_partition IN
        SELECT int4range(p.start, LEAST(p.start + v_full_partition_size, 16384))
        FROM generate_series(0, 16383, v_full_partition_size) AS p(start)
        WHERE v_full
        UNION
        SELECT int4range((d.dirty_hash_slot / v_hash_partition_size) * v_hash_partition_size,
                         LEAST((d.dirty_hash_slot / v_hash_partition_size) * v_hash_partition_size + v_hash_partition_size, 16384))
        FROM public.statistical_unit_facet_dirty_hash_slots AS d
        WHERE NOT v_full
        ORDER BY 1
    LOOP
        PERFORM worker.spawn(
            p_command => 'derive_quality_partition',
            p_payload => jsonb_build_object('command', 'derive_quality_partition', 'hash_partition', v_hash_partition::text),
            p_parent_id => v_task_id
        );
        v_child_count := v_child_count + 1;
    END LOOP;

    p_info := jsonb_build_object('child_count', v_child_count, 'full', v_full);
END;
$procedure$
;

COMMENT ON PROCEDURE worker.derive_quality(jsonb, jsonb) IS
  'The reports phase''s quality step, after statistical_unit is published: spawns concurrent derive_quality_partition children, on a full recalculation one hash range per analytics worker (worker.queue_registry.default_concurrency) and otherwise the small partitions holding a changed unit (0pn35h). SECURITY DEFINER like the other derive steps, because its children write RLS-protected tables for whichever role enqueued the recalculation.';

END;
