-- Migration 20261008132050: statbus_472 activity category name bound 512
--
-- STATBUS-472. Double activity_category.name from character varying(256) to
-- character varying(512), the interim workaround until multi-language
-- category names are modelled properly (deferred, see the ticket notes).
--
-- Why 512: real field labels reach 252 characters (a bilingual Turkish +
-- English file of 997 rows that the operator had already hand-trimmed to fit
-- 256), while the longest single-language official label we ship is 136
-- (ISIC4) / 139 (NACE 2.1). In PostgreSQL a varchar(n) bound is a length
-- check, not a storage layout, so raising it costs nothing in row size.
-- Above 512 the insert still fails honestly with SQLSTATE 22001
-- (value too long for type character varying(512)).
-- The bound and its evidence are documented in doc/text-length-bounds.md.
--
-- Dependents found (inventory taken from pg_depend on a seed at HEAD):
--   * Five views select activity_category.name and expose it as
--     varchar(256), so PostgreSQL refuses ALTER COLUMN TYPE while they exist:
--     activity_category_enabled, activity_category_enabled_custom,
--     activity_category_isic_v4, activity_category_nace_v2_1,
--     activity_category_used_def. They are dropped and recreated with their
--     exact current definitions (pg_get_viewdef), options, INSTEAD OF /
--     statement triggers and grants. Their name column then follows the
--     table and becomes varchar(512).
--   * public.activity_category_used is a TABLE derived from
--     activity_category_used_def by MERGE; its own name varchar(256) would
--     reject a long label at derive time, so it is widened too.
--   * timeline_establishment_def / timeline_legal_unit_def depend on
--     activity_category but only on id, path and code, never on name, so they
--     are untouched.
--   * The trigger functions admin.upsert_activity_category,
--     admin.activity_category_enabled_upsert_custom,
--     admin.activity_category_enabled_custom_upsert_custom and
--     public.activity_category_used_derive copy NEW.name / source.name
--     without any varchar(256) cast; no function body in the database
--     contains a varchar(256) cast. Nothing to change there.
BEGIN;

DROP VIEW public.activity_category_enabled;
DROP VIEW public.activity_category_enabled_custom;
DROP VIEW public.activity_category_isic_v4;
DROP VIEW public.activity_category_nace_v2_1;
DROP VIEW public.activity_category_used_def;

ALTER TABLE public.activity_category ALTER COLUMN name TYPE character varying(512);
ALTER TABLE public.activity_category_used ALTER COLUMN name TYPE character varying(512);

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
