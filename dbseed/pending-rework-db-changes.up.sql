\echo public.analysis_queue
CREATE TABLE public.analysis_queue (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_start_period timestamp with time zone NOT NULL,
    user_end_period timestamp with time zone NOT NULL,
    user_id integer NOT NULL REFERENCES public.statbus_user(id) ON DELETE CASCADE,
    comment text,
    server_start_period timestamp with time zone,
    server_end_period timestamp with time zone
);
CREATE INDEX ix_analysis_queue_user_id ON public.analysis_queue USING btree (user_id);

\echo public.custom_analysis_check
CREATE TABLE public.custom_analysis_check (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name character varying(64),
    query character varying(2048),
    target_unit_types character varying(16)
);


-- This is not in use currently, as it is slated to be replaced by specific reports using the /search functionality
-- on statistical_unit
\echo public.analysis_log
CREATE TABLE public.analysis_log (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    analysis_queue_id integer NOT NULL REFERENCES public.analysis_queue(id) ON DELETE CASCADE,
    establishment_id integer check (admin.establishment_id_exists(establishment_id)),
    legal_unit_id integer check (admin.legal_unit_id_exists(legal_unit_id)),
    enterprise_id integer REFERENCES public.enterprise(id) ON DELETE CASCADE,
    enterprise_group_id integer check (admin.enterprise_group_id_exists(enterprise_group_id)),
    issued_at timestamp with time zone NOT NULL,
    resolved_at timestamp with time zone,
    summary_messages text,
    error_values text,
    CONSTRAINT "One and only one statistical unit id must be set"
    CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL AND enterprise_id IS     NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL AND enterprise_id IS     NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS     NULL AND enterprise_id IS NOT NULL AND enterprise_group_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS     NULL AND enterprise_id IS     NULL AND enterprise_group_id IS NOT NULL
        )
);
CREATE INDEX ix_analysis_log_analysis_queue_id_analyzed_queue_id ON public.analysis_log USING btree (analysis_queue_id);
CREATE INDEX ix_analysis_log_analysis_queue_id_establishment_id ON public.analysis_log USING btree (establishment_id);
CREATE INDEX ix_analysis_log_analysis_queue_id_legal_unit_id ON public.analysis_log USING btree (legal_unit_id);
CREATE INDEX ix_analysis_log_analysis_queue_id_enterprise_id ON public.analysis_log USING btree (enterprise_id);
CREATE INDEX ix_analysis_log_analysis_queue_id_enterprise_group_id ON public.analysis_log USING btree (enterprise_group_id);


-- Currently unused.
\echo public.postal_index
CREATE TABLE public.postal_index (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name text,
    archived boolean NOT NULL DEFAULT false,
    name_language1 text,
    name_language2 text
);


-- Currently unused
\echo public.report_tree
CREATE TABLE public.report_tree (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title text,
    type text,
    report_id integer,
    parent_node_id integer,
    archived boolean NOT NULL DEFAULT false,
    resource_group text,
    report_url text
);


-- Currently unused, replaced by the temporal tables.
\echo public.sample_frame
CREATE TABLE public.sample_frame (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name text NOT NULL,
    description text,
    predicate text NOT NULL,
    fields text NOT NULL,
    user_id integer REFERENCES public.statbus_user(id) ON DELETE SET NULL,
    status integer NOT NULL,
    file_path text,
    generated_date_time timestamp with time zone,
    creation_date timestamp with time zone NOT NULL,
    editing_date timestamp with time zone
);
CREATE INDEX ix_sample_frame_user_id ON public.sample_frame USING btree (user_id);



-- TODO: Create a view to see an establishment with statistics
-- TODO: allow upsert on statistics view according to stat_definition

