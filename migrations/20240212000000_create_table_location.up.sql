BEGIN;

CREATE TABLE public.location (
    id SERIAL NOT NULL,
    valid_after date GENERATED ALWAYS AS (valid_from - INTERVAL '1 day') STORED,
    valid_from date NOT NULL DEFAULT current_date,
    valid_to date NOT NULL DEFAULT 'infinity',
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
    created_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    edit_comment character varying(512),
    edit_by_user_id integer NOT NULL REFERENCES public.statbus_user(id) ON DELETE RESTRICT,
    edit_at timestamp with time zone NOT NULL DEFAULT statement_timestamp(),
    CONSTRAINT "One and only one statistical unit id must be set"
    CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL),
    CONSTRAINT "coordinates require both latitude and longitude"
      CHECK((latitude IS NOT NULL AND longitude IS NOT NULL)
         OR (latitude IS NULL AND longitude IS NULL)),
    CONSTRAINT "altitude requires coordinates"
      CHECK(CASE
                WHEN altitude IS NOT NULL THEN
                    (latitude IS NOT NULL AND longitude IS NOT NULL)
                ELSE
                    TRUE
            END)
);
CREATE INDEX ix_address_region_id ON public.location USING btree (region_id);
CREATE INDEX ix_location_establishment_id_id ON public.location USING btree (establishment_id);
CREATE INDEX ix_location_legal_unit_id_id ON public.location USING btree (legal_unit_id);
CREATE INDEX ix_location_edit_by_user_id ON public.location USING btree (edit_by_user_id);

END;
