-- Down Migration 20261126234314: the quality step rederives every unit in one serial task again.
-- The views lose their hash_slot column, which CREATE OR REPLACE cannot drop, so both are dropped and
-- created as 20261126202816 left them; only public.quality_finding_derive() reads them, at call time.
BEGIN;

DELETE FROM worker.tasks WHERE command = 'derive_quality_partition';
DELETE FROM worker.command_registry WHERE command = 'derive_quality_partition';
UPDATE worker.command_registry
   SET description = 'Run every quality check (public.quality_*) on the published statistical_unit'
 WHERE command = 'derive_quality';
DROP PROCEDURE worker.derive_quality_partition(jsonb, jsonb);

DROP FUNCTION public.quality_finding_derive();
DROP FUNCTION public.quality_finding_derive(int4range);
DROP INDEX public.quality_finding_hash_slot_idx;
ALTER TABLE public.quality_finding DROP COLUMN hash_slot;

DROP VIEW public.quality_finding_def;
DROP VIEW public.legal_unit_establishment_stat_comparison;

CREATE VIEW public.legal_unit_establishment_stat_comparison
 WITH (security_invoker='on') AS
 WITH establishment_values AS (
         SELECT su_1.unit_id,
            su_1.valid_from,
            sd.code AS stat_code,
            count(*) AS establishment_count,
            count(te.stats -> sd.code::text) AS establishments_with_value,
            sum(((te.stats -> sd.code::text) ->> 'value'::text)::numeric) AS establishments_sum
           FROM statistical_unit su_1
             JOIN timeline_establishment te ON te.legal_unit_id = su_1.unit_id AND te.used_for_counting AND te.valid_from <= su_1.valid_from AND su_1.valid_from < te.valid_until
             JOIN stat_definition sd ON sd.enabled AND (sd.type = ANY (ARRAY['int'::stat_type, 'float'::stat_type]))
          WHERE su_1.unit_type = 'legal_unit'::statistical_unit_type AND su_1.stats ? sd.code::text
          GROUP BY su_1.unit_id, su_1.valid_from, sd.code
        )
 SELECT su.unit_type,
    su.unit_id,
    su.valid_from,
    su.valid_until,
    ev.stat_code,
    ((su.stats -> ev.stat_code::text) ->> 'value'::text)::numeric AS legal_unit_value,
    ev.establishment_count,
    ev.establishments_with_value,
    ev.establishments_sum
   FROM statistical_unit su
     JOIN establishment_values ev ON ev.unit_id = su.unit_id AND ev.valid_from = su.valid_from
  WHERE su.unit_type = 'legal_unit'::statistical_unit_type AND ev.establishments_with_value > 0
;

COMMENT ON VIEW public.legal_unit_establishment_stat_comparison IS
  'Per legal_unit row of statistical_unit and enabled summed stat (int, float) held both by the legal unit and by at least one counted establishment: the legal unit''s own value (statistical_unit.stats) and its counted establishments'' count, count with a value, and sum at the row''s valid_from. The quality rules establishments_above_legal_unit and legal_unit_above_establishments read it (public.quality_finding_def); a legal unit''s total takes the larger level (public.jsonb_stats_covers).';
GRANT SELECT ON public.legal_unit_establishment_stat_comparison TO authenticated, regular_user, admin_user;

CREATE VIEW public.quality_finding_def
 WITH (security_invoker='on') AS
 SELECT 'missing_region'::quality_rule AS rule,
    NULL::integer AS stat_definition_id,
    su.unit_type,
    su.unit_id,
    su.valid_from,
    su.valid_until,
    NULL::jsonb AS detail
   FROM statistical_unit su
  WHERE (su.unit_type = ANY (ARRAY['legal_unit'::statistical_unit_type, 'establishment'::statistical_unit_type])) AND su.domestic AND su.physical_country_id IS NOT NULL AND su.physical_region_path IS NULL
UNION ALL
 SELECT 'missing_activity_category'::quality_rule AS rule,
    NULL::integer AS stat_definition_id,
    su.unit_type,
    su.unit_id,
    su.valid_from,
    su.valid_until,
    NULL::jsonb AS detail
   FROM statistical_unit su
  WHERE (su.unit_type = ANY (ARRAY['legal_unit'::statistical_unit_type, 'establishment'::statistical_unit_type])) AND su.primary_activity_category_path IS NULL
UNION ALL
 SELECT 'missing_physical_location'::quality_rule AS rule,
    NULL::integer AS stat_definition_id,
    su.unit_type,
    su.unit_id,
    su.valid_from,
    su.valid_until,
    NULL::jsonb AS detail
   FROM statistical_unit su
  WHERE (su.unit_type = ANY (ARRAY['legal_unit'::statistical_unit_type, 'establishment'::statistical_unit_type])) AND su.physical_country_id IS NULL
