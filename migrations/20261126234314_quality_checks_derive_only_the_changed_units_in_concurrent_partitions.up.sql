-- Migration 20261126234314: quality checks derive only the changed units in concurrent partitions (0pn35h)
--
-- A one-unit edit on Norway spent 2m32s in derive_quality, which rederived every finding of every
-- unit in one serial task. The checks now work by hash partition, as the search facets do
-- (worker.derive_statistical_unit_facet): worker.derive_quality spawns one concurrent
-- derive_quality_partition child per partition range, every range on a full recalculation and only
-- the ranges holding a changed unit (public.statistical_unit_facet_dirty_hash_slots) otherwise.
--
-- The rules stay one definition, public.quality_finding_def; it and the comparison view it reads
-- carry each row's hash_slot, so a range filter reaches every rule's index scan. public.quality_finding
-- carries hash_slot too, so a partition replaces exactly its own findings.
BEGIN;

-- The comparison, with the legal unit's hash_slot: grouped by it, so a filter on the slot reaches the
-- scan of statistical_unit (idx_statistical_unit_hash_slot) instead of grouping every legal unit.
CREATE OR REPLACE VIEW public.legal_unit_establishment_stat_comparison
 WITH (security_invoker='on') AS
 WITH establishment_values AS (
         SELECT su_1.hash_slot,
            su_1.unit_id,
            su_1.valid_from,
            sd.code AS stat_code,
            count(*) AS establishment_count,
            count(te.stats -> sd.code::text) AS establishments_with_value,
            sum(((te.stats -> sd.code::text) ->> 'value'::text)::numeric) AS establishments_sum
           FROM statistical_unit su_1
             JOIN timeline_establishment te ON te.legal_unit_id = su_1.unit_id AND te.used_for_counting AND te.valid_from <= su_1.valid_from AND su_1.valid_from < te.valid_until
             JOIN stat_definition sd ON sd.enabled AND (sd.type = ANY (ARRAY['int'::stat_type, 'float'::stat_type]))
          WHERE su_1.unit_type = 'legal_unit'::statistical_unit_type AND su_1.stats ? sd.code::text
          GROUP BY su_1.hash_slot, su_1.unit_id, su_1.valid_from, sd.code
        )
 SELECT su.unit_type,
    su.unit_id,
    su.valid_from,
    su.valid_until,
    ev.stat_code,
    ((su.stats -> ev.stat_code::text) ->> 'value'::text)::numeric AS legal_unit_value,
    ev.establishment_count,
    ev.establishments_with_value,
    ev.establishments_sum,
    ev.hash_slot
   FROM statistical_unit su
     JOIN establishment_values ev ON ev.hash_slot = su.hash_slot AND ev.unit_id = su.unit_id AND ev.valid_from = su.valid_from
  WHERE su.unit_type = 'legal_unit'::statistical_unit_type AND ev.establishments_with_value > 0;

COMMENT ON COLUMN public.legal_unit_establishment_stat_comparison.hash_slot IS
  'The legal unit''s public.hash_slot, the partition key of public.quality_finding_derive(): a filter on it reaches the scan of statistical_unit (0pn35h).';

CREATE OR REPLACE VIEW public.quality_finding_def
 WITH (security_invoker='on') AS
 SELECT 'missing_region'::quality_rule AS rule,
    NULL::integer AS stat_definition_id,
    su.unit_type,
    su.unit_id,
    su.valid_from,
    su.valid_until,
    NULL::jsonb AS detail,
    su.hash_slot
   FROM statistical_unit su
  WHERE (su.unit_type = ANY (ARRAY['legal_unit'::statistical_unit_type, 'establishment'::statistical_unit_type])) AND su.domestic AND su.physical_country_id IS NOT NULL AND su.physical_region_path IS NULL
UNION ALL
 SELECT 'missing_activity_category'::quality_rule AS rule,
    NULL::integer AS stat_definition_id,
    su.unit_type,
    su.unit_id,
    su.valid_from,
    su.valid_until,
    NULL::jsonb AS detail,
    su.hash_slot
   FROM statistical_unit su
  WHERE (su.unit_type = ANY (ARRAY['legal_unit'::statistical_unit_type, 'establishment'::statistical_unit_type])) AND su.primary_activity_category_path IS NULL
UNION ALL
 SELECT 'missing_physical_location'::quality_rule AS rule,
    NULL::integer AS stat_definition_id,
    su.unit_type,
    su.unit_id,
    su.valid_from,
    su.valid_until,
    NULL::jsonb AS detail,
    su.hash_slot
   FROM statistical_unit su
  WHERE (su.unit_type = ANY (ARRAY['legal_unit'::statistical_unit_type, 'establishment'::statistical_unit_type])) AND su.physical_country_id IS NULL
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
UNION ALL
 SELECT 'secondary_activity_equals_primary'::quality_rule AS rule,
    NULL::integer AS stat_definition_id,
    su.unit_type,
    su.unit_id,
    su.valid_from,
    su.valid_until,
    jsonb_build_object('activity_category_id', su.primary_activity_category_id) AS detail,
    su.hash_slot
   FROM statistical_unit su
  WHERE (su.unit_type = ANY (ARRAY['legal_unit'::statistical_unit_type, 'establishment'::statistical_unit_type])) AND su.secondary_activity_category_id = su.primary_activity_category_id;

COMMENT ON VIEW public.quality_finding_def IS
  'The rule of every data-quality check (public.quality_rule), read from the published statistical_unit and the legal unit / establishment comparison; public.quality_finding_derive() makes public.quality_finding equal to it, a hash partition at a time. Missing region counts only units located in the installation''s own country (domestic): a unit abroad has no region of this country to lack, and a unit without a physical location is missing_physical_location (pkne34). Secondary activity equals primary reads each statistical_unit row, which statistical_unit splits wherever an activity changes, so the row is the period where the two overlap (qjy2eg).';
