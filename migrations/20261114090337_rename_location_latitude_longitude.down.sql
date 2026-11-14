-- Revert: rename physical_latitude/physical_longitude back to latitude/longitude

BEGIN;

ALTER TABLE public.location RENAME COLUMN physical_latitude TO latitude;
ALTER TABLE public.location RENAME COLUMN physical_longitude TO longitude;

ALTER TABLE public.location RENAME CONSTRAINT
    "physical_latitude_must_be_from_minus_90_to_90_degrees"
    TO "latitude_must_be_from_minus_90_to_90_degrees";

ALTER TABLE public.location RENAME CONSTRAINT
    "physical_longitude_must_be_from_minus_180_to_180_degrees"
    TO "longitude_must_be_from_minus_180_to_180_degrees";

ALTER TABLE public.location RENAME CONSTRAINT
    "coordinates require both physical_latitude and physical_longitude"
    TO "coordinates require both latitude and longitude";

COMMENT ON COLUMN public.location.latitude IS
    'Latitude coordinate (decimal degrees). Only applicable for physical locations.';
COMMENT ON COLUMN public.location.longitude IS
    'Longitude coordinate (decimal degrees). Only applicable for physical locations.';

COMMIT;
