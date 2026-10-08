-- Down Migration 20261008132050: statbus_472 activity category name bound 512
--
-- Restores character varying(256). Fails honestly with SQLSTATE 22001 if any
-- stored name is longer than 256 characters; shorten those rows first.
BEGIN;

DROP VIEW public.activity_category_enabled;
DROP VIEW public.activity_category_enabled_custom;
DROP VIEW public.activity_category_isic_v4;
DROP VIEW public.activity_category_nace_v2_1;
DROP VIEW public.activity_category_used_def;

ALTER TABLE public.activity_category ALTER COLUMN name TYPE character varying(256);
ALTER TABLE public.activity_category_used ALTER COLUMN name TYPE character varying(256);

CREATE VIEW public.activity_category_enabled WITH (security_invoker = on) AS
 SELECT acs.code AS standard_code,
    ac.id,
    ac.path,
    acp.path AS parent_path,
    ac.code,
    ac.label,
    ac.name,
    ac.description,
    ac.custom
   FROM ((public.activity_category ac
     JOIN public.activity_category_standard acs ON ((ac.standard_id = acs.id)))
     LEFT JOIN public.activity_category acp ON ((ac.parent_id = acp.id)))
  WHERE ((acs.id = ( SELECT settings.activity_category_standard_id
           FROM public.settings)) AND ac.enabled)
  ORDER BY ac.path;

CREATE VIEW public.activity_category_enabled_custom WITH (security_invoker = on) AS
 SELECT path,
    name,
    description
   FROM public.activity_category ac
  WHERE ((standard_id = ( SELECT settings.activity_category_standard_id
           FROM public.settings)) AND enabled AND custom)
  ORDER BY path;

CREATE VIEW public.activity_category_isic_v4 WITH (security_invoker = on) AS
 SELECT acs.code AS standard,
    ac.path,
    ac.label,
    ac.code,
    ac.name,
    ac.description
   FROM (public.activity_category ac
     JOIN public.activity_category_standard acs ON ((ac.standard_id = acs.id)))
  WHERE ((acs.code)::text = 'isic_v4'::text)
  ORDER BY ac.path;

CREATE VIEW public.activity_category_nace_v2_1 WITH (security_invoker = on) AS
 SELECT acs.code AS standard,
    ac.path,
    ac.label,
    ac.code,
    ac.name,
    ac.description
   FROM (public.activity_category ac
     JOIN public.activity_category_standard acs ON ((ac.standard_id = acs.id)))
  WHERE ((acs.code)::text = 'nace_v2.1'::text)
  ORDER BY ac.path;

CREATE VIEW public.activity_category_used_def WITH (security_invoker = on) AS
 SELECT acs.code AS standard_code,
    ac.id,
    ac.path,
    acp.path AS parent_path,
    ac.code,
    ac.label,
    ac.name,
    ac.description
   FROM ((public.activity_category ac
     JOIN public.activity_category_standard acs ON ((ac.standard_id = acs.id)))
     LEFT JOIN public.activity_category acp ON ((ac.parent_id = acp.id)))
  WHERE ((acs.id = ( SELECT settings.activity_category_standard_id
           FROM public.settings)) AND ac.enabled AND ((ac.path OPERATOR(public.@>) ( SELECT array_agg(DISTINCT statistical_unit.primary_activity_category_path) AS array_agg
           FROM public.statistical_unit
          WHERE (statistical_unit.primary_activity_category_path IS NOT NULL))) OR (ac.path OPERATOR(public.@>) ( SELECT array_agg(DISTINCT statistical_unit.secondary_activity_category_path) AS array_agg
           FROM public.statistical_unit
          WHERE (statistical_unit.secondary_activity_category_path IS NOT NULL)))))
  ORDER BY ac.path;

CREATE TRIGGER activity_category_enabled_upsert_custom
INSTEAD OF INSERT ON public.activity_category_enabled
FOR EACH ROW EXECUTE FUNCTION admin.activity_category_enabled_upsert_custom();

CREATE TRIGGER activity_category_enabled_custom_upsert_custom
INSTEAD OF INSERT ON public.activity_category_enabled_custom
FOR EACH ROW EXECUTE FUNCTION admin.activity_category_enabled_custom_upsert_custom();

CREATE TRIGGER upsert_activity_category_isic_v4
INSTEAD OF INSERT ON public.activity_category_isic_v4
FOR EACH ROW EXECUTE FUNCTION admin.upsert_activity_category('isic_v4');

CREATE TRIGGER delete_stale_activity_category_isic_v4
AFTER INSERT ON public.activity_category_isic_v4
FOR EACH STATEMENT EXECUTE FUNCTION admin.delete_stale_activity_category();

CREATE TRIGGER upsert_activity_category_nace_v2_1
INSTEAD OF INSERT ON public.activity_category_nace_v2_1
FOR EACH ROW EXECUTE FUNCTION admin.upsert_activity_category('nace_v2.1');

CREATE TRIGGER delete_stale_activity_category_nace_v2_1
AFTER INSERT ON public.activity_category_nace_v2_1
FOR EACH STATEMENT EXECUTE FUNCTION admin.delete_stale_activity_category();

GRANT SELECT ON public.activity_category_enabled TO authenticated, regular_user, admin_user;
GRANT SELECT, INSERT ON public.activity_category_enabled_custom TO authenticated, regular_user, admin_user;
GRANT SELECT ON public.activity_category_isic_v4 TO authenticated, regular_user, admin_user;
GRANT SELECT ON public.activity_category_nace_v2_1 TO authenticated, regular_user, admin_user;
GRANT SELECT ON public.activity_category_used_def TO authenticated, regular_user, admin_user;

END;
