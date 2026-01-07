BEGIN;

-- =================================================================
-- BEGIN: PostgREST resource embedding functions for statistical_unit
-- =================================================================
-- These functions enable PostgREST resource embedding for foreign key
-- relationships in the statistical_unit table.
-- Reference: https://docs.postgrest.org/en/latest/references/api/resource_embedding.html
-- =================================================================

-- Physical Region
CREATE FUNCTION public.physical_region(statistical_unit public.statistical_unit)
RETURNS SETOF public.region ROWS 1 AS $$
    SELECT r.*
    FROM public.region r
    WHERE r.id = statistical_unit.physical_region_id;
$$ LANGUAGE sql STABLE;

COMMENT ON FUNCTION public.physical_region(public.statistical_unit) IS
'PostgREST resource embedding function to retrieve the physical region for a statistical unit. '
'Usage: GET /statistical_unit?select=*,physical_region(name,code,path)';

-- Postal Region
CREATE FUNCTION public.postal_region(statistical_unit public.statistical_unit)
RETURNS SETOF public.region ROWS 1 AS $$
    SELECT r.*
    FROM public.region r
    WHERE r.id = statistical_unit.postal_region_id;
$$ LANGUAGE sql STABLE;

COMMENT ON FUNCTION public.postal_region(public.statistical_unit) IS
'PostgREST resource embedding function to retrieve the postal region for a statistical unit. '
'Usage: GET /statistical_unit?select=*,postal_region(name,code,path)';

-- Physical Country
CREATE FUNCTION public.physical_country(statistical_unit public.statistical_unit)
RETURNS SETOF public.country ROWS 1 AS $$
    SELECT c.*
    FROM public.country c
    WHERE c.id = statistical_unit.physical_country_id;
$$ LANGUAGE sql STABLE;

COMMENT ON FUNCTION public.physical_country(public.statistical_unit) IS
'PostgREST resource embedding function to retrieve the physical country for a statistical unit. '
'Usage: GET /statistical_unit?select=*,physical_country(iso_2,name)';

-- Postal Country
CREATE FUNCTION public.postal_country(statistical_unit public.statistical_unit)
RETURNS SETOF public.country ROWS 1 AS $$
    SELECT c.*
    FROM public.country c
    WHERE c.id = statistical_unit.postal_country_id;
$$ LANGUAGE sql STABLE;

COMMENT ON FUNCTION public.postal_country(public.statistical_unit) IS
'PostgREST resource embedding function to retrieve the postal country for a statistical unit. '
'Usage: GET /statistical_unit?select=*,postal_country(iso_2,name)';

-- Primary Activity Category
CREATE FUNCTION public.primary_activity_category(statistical_unit public.statistical_unit)
RETURNS SETOF public.activity_category ROWS 1 AS $$
    SELECT ac.*
    FROM public.activity_category ac
    WHERE ac.id = statistical_unit.primary_activity_category_id;
$$ LANGUAGE sql STABLE;

COMMENT ON FUNCTION public.primary_activity_category(public.statistical_unit) IS
'PostgREST resource embedding function to retrieve the primary activity category for a statistical unit. '
'Usage: GET /statistical_unit?select=*,primary_activity_category(code,name,path)';

-- Secondary Activity Category
CREATE FUNCTION public.secondary_activity_category(statistical_unit public.statistical_unit)
RETURNS SETOF public.activity_category ROWS 1 AS $$
    SELECT ac.*
    FROM public.activity_category ac
    WHERE ac.id = statistical_unit.secondary_activity_category_id;
$$ LANGUAGE sql STABLE;

COMMENT ON FUNCTION public.secondary_activity_category(public.statistical_unit) IS
'PostgREST resource embedding function to retrieve the secondary activity category for a statistical unit. '
'Usage: GET /statistical_unit?select=*,secondary_activity_category(code,name,path)';

-- Sector
CREATE FUNCTION public.sector(statistical_unit public.statistical_unit)
RETURNS SETOF public.sector ROWS 1 AS $$
    SELECT s.*
    FROM public.sector s
    WHERE s.id = statistical_unit.sector_id;
$$ LANGUAGE sql STABLE;

COMMENT ON FUNCTION public.sector(public.statistical_unit) IS
'PostgREST resource embedding function to retrieve the sector for a statistical unit. '
'Usage: GET /statistical_unit?select=*,sector(code,name,path)';

-- Legal Form
CREATE FUNCTION public.legal_form(statistical_unit public.statistical_unit)
RETURNS SETOF public.legal_form ROWS 1 AS $$
    SELECT lf.*
    FROM public.legal_form lf
    WHERE lf.id = statistical_unit.legal_form_id;
$$ LANGUAGE sql STABLE;

COMMENT ON FUNCTION public.legal_form(public.statistical_unit) IS
'PostgREST resource embedding function to retrieve the legal form for a statistical unit. '
'Usage: GET /statistical_unit?select=*,legal_form(code,name)';

-- Unit Size
CREATE FUNCTION public.unit_size(statistical_unit public.statistical_unit)
RETURNS SETOF public.unit_size ROWS 1 AS $$
    SELECT us.*
    FROM public.unit_size us
    WHERE us.id = statistical_unit.unit_size_id;
$$ LANGUAGE sql STABLE;

COMMENT ON FUNCTION public.unit_size(public.statistical_unit) IS
'PostgREST resource embedding function to retrieve the unit size for a statistical unit. '
'Usage: GET /statistical_unit?select=*,unit_size(code,name)';

-- Status
CREATE FUNCTION public.status(statistical_unit public.statistical_unit)
RETURNS SETOF public.status ROWS 1 AS $$
    SELECT st.*
    FROM public.status st
    WHERE st.id = statistical_unit.status_id;
$$ LANGUAGE sql STABLE;

COMMENT ON FUNCTION public.status(public.statistical_unit) IS
'PostgREST resource embedding function to retrieve the status for a statistical unit. '
'Usage: GET /statistical_unit?select=*,status(code,name)';

-- =================================================================
-- END: PostgREST resource embedding functions for statistical_unit
-- =================================================================

END;
