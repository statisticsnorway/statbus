BEGIN;

CREATE OR REPLACE VIEW public.activity_category_used_def
 WITH (security_invoker='on') AS
 SELECT acs.code AS standard_code,
    ac.id,
    ac.path,
    acp.path AS parent_path,
    ac.code,
    ac.label,
    ac.name,
    ac.description
   FROM activity_category ac
     JOIN activity_category_standard acs ON ac.standard_id = acs.id
     LEFT JOIN activity_category acp ON ac.parent_id = acp.id
  WHERE acs.id = (( SELECT settings.activity_category_standard_id
           FROM settings)) AND ac.enabled AND (ac.path @> (( SELECT array_agg(DISTINCT statistical_unit.primary_activity_category_path) AS array_agg
           FROM statistical_unit
          WHERE statistical_unit.primary_activity_category_path IS NOT NULL)) OR ac.path @> (( SELECT array_agg(DISTINCT statistical_unit.secondary_activity_category_path) AS array_agg
           FROM statistical_unit
          WHERE statistical_unit.secondary_activity_category_path IS NOT NULL)))
  ORDER BY ac.path
;

CREATE OR REPLACE VIEW public.region_used_def
 WITH (security_invoker='on') AS
 SELECT id,
    path,
    level,
    label,
    code,
    name
   FROM region r
  WHERE path @> (( SELECT array_agg(DISTINCT statistical_unit.physical_region_path) AS array_agg
           FROM statistical_unit
          WHERE statistical_unit.physical_region_path IS NOT NULL))
  ORDER BY (nlevel(path)), path
;

CREATE OR REPLACE VIEW public.sector_used_def
 WITH (security_invoker='on') AS
 SELECT id,
    path,
    label,
    code,
    name
   FROM sector s
  WHERE path @> (( SELECT array_agg(DISTINCT statistical_unit.sector_path) AS array_agg
           FROM statistical_unit
          WHERE statistical_unit.sector_path IS NOT NULL)) AND enabled
  ORDER BY path
;

END;
