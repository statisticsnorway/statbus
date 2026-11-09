BEGIN;

-- The used-code views list classification codes that some statistical unit uses.
-- statistical_unit has millions of rows but few distinct paths, so each view
-- walks the column's btree index one distinct path at a time (a skip scan)
-- instead of aggregating every row.
CREATE OR REPLACE VIEW public.activity_category_used_def
 WITH (security_invoker='on') AS
 WITH RECURSIVE primary_path(path) AS (
         ( SELECT statistical_unit.primary_activity_category_path
           FROM statistical_unit
          WHERE statistical_unit.primary_activity_category_path IS NOT NULL
          ORDER BY statistical_unit.primary_activity_category_path
         LIMIT 1)
        UNION ALL
         SELECT ( SELECT statistical_unit.primary_activity_category_path
                   FROM statistical_unit
                  WHERE statistical_unit.primary_activity_category_path > primary_path.path
                  ORDER BY statistical_unit.primary_activity_category_path
                 LIMIT 1) AS path
           FROM primary_path
          WHERE primary_path.path IS NOT NULL
        ), secondary_path(path) AS (
         ( SELECT statistical_unit.secondary_activity_category_path
           FROM statistical_unit
          WHERE statistical_unit.secondary_activity_category_path IS NOT NULL
          ORDER BY statistical_unit.secondary_activity_category_path
         LIMIT 1)
        UNION ALL
         SELECT ( SELECT statistical_unit.secondary_activity_category_path
                   FROM statistical_unit
                  WHERE statistical_unit.secondary_activity_category_path > secondary_path.path
                  ORDER BY statistical_unit.secondary_activity_category_path
                 LIMIT 1) AS path
           FROM secondary_path
          WHERE secondary_path.path IS NOT NULL
        )
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
           FROM settings)) AND ac.enabled AND (ac.path @> (( SELECT array_agg(primary_path.path) AS array_agg
           FROM primary_path
          WHERE primary_path.path IS NOT NULL)) OR ac.path @> (( SELECT array_agg(secondary_path.path) AS array_agg
           FROM secondary_path
          WHERE secondary_path.path IS NOT NULL)))
  ORDER BY ac.path;

CREATE OR REPLACE VIEW public.region_used_def
 WITH (security_invoker='on') AS
 WITH RECURSIVE used_path(path) AS (
         ( SELECT statistical_unit.physical_region_path
           FROM statistical_unit
          WHERE statistical_unit.physical_region_path IS NOT NULL
          ORDER BY statistical_unit.physical_region_path
         LIMIT 1)
        UNION ALL
         SELECT ( SELECT statistical_unit.physical_region_path
                   FROM statistical_unit
                  WHERE statistical_unit.physical_region_path > used_path.path
                  ORDER BY statistical_unit.physical_region_path
                 LIMIT 1) AS path
           FROM used_path
          WHERE used_path.path IS NOT NULL
        )
 SELECT id,
    path,
    level,
    label,
    code,
    name
   FROM region r
  WHERE path @> (( SELECT array_agg(used_path.path) AS array_agg
           FROM used_path
          WHERE used_path.path IS NOT NULL))
  ORDER BY (nlevel(path)), path;

CREATE OR REPLACE VIEW public.sector_used_def
 WITH (security_invoker='on') AS
 WITH RECURSIVE used_path(path) AS (
         ( SELECT statistical_unit.sector_path
           FROM statistical_unit
          WHERE statistical_unit.sector_path IS NOT NULL
          ORDER BY statistical_unit.sector_path
         LIMIT 1)
        UNION ALL
         SELECT ( SELECT statistical_unit.sector_path
                   FROM statistical_unit
                  WHERE statistical_unit.sector_path > used_path.path
                  ORDER BY statistical_unit.sector_path
                 LIMIT 1) AS path
           FROM used_path
          WHERE used_path.path IS NOT NULL
        )
 SELECT id,
    path,
    label,
    code,
    name
   FROM sector s
  WHERE path @> (( SELECT array_agg(used_path.path) AS array_agg
           FROM used_path
          WHERE used_path.path IS NOT NULL)) AND enabled
  ORDER BY path;

END;
