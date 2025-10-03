BEGIN;

CREATE TYPE public.location_type AS ENUM ('physical', 'postal');

CREATE TABLE public.location (
    id SERIAL NOT NULL,
    valid_from date NOT NULL,
    valid_to date,
    valid_until date,
    type public.location_type NOT NULL,
    address_part1 character varying(200),
    address_part2 character varying(200),
    address_part3 character varying(200),
    postcode character varying(200),
    postplace character varying(200),
    region_id integer REFERENCES public.region(id) ON DELETE RESTRICT,
    country_id integer NOT NULL REFERENCES public.country(id) ON DELETE RESTRICT,
    latitude numeric(9, 6),
    longitude numeric(9, 6),
    altitude numeric(6, 1),
    establishment_id integer,
    legal_unit_id integer,
    data_source_id integer REFERENCES public.data_source(id) ON DELETE SET NULL,
    edit_comment character varying(512),
    edit_by_user_id integer NOT NULL REFERENCES auth.user(id) ON DELETE RESTRICT,
    edit_at timestamp with time zone NOT NULL DEFAULT statement_timestamp(),
    CONSTRAINT "coordinates require both latitude and longitude"
      CHECK((latitude IS NOT NULL AND longitude IS NOT NULL)
         OR (latitude IS NULL AND longitude IS NULL)),
    CONSTRAINT "altitude requires coordinates"
      CHECK(CASE
                WHEN altitude IS NOT NULL THEN
                    (latitude IS NOT NULL AND longitude IS NOT NULL)
                ELSE
                    TRUE
            END),
    CONSTRAINT "latitude_must_be_from_minus_90_to_90_degrees" CHECK(latitude >= -90 AND latitude <= 90),
    CONSTRAINT "longitude_must_be_from_minus_180_to_180_degrees" CHECK(longitude >= -180 AND longitude <= 180),
    CONSTRAINT "altitude_must_be_positive" CHECK(altitude >= 0),
    CONSTRAINT "postal_locations_cannot_have_coordinates" CHECK (
        CASE type
            WHEN 'postal' THEN (latitude IS NULL AND longitude IS NULL AND altitude IS NULL) -- If postal, all coords must be NULL
            ELSE TRUE -- Otherwise (physical), the constraint passes regardless of coords
        END
    )
);
COMMENT ON TABLE public.location IS 'Stores physical or postal addresses associated with statistical units (Legal Units or Establishments). Uses temporal validity.';
COMMENT ON COLUMN public.location.id IS 'Entity key for the location record (not the temporal era).';
COMMENT ON COLUMN public.location.valid_from IS 'Start date (inclusive) of the validity period for this location era.';
COMMENT ON COLUMN public.location.valid_to IS 'End date (inclusive) of the validity period for this location era. UI-facing.';
COMMENT ON COLUMN public.location.valid_until IS 'End date (exclusive) of the validity period for this location era. Used for temporal logic.';
COMMENT ON COLUMN public.location.type IS 'Type of location: ''physical'' or ''postal''.';
COMMENT ON COLUMN public.location.address_part1 IS 'First line of the address.';
COMMENT ON COLUMN public.location.address_part2 IS 'Second line of the address.';
COMMENT ON COLUMN public.location.address_part3 IS 'Third line of the address.';
COMMENT ON COLUMN public.location.postcode IS 'Postal code.';
COMMENT ON COLUMN public.location.postplace IS 'Postal place (city/town).';
COMMENT ON COLUMN public.location.region_id IS 'Foreign key to the region table.';
COMMENT ON COLUMN public.location.country_id IS 'Foreign key to the country table.';
COMMENT ON COLUMN public.location.latitude IS 'Latitude coordinate (decimal degrees). Only applicable for physical locations.';
COMMENT ON COLUMN public.location.longitude IS 'Longitude coordinate (decimal degrees). Only applicable for physical locations.';
COMMENT ON COLUMN public.location.altitude IS 'Altitude coordinate (meters). Only applicable for physical locations.';
COMMENT ON COLUMN public.location.establishment_id IS 'Foreign key to the establishment this location belongs to (NULL if linked to legal_unit).';
COMMENT ON COLUMN public.location.legal_unit_id IS 'Foreign key to the legal unit this location belongs to (NULL if linked to establishment).';
COMMENT ON COLUMN public.location.data_source_id IS 'Foreign key to the data source providing this information.';
COMMENT ON COLUMN public.location.edit_comment IS 'Comment added during manual edit.';
COMMENT ON COLUMN public.location.edit_by_user_id IS 'User who last edited this record.';
COMMENT ON COLUMN public.location.edit_at IS 'Timestamp of the last edit.';

CREATE INDEX ix_location_type ON public.location USING btree (type);
CREATE INDEX ix_location_region_id ON public.location USING btree (region_id);
CREATE INDEX ix_location_establishment_id ON public.location USING btree (establishment_id);
CREATE INDEX ix_location_legal_unit_id ON public.location USING btree (legal_unit_id);
CREATE INDEX ix_location_edit_by_user_id ON public.location USING btree (edit_by_user_id);
CREATE INDEX ix_location_country_id ON public.location USING btree (country_id);
CREATE INDEX ix_location_data_source_id ON public.location USING btree (data_source_id);
CREATE INDEX ix_location_legal_unit_id_valid_range ON public.location USING gist (legal_unit_id, daterange(valid_from, valid_until, '[)'));
CREATE INDEX ix_location_establishment_id_valid_range ON public.location USING gist (establishment_id, daterange(valid_from, valid_until, '[)'));

-- Improve filtering for temporal_merge
CREATE INDEX ON location (legal_unit_id, establishment_id, type);
CREATE INDEX ON location (legal_unit_id, type) WHERE establishment_id IS NULL;
CREATE INDEX ON location (establishment_id, type) WHERE legal_unit_id IS NULL;

-- Activate era handling
SELECT sql_saga.add_era('public.location', synchronize_valid_to_column => 'valid_to');

SELECT sql_saga.add_unique_key(
    table_oid => 'public.location',
    key_type => 'primary',
    column_names => ARRAY['id'],
    unique_key_name => 'location_id_valid'
);

SELECT sql_saga.add_unique_key(
    table_oid => 'public.location',
    key_type => 'natural',
    column_names => ARRAY['type', 'establishment_id','legal_unit_id'],
    mutually_exclusive_columns => ARRAY['establishment_id','legal_unit_id'],
    unique_key_name => 'location_type_establishment_id_valid'
);

SELECT sql_saga.add_foreign_key(
    fk_table_oid => 'public.location',
    fk_column_names => ARRAY['establishment_id'],
    pk_table_oid => 'public.establishment',
    pk_column_names => ARRAY['id']
);
SELECT sql_saga.add_foreign_key(
    fk_table_oid => 'public.location',
    fk_column_names => ARRAY['legal_unit_id'],
    pk_table_oid => 'public.legal_unit',
    pk_column_names => ARRAY['id']
);

-- Add a view for portion-of updates
SELECT sql_saga.add_for_portion_of_view('public.location');

END;
