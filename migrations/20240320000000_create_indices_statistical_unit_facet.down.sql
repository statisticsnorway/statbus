BEGIN;

DROP INDEX IF EXISTS public.statistical_unit_facet_valid_from;
DROP INDEX IF EXISTS public.statistical_unit_facet_valid_until;
DROP INDEX IF EXISTS public.statistical_unit_facet_unit_type;
DROP INDEX IF EXISTS public.statistical_unit_facet_physical_region_path_btree;
DROP INDEX IF EXISTS public.statistical_unit_facet_physical_region_path_gist;
DROP INDEX IF EXISTS public.statistical_unit_facet_primary_activity_category_path_btree;
DROP INDEX IF EXISTS public.statistical_unit_facet_primary_activity_category_path_gist;
DROP INDEX IF EXISTS public.statistical_unit_facet_sector_path_btree;
DROP INDEX IF EXISTS public.statistical_unit_facet_sector_path_gist;
DROP INDEX IF EXISTS public.statistical_unit_facet_legal_form_id_btree;
DROP INDEX IF EXISTS public.statistical_unit_facet_physical_country_id_btree;

END;
