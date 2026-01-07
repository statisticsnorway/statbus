BEGIN;

DROP FUNCTION IF EXISTS public.physical_region(public.statistical_unit);
DROP FUNCTION IF EXISTS public.postal_region(public.statistical_unit);
DROP FUNCTION IF EXISTS public.physical_country(public.statistical_unit);
DROP FUNCTION IF EXISTS public.postal_country(public.statistical_unit);
DROP FUNCTION IF EXISTS public.primary_activity_category(public.statistical_unit);
DROP FUNCTION IF EXISTS public.secondary_activity_category(public.statistical_unit);
DROP FUNCTION IF EXISTS public.sector(public.statistical_unit);
DROP FUNCTION IF EXISTS public.legal_form(public.statistical_unit);
DROP FUNCTION IF EXISTS public.unit_size(public.statistical_unit);
DROP FUNCTION IF EXISTS public.status(public.statistical_unit);

END;