COMMENT ON COLUMN public.quality_finding_def.hash_slot IS
  'The unit''s public.hash_slot: public.quality_finding_derive() filters on it to rederive one partition (0pn35h).';

-- A finding's partition, the key a partition's derive replaces its findings by.
ALTER TABLE public.quality_finding
  ADD COLUMN hash_slot integer GENERATED ALWAYS AS (public.hash_slot(unit_type, unit_id)) STORED;
CREATE INDEX quality_finding_hash_slot_idx ON public.quality_finding (hash_slot);
COMMENT ON COLUMN public.quality_finding.hash_slot IS
  'The unit''s public.hash_slot, the partition public.quality_finding_derive() rederives the finding in (0pn35h).';

DROP FUNCTION public.quality_finding_derive();
CREATE FUNCTION public.quality_finding_derive(p_hash_slots int4range)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $quality_finding_derive$
DECLARE
    -- Explicit half-open bounds, so the btree indexes on hash_slot are used (as in
    -- worker.derive_statistical_unit_facet_partition).
    v_from integer := lower(p_hash_slots);
    v_until integer := upper(p_hash_slots);
    v_findings jsonb;
BEGIN
    DELETE FROM public.quality_finding
     WHERE hash_slot >= v_from AND hash_slot < v_until;

    WITH inserted AS (
        INSERT INTO public.quality_finding
            (rule, stat_definition_id, unit_type, unit_id, valid_from, valid_until, existence_from, existence_until, detail)
        SELECT d.rule, d.stat_definition_id, d.unit_type, d.unit_id, d.valid_from, d.valid_until,
               public.unit_existence_from(su.valid_from, su.birth_date),
               public.unit_existence_until(su.valid_until, su.death_date),
               d.detail
        FROM public.quality_finding_def AS d
        JOIN public.statistical_unit AS su
          ON su.unit_type = d.unit_type AND su.unit_id = d.unit_id
         AND su.valid_range = daterange(d.valid_from, d.valid_until)
         AND su.hash_slot >= v_from AND su.hash_slot < v_until
        WHERE d.hash_slot >= v_from AND d.hash_slot < v_until
        RETURNING rule, stat_definition_id
    )
    SELECT jsonb_object_agg(k.check_key, k.findings) INTO v_findings
    FROM (
        SELECT CASE WHEN sd.code IS NULL THEN i.rule::text ELSE i.rule::text || ':' || sd.code END AS check_key,
               count(*) AS findings
        FROM inserted AS i
        LEFT JOIN public.stat_definition AS sd ON sd.id = i.stat_definition_id
        GROUP BY 1
    ) AS k;
    RETURN COALESCE(v_findings, '{}'::jsonb);
END;
$quality_finding_derive$;

COMMENT ON FUNCTION public.quality_finding_derive(int4range) IS
  'Makes public.quality_finding equal to public.quality_finding_def for the units whose hash_slot is in p_hash_slots, with each finding''s existence dates from its statistical_unit row. Returns the findings per check, keyed by the check''s ?quality= value (rule, or rule:variable code). Called per partition by worker.derive_quality_partition (0pn35h); public.quality_finding_derive() does every slot.';

CREATE FUNCTION public.quality_finding_derive()
 RETURNS jsonb
 LANGUAGE sql
AS $quality_finding_derive_all$
    SELECT public.quality_finding_derive(int4range(0, 16384));
$quality_finding_derive_all$;

COMMENT ON FUNCTION public.quality_finding_derive() IS
  'public.quality_finding_derive(int4range) over every hash slot (public.hash_slot is 0 to 16383): all findings in one transaction, for tests and repairs; the worker derives a partition per task.';

-- The reports phase's quality step: spawns the partitions to rederive, as derive_statistical_unit_facet does.
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
        SELECT int4range(p.start, LEAST(p.start + v_hash_partition_size, 16384))
        FROM generate_series(0, 16383, v_hash_partition_size) AS p(start)
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
$procedure$;

COMMENT ON PROCEDURE worker.derive_quality(jsonb, jsonb) IS
  'The reports phase''s quality step, after statistical_unit is published: spawns one concurrent derive_quality_partition per hash partition to rederive, every partition on a full recalculation and the partitions holding a changed unit otherwise (0pn35h). SECURITY DEFINER like the other derive steps, because its children write RLS-protected tables for whichever role enqueued the recalculation.';

CREATE PROCEDURE worker.derive_quality_partition(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
BEGIN
    -- The findings per check in this partition, one number per check, so the parent's info sums
    -- them over its children (worker.complete_parent_if_ready).
    p_info := public.quality_finding_derive((payload->>'hash_partition')::int4range);
END;
$procedure$;

COMMENT ON PROCEDURE worker.derive_quality_partition(jsonb, jsonb) IS
  'A child of worker.derive_quality: rederives the quality findings of one hash partition (public.quality_finding_derive), concurrently with its siblings (0pn35h). SECURITY DEFINER: it writes the RLS-protected public.quality_finding.';

INSERT INTO worker.command_registry (command, handler_procedure, description, queue)
VALUES ('derive_quality_partition', 'worker.derive_quality_partition',
        'Rederive the quality findings of one hash partition (parallel-safe, child task)', 'analytics');

UPDATE worker.command_registry
   SET description = 'Run the quality checks (public.quality_finding_def) on the changed partitions of the published statistical_unit'
 WHERE command = 'derive_quality';

END;
