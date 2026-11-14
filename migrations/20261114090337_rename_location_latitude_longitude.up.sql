-- Rename location.latitude/longitude to physical_latitude/physical_longitude
-- so all API endpoints use consistent names (statistical_unit already uses physical_*).

BEGIN;

-- 1. Rename columns
ALTER TABLE public.location RENAME COLUMN latitude TO physical_latitude;
ALTER TABLE public.location RENAME COLUMN longitude TO physical_longitude;

-- 2. Rename constraints to match
ALTER TABLE public.location RENAME CONSTRAINT
    "latitude_must_be_from_minus_90_to_90_degrees"
    TO "physical_latitude_must_be_from_minus_90_to_90_degrees";

ALTER TABLE public.location RENAME CONSTRAINT
    "longitude_must_be_from_minus_180_to_180_degrees"
    TO "physical_longitude_must_be_from_minus_180_to_180_degrees";

-- Note: CHECK constraint expressions that reference latitude/longitude are
-- automatically updated by ALTER TABLE RENAME COLUMN in PostgreSQL.
-- The constraint names below are just descriptive labels.

ALTER TABLE public.location RENAME CONSTRAINT
    "coordinates require both latitude and longitude"
    TO "coordinates require both physical_latitude and physical_longitude";

-- 3. Update column comments
COMMENT ON COLUMN public.location.physical_latitude IS
    'Latitude coordinate (decimal degrees). Only applicable for physical locations.';
COMMENT ON COLUMN public.location.physical_longitude IS
    'Longitude coordinate (decimal degrees). Only applicable for physical locations.';

COMMIT;