UNION ALL
 SELECT 'establishment_activity_differs'::quality_rule AS rule,
    NULL::integer AS stat_definition_id,
    su.unit_type,
    su.unit_id,
    su.valid_from,
    su.valid_until,
    jsonb_build_object('legal_unit_activity_category_id', su.primary_activity_category_id, 'primary_establishment_id', te.unit_id, 'primary_establishment_activity_category_id', te.primary_activity_category_id) AS detail
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
    jsonb_build_object('legal_unit', c.legal_unit_value, 'establishments_sum', c.establishments_sum, 'establishments', c.establishment_count) AS detail
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
    jsonb_build_object('legal_unit', c.legal_unit_value, 'establishments_sum', c.establishments_sum, 'establishments', c.establishment_count) AS detail
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
    jsonb_build_object('activity_category_id', su.primary_activity_category_id) AS detail
   FROM statistical_unit su
  WHERE (su.unit_type = ANY (ARRAY['legal_unit'::statistical_unit_type, 'establishment'::statistical_unit_type])) AND su.secondary_activity_category_id = su.primary_activity_category_id
;

COMMENT ON VIEW public.quality_finding_def IS
  'The rule of every data-quality check (public.quality_rule), read from the published statistical_unit and the legal unit / establishment comparison; public.quality_finding_derive() makes public.quality_finding equal to it. Missing region counts only units located in the installation''s own country (domestic): a unit abroad has no region of this country to lack, and a unit without a physical location is missing_physical_location (pkne34). Secondary activity equals primary reads each statistical_unit row, which statistical_unit splits wherever an activity changes, so the row is the period where the two overlap (qjy2eg).';
GRANT SELECT ON public.quality_finding_def TO authenticated, regular_user, admin_user;

CREATE FUNCTION public.quality_finding_derive()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE DEBUG 'Running quality_finding_derive()';
    MERGE INTO public.quality_finding AS target
    USING (
        SELECT d.rule, d.stat_definition_id, d.unit_type, d.unit_id, d.valid_from, d.valid_until, d.detail,
               public.unit_existence_from(su.valid_from, su.birth_date) AS existence_from,
               public.unit_existence_until(su.valid_until, su.death_date) AS existence_until
        FROM public.quality_finding_def AS d
        JOIN public.statistical_unit AS su
          ON su.unit_type = d.unit_type AND su.unit_id = d.unit_id
         AND su.valid_range = daterange(d.valid_from, d.valid_until)
    ) AS source
    ON target.rule = source.rule
   AND COALESCE(target.stat_definition_id, 0) = COALESCE(source.stat_definition_id, 0)
   AND target.unit_type = source.unit_type
   AND target.unit_id = source.unit_id
   AND target.valid_range = daterange(source.valid_from, source.valid_until)
    WHEN MATCHED AND (target.detail IS DISTINCT FROM source.detail
                      OR target.existence_from IS DISTINCT FROM source.existence_from
                      OR target.existence_until IS DISTINCT FROM source.existence_until) THEN
        UPDATE SET detail = source.detail,
                   existence_from = source.existence_from,
                   existence_until = source.existence_until
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (rule, stat_definition_id, unit_type, unit_id, valid_from, valid_until, existence_from, existence_until, detail)
        VALUES (source.rule, source.stat_definition_id, source.unit_type, source.unit_id, source.valid_from,
                source.valid_until, source.existence_from, source.existence_until, source.detail)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
    ANALYZE public.quality_finding;
END;
$function$
;

COMMENT ON FUNCTION public.quality_finding_derive() IS
  'Makes public.quality_finding equal to public.quality_finding_def (insert, update, delete), with each finding''s existence dates from its statistical_unit row; called by worker.derive_quality.';

CREATE OR REPLACE PROCEDURE worker.derive_quality(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
BEGIN
    PERFORM public.quality_finding_derive();

    p_info := (
        SELECT jsonb_build_object('findings', jsonb_object_agg(f.rule, f.findings))
        FROM (SELECT qf.rule, count(*) AS findings FROM public.quality_finding AS qf GROUP BY qf.rule) AS f
    );
END;
$procedure$
;

COMMENT ON PROCEDURE worker.derive_quality(jsonb, jsonb) IS
  'The reports phase''s quality step: runs every quality check (public.quality_<check>_derive()) after statistical_unit is published. SECURITY DEFINER like the other derive steps, because it writes RLS-protected tables for whichever role enqueued the recalculation.';

END;