---- Example dynamic generation of view for each active stat_definition
-- CREATE OR REPLACE FUNCTION generate_legal_unit_history_with_stats_view()
-- RETURNS VOID LANGUAGE plpgsql AS $$
-- DECLARE
--     dyn_query TEXT;
--     stat_code RECORD;
-- BEGIN
--     -- Start building the dynamic query
--     dyn_query := 'CREATE OR REPLACE VIEW legal_unit_history_with_stats AS SELECT id, unit_ident, name, edit_comment, valid_from, valid_to';
--
--     -- For each code in stat_definition, add it as a column
--     FOR stat_code IN (SELECT code FROM stat_definition WHERE archived = false ORDER BY priority)
--     LOOP
--         dyn_query := dyn_query || ', stats ->> ''' || stat_code.code || ''' AS "' || stat_code.code || '"';
--     END LOOP;
--
--     dyn_query := dyn_query || ' FROM legal_unit_history';
--
--     -- Execute the dynamic query
--     EXECUTE dyn_query;
--     -- Reload PostgREST to expose the new view
--     NOTIFY pgrst, 'reload config';
-- END;
-- $$;
-- --
-- CREATE OR REPLACE FUNCTION generate_legal_unit_history_with_stats_view_trigger()
-- RETURNS TRIGGER LANGUAGE plpgsql AS $$
-- BEGIN
--     -- Call the view generation function
--     PERFORM generate_legal_unit_history_with_stats_view();
--
--     -- As this is an AFTER trigger, we don't need to return any specific row.
--     RETURN NULL;
-- END;
-- $$;
-- --
-- CREATE TRIGGER regenerate_stats_view_trigger
-- AFTER INSERT OR UPDATE OR DELETE ON stat_definition
-- FOR EACH ROW
-- EXECUTE FUNCTION generate_legal_unit_history_with_stats_view_trigger();
-- --
-- SELECT generate_legal_unit_history_with_stats_view();
--



-- TODO: Use pg_audit.



-- Custom functionality for Uganda
\echo admin.upsert_region_7_levels
CREATE FUNCTION admin.upsert_region_7_levels()
RETURNS TRIGGER AS $$
BEGIN
    WITH source AS (
        SELECT NEW."Regional Code"::ltree AS path, NEW."Regional Name" AS name
            UNION ALL
        SELECT NEW."Regional Code"::ltree||NEW."District Code"::ltree AS path, NEW."District Name" AS name
            UNION ALL
        SELECT NEW."Regional Code"::ltree||NEW."District Code"::ltree||NEW."County Code" AS path, NEW."County Name" AS name
            UNION ALL
        SELECT NEW."Regional Code"::ltree||NEW."District Code"::ltree||NEW."County Code"||NEW."Constituency Code" AS path, NEW."Constituency Name" AS name
            UNION ALL
        SELECT NEW."Regional Code"::ltree||NEW."District Code"::ltree||NEW."County Code"||NEW."Constituency Code"||NEW."Subcounty Code" AS path, NEW."Subcounty Name" AS name
            UNION ALL
        SELECT NEW."Regional Code"::ltree||NEW."District Code"::ltree||NEW."County Code"||NEW."Constituency Code"||NEW."Subcounty Code"||NEW."Parish Code" AS path, NEW."Parish Name" AS name
            UNION ALL
        SELECT NEW."Regional Code"::ltree||NEW."District Code"::ltree||NEW."County Code"||NEW."Constituency Code"||NEW."Subcounty Code"||NEW."Parish Code"||NEW."Village Code" AS path, NEW."Village Name" AS name
    )
    INSERT INTO public.region_view(path, name)
    SELECT path,name FROM source;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create a view for region
\echo public.region_7_levels_view
CREATE VIEW public.region_7_levels_view
WITH (security_invoker=on) AS
SELECT '' AS "Regional Code"
     , '' AS "Regional Name"
     , '' AS "District Code"
     , '' AS "District Name"
     , '' AS "County Code"
     , '' AS "County Name"
     , '' AS "Constituency Code"
     , '' AS "Constituency Name"
     , '' AS "Subcounty Code"
     , '' AS "Subcounty Name"
     , '' AS "Parish Code"
     , '' AS "Parish Name"
     , '' AS "Village Code"
     , '' AS "Village Name"
     ;

-- Create triggers for the view
CREATE TRIGGER upsert_region_7_levels_view
INSTEAD OF INSERT ON public.region_7_levels_view
FOR EACH ROW
EXECUTE FUNCTION admin.upsert_region_7_levels();


-- Prototype to see how it can be done, to be generated dynamically
-- by a later import system.
-- View for insert of Norwegian Legal Unit (Hovedenhet)
\echo public.legal_unit_brreg_view
CREATE VIEW public.legal_unit_brreg_view
WITH (security_invoker=on) AS
SELECT '' AS "organisasjonsnummer"
     , '' AS "navn"
     , '' AS "organisasjonsform.kode"
     , '' AS "organisasjonsform.beskrivelse"
     , '' AS "naeringskode1.kode"
     , '' AS "naeringskode1.beskrivelse"
     , '' AS "naeringskode2.kode"
     , '' AS "naeringskode2.beskrivelse"
     , '' AS "naeringskode3.kode"
     , '' AS "naeringskode3.beskrivelse"
     , '' AS "hjelpeenhetskode.kode"
     , '' AS "hjelpeenhetskode.beskrivelse"
     , '' AS "harRegistrertAntallAnsatte"
     , '' AS "antallAnsatte"
     , '' AS "hjemmeside"
     , '' AS "postadresse.adresse"
     , '' AS "postadresse.poststed"
     , '' AS "postadresse.postnummer"
     , '' AS "postadresse.kommune"
     , '' AS "postadresse.kommunenummer"
     , '' AS "postadresse.land"
     , '' AS "postadresse.landkode"
     , '' AS "forretningsadresse.adresse"
     , '' AS "forretningsadresse.poststed"
     , '' AS "forretningsadresse.postnummer"
     , '' AS "forretningsadresse.kommune"
     , '' AS "forretningsadresse.kommunenummer"
     , '' AS "forretningsadresse.land"
     , '' AS "forretningsadresse.landkode"
     , '' AS "institusjonellSektorkode.kode"
     , '' AS "institusjonellSektorkode.beskrivelse"
     , '' AS "sisteInnsendteAarsregnskap"
     , '' AS "registreringsdatoenhetsregisteret"
     , '' AS "stiftelsesdato"
     , '' AS "registrertIMvaRegisteret"
     , '' AS "frivilligMvaRegistrertBeskrivelser"
     , '' AS "registrertIFrivillighetsregisteret"
     , '' AS "registrertIForetaksregisteret"
     , '' AS "registrertIStiftelsesregisteret"
     , '' AS "konkurs"
     , '' AS "konkursdato"
     , '' AS "underAvvikling"
     , '' AS "underAvviklingDato"
     , '' AS "underTvangsavviklingEllerTvangsopplosning"
     , '' AS "tvangsopplostPgaManglendeDagligLederDato"
     , '' AS "tvangsopplostPgaManglendeRevisorDato"
     , '' AS "tvangsopplostPgaManglendeRegnskapDato"
     , '' AS "tvangsopplostPgaMangelfulltStyreDato"
     , '' AS "tvangsavvikletPgaManglendeSlettingDato"
     , '' AS "overordnetEnhet"
     , '' AS "maalform"
     , '' AS "vedtektsdato"
     , '' AS "vedtektsfestetFormaal"
     , '' AS "aktivitet"
     ;

\echo admin.legal_unit_brreg_view_upsert
CREATE FUNCTION admin.legal_unit_brreg_view_upsert()
RETURNS TRIGGER AS $$
DECLARE
  result RECORD;
BEGIN
    WITH su AS (
        SELECT *
        FROM statbus_user
        WHERE uuid = auth.uid()
        LIMIT 1
    ), upsert_data AS (
        SELECT
          NEW."organisasjonsnummer" AS tax_ident
        , '2023-01-01'::date AS valid_from
        , 'infinity'::date AS valid_to
        , CASE NEW."stiftelsesdato"
          WHEN NULL THEN NULL
          WHEN '' THEN NULL
          ELSE NEW."stiftelsesdato"::date
          END AS birth_date
        , NEW."navn" AS name
        , true AS active
        , 'Batch import' AS edit_comment
        , (SELECT id FROM su) AS edit_by_user_id
    ),
    update_outcome AS (
        UPDATE public.legal_unit
        SET valid_from = upsert_data.valid_from
          , valid_to = upsert_data.valid_to
          , birth_date = upsert_data.birth_date
          , name = upsert_data.name
          , active = upsert_data.active
          , edit_comment = upsert_data.edit_comment
          , edit_by_user_id = upsert_data.edit_by_user_id
        FROM upsert_data
        WHERE legal_unit.tax_ident = upsert_data.tax_ident
          AND legal_unit.valid_to = 'infinity'::date
        RETURNING 'update'::text AS action, legal_unit.id
    ),
    insert_outcome AS (
        INSERT INTO public.legal_unit
          ( tax_ident
          , valid_from
          , valid_to
          , birth_date
          , name
          , active
          , edit_comment
          , edit_by_user_id
          )
        SELECT
            upsert_data.tax_ident
          , upsert_data.valid_from
          , upsert_data.valid_to
          , upsert_data.birth_date
          , upsert_data.name
          , upsert_data.active
          , upsert_data.edit_comment
          , upsert_data.edit_by_user_id
        FROM upsert_data
        WHERE NOT EXISTS (SELECT id FROM update_outcome LIMIT 1)
        RETURNING 'insert'::text AS action, id
    ), combined AS (
      SELECT * FROM update_outcome UNION ALL SELECT * FROM insert_outcome
    )
    SELECT * INTO result FROM combined;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;


-- Create triggers for the view
CREATE TRIGGER legal_unit_brreg_view_upsert
INSTEAD OF INSERT ON public.legal_unit_brreg_view
FOR EACH ROW
EXECUTE FUNCTION admin.legal_unit_brreg_view_upsert();

-- time psql <<EOS
-- \copy public.legal_unit_brreg_view FROM 'tmp/enheter.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
-- EOS

-- View for insert of Norwegian Establishment (Underenhet)
\echo public.establishment_brreg_view
CREATE VIEW public.establishment_brreg_view
WITH (security_invoker=on) AS
SELECT '' AS "organisasjonsnummer"
     , '' AS "navn"
     , '' AS "organisasjonsform.kode"
     , '' AS "organisasjonsform.beskrivelse"
     , '' AS "naeringskode1.kode"
     , '' AS "naeringskode1.beskrivelse"
     , '' AS "naeringskode2.kode"
     , '' AS "naeringskode2.beskrivelse"
     , '' AS "naeringskode3.kode"
     , '' AS "naeringskode3.beskrivelse"
     , '' AS "hjelpeenhetskode.kode"
     , '' AS "hjelpeenhetskode.beskrivelse"
     , '' AS "harRegistrertAntallAnsatte"
     , '' AS "antallAnsatte"
     , '' AS "hjemmeside"
     , '' AS "postadresse.adresse"
     , '' AS "postadresse.poststed"
     , '' AS "postadresse.postnummer"
     , '' AS "postadresse.kommune"
     , '' AS "postadresse.kommunenummer"
     , '' AS "postadresse.land"
     , '' AS "postadresse.landkode"
     , '' AS "beliggenhetsadresse.adresse"
     , '' AS "beliggenhetsadresse.poststed"
     , '' AS "beliggenhetsadresse.postnummer"
     , '' AS "beliggenhetsadresse.kommune"
     , '' AS "beliggenhetsadresse.kommunenummer"
     , '' AS "beliggenhetsadresse.land"
     , '' AS "beliggenhetsadresse.landkode"
     , '' AS "registreringsdatoIEnhetsregisteret"
     , '' AS "frivilligMvaRegistrertBeskrivelser"
     , '' AS "registrertIMvaregisteret"
     , '' AS "oppstartsdato"
     , '' AS "datoEierskifte"
     , '' AS "overordnetEnhet"
     , '' AS "nedleggelsesdato"
     ;


\echo admin.upsert_establishment_brreg_view
CREATE FUNCTION admin.upsert_establishment_brreg_view()
RETURNS TRIGGER AS $$
DECLARE
  result RECORD;
BEGIN
    WITH su AS (
        SELECT *
        FROM statbus_user
        WHERE uuid = auth.uid()
        LIMIT 1
    ), upsert_data AS (
        SELECT
          NEW."organisasjonsnummer" AS tax_ident
        , '2023-01-01'::date AS valid_from
        , 'infinity'::date AS valid_to
        , CASE NEW."oppstartsdato"
          WHEN NULL THEN NULL
          WHEN '' THEN NULL
          ELSE NEW."oppstartsdato"::date
          END AS birth_date
        , NEW."navn" AS name
        , true AS active
        , 'Batch import' AS edit_comment
        , (SELECT id FROM su) AS edit_by_user_id
    ),
    update_outcome AS (
        UPDATE public.establishment
        SET valid_from = upsert_data.valid_from
          , valid_to = upsert_data.valid_to
          , birth_date = upsert_data.birth_date
          , name = upsert_data.name
          , active = upsert_data.active
          , edit_comment = upsert_data.edit_comment
          , edit_by_user_id = upsert_data.edit_by_user_id
        FROM upsert_data
        WHERE establishment.tax_ident = upsert_data.tax_ident
          AND establishment.valid_to = 'infinity'::date
        RETURNING 'update'::text AS action, establishment.id
    ),
    insert_outcome AS (
        INSERT INTO public.establishment
          ( tax_ident
          , valid_from
          , valid_to
          , birth_date
          , name
          , active
          , edit_comment
          , edit_by_user_id
          )
        SELECT
            upsert_data.tax_ident
          , upsert_data.valid_from
          , upsert_data.valid_to
          , upsert_data.birth_date
          , upsert_data.name
          , upsert_data.active
          , upsert_data.edit_comment
          , upsert_data.edit_by_user_id
        FROM upsert_data
        WHERE NOT EXISTS (SELECT id FROM update_outcome LIMIT 1)
        RETURNING 'insert'::text AS action, id
    ), combined AS (
      SELECT * FROM update_outcome UNION ALL SELECT * FROM insert_outcome
    )
    SELECT * INTO result FROM combined;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;


-- Create triggers for the view
CREATE TRIGGER upsert_establishment_brreg_view
INSTEAD OF INSERT ON public.establishment_brreg_view
FOR EACH ROW
EXECUTE FUNCTION admin.upsert_establishment_brreg_view();
