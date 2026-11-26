-- Down Migration 20261126202816: the view without the secondary-equals-primary branch, and the rule's
-- findings and switches gone. CREATE OR REPLACE cannot remove a UNION branch, so the view is dropped
-- and created as 20261124212002 left it; only quality_finding_derive() reads it, at call time.
BEGIN;

DELETE FROM public.quality_finding WHERE rule = 'secondary_activity_equals_primary';
DELETE FROM public.quality_check_switched_off WHERE rule = 'secondary_activity_equals_primary';
DROP VIEW public.quality_finding_def;
CREATE VIEW public.quality_finding_def
WITH (security_invoker = on) AS
SELECT 'missing_region'::public.quality_rule AS rule,
       NULL::integer AS stat_definition_id,
       su.unit_type, su.unit_id, su.valid_from, su.valid_until,
       NULL::jsonb AS detail
FROM public.statistical_unit AS su
WHERE su.unit_type IN ('legal_unit', 'establishment')
  AND su.domestic
  AND su.physical_country_id IS NOT NULL
  AND su.physical_region_path IS NULL
UNION ALL
SELECT 'missing_activity_category', NULL, su.unit_type, su.unit_id, su.valid_from, su.valid_until, NULL
FROM public.statistical_unit AS su
WHERE su.unit_type IN ('legal_unit', 'establishment')
  AND su.primary_activity_category_path IS NULL
UNION ALL
SELECT 'missing_physical_location', NULL, su.unit_type, su.unit_id, su.valid_from, su.valid_until, NULL
FROM public.statistical_unit AS su
WHERE su.unit_type IN ('legal_unit', 'establishment')
  AND su.physical_country_id IS NULL
UNION ALL
SELECT 'establishment_activity_differs', NULL, su.unit_type, su.unit_id, su.valid_from, su.valid_until,
       jsonb_build_object(
           'legal_unit_activity_category_id', su.primary_activity_category_id,
           'primary_establishment_id', te.unit_id,
           'primary_establishment_activity_category_id', te.primary_activity_category_id)
FROM public.statistical_unit AS su
JOIN public.timeline_establishment AS te
  ON te.legal_unit_id = su.unit_id
 AND te.primary_for_legal_unit
 AND te.valid_from <= su.valid_from AND su.valid_from < te.valid_until
WHERE su.unit_type = 'legal_unit'
  AND su.primary_activity_category_id IS DISTINCT FROM te.primary_activity_category_id
UNION ALL
SELECT 'establishments_above_legal_unit', sd.id, c.unit_type, c.unit_id, c.valid_from, c.valid_until,
       jsonb_build_object('legal_unit', c.legal_unit_value,
                          'establishments_sum', c.establishments_sum,
                          'establishments', c.establishment_count)
FROM public.legal_unit_establishment_stat_comparison AS c
JOIN public.stat_definition AS sd ON sd.code = c.stat_code
WHERE c.legal_unit_value < c.establishments_sum
UNION ALL
SELECT 'legal_unit_above_establishments', sd.id, c.unit_type, c.unit_id, c.valid_from, c.valid_until,
       jsonb_build_object('legal_unit', c.legal_unit_value,
                          'establishments_sum', c.establishments_sum,
                          'establishments', c.establishment_count)
FROM public.legal_unit_establishment_stat_comparison AS c
JOIN public.stat_definition AS sd ON sd.code = c.stat_code
WHERE c.establishments_sum < c.legal_unit_value
  AND c.establishments_with_value = c.establishment_count;

COMMENT ON VIEW public.quality_finding_def IS
  'The rule of every data-quality check (public.quality_rule), read from the published statistical_unit and the legal unit / establishment comparison; public.quality_finding_derive() makes public.quality_finding equal to it. Missing region counts only units located in the installation''s own country (domestic): a unit abroad has no region of this country to lack, and a unit without a physical location is missing_physical_location (pkne34).';
GRANT SELECT ON public.quality_finding_def TO authenticated, regular_user, admin_user;

END;
