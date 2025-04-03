-- Minor Migration 1_159: create_table_contact
BEGIN;

CREATE TABLE public.contact (
    id SERIAL NOT NULL,
    valid_after date GENERATED ALWAYS AS (valid_from - INTERVAL '1 day') STORED,
    valid_from date NOT NULL DEFAULT current_date,
    valid_to date NOT NULL DEFAULT 'infinity',
    web_address character varying(256),
    email_address character varying(50),
    phone_number character varying(50),
    landline character varying(50),
    mobile_number character varying(50),
    fax_number character varying(50),
    CONSTRAINT "One information must be provided" CHECK (
        web_address IS NOT NULL OR
        email_address IS NOT NULL OR
        phone_number IS NOT NULL OR
        landline IS NOT NULL OR
        mobile_number IS NOT NULL OR
        fax_number IS NOT NULL
    ),
    establishment_id integer,
    legal_unit_id integer,
    CONSTRAINT "One and only one statistical unit id must be set"
    CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL
        ),
    data_source_id integer REFERENCES public.data_source(id),
    edit_comment character varying(512),
    edit_by_user_id integer NOT NULL REFERENCES auth.user(id) ON DELETE RESTRICT,
    edit_at timestamp with time zone NOT NULL DEFAULT statement_timestamp()
);

CREATE INDEX ix_contact_establishment_id ON public.contact USING btree (establishment_id);
CREATE INDEX ix_contact_legal_unit_id ON public.contact USING btree (legal_unit_id);
CREATE INDEX ix_contact_data_source_id ON public.contact USING btree (data_source_id);
CREATE INDEX ix_contact_edit_by_user_id ON public.contact USING btree (edit_by_user_id);

END;
