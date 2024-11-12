\echo admin.generate_import_establishment_current_without_legal_unit()
CREATE PROCEDURE admin.generate_import_establishment_current_without_legal_unit()
LANGUAGE plpgsql AS $generate_import_establishment_current_without_legal_unit$
DECLARE
    ident_type_row RECORD;
    stat_definition_row RECORD;
    ident_type_columns TEXT := '';
    stat_definition_columns TEXT := '';
    ident_insert_labels TEXT := '';
    stats_insert_labels TEXT := '';
    ident_value_labels TEXT := '';
    stats_value_labels TEXT := '';

    view_template TEXT := $view_template$
CREATE VIEW public.import_establishment_current_without_legal_unit
WITH (security_invoker=on) AS
SELECT {{ident_type_columns}}
     -- legal_unit_tax_ident is Disabled because this is an informal sector
       name,
       birth_date,
       death_date,
       physical_address_part1,
       physical_address_part2,
       physical_address_part3,
       physical_postal_code,
       physical_postal_place,
       physical_region_code,
       physical_region_path,
       physical_country_iso_2,
       postal_address_part1,
       postal_address_part2,
       postal_address_part3,
       postal_postal_code,
       postal_postal_place,
       postal_region_code,
       postal_region_path,
       postal_country_iso_2,
       primary_activity_category_code,
       secondary_activity_category_code,
       sector_code, -- Is allowed, since there is no legal unit to provide it.
       data_source_code,
{{stat_definition_columns}}
       tag_path
FROM public.import_establishment_era;
    $view_template$;

    function_template TEXT := $function_template$
CREATE FUNCTION admin.import_establishment_current_without_legal_unit_upsert()
RETURNS TRIGGER LANGUAGE plpgsql AS $import_establishment_current_without_legal_unit_upsert$
DECLARE
    new_valid_from DATE := current_date;
    new_valid_to DATE := 'infinity'::date;
BEGIN
    INSERT INTO public.import_establishment_era (
        valid_from,
        valid_to,
{{ident_insert_labels}}
        name,
        birth_date,
        death_date,
        physical_address_part1,
        physical_address_part2,
        physical_address_part3,
        physical_postal_code,
        physical_postal_place,
        physical_region_code,
        physical_region_path,
        physical_country_iso_2,
        postal_address_part1,
        postal_address_part2,
        postal_address_part3,
        postal_postal_code,
        postal_postal_place,
        postal_region_code,
        postal_region_path,
        postal_country_iso_2,
        primary_activity_category_code,
        secondary_activity_category_code,
        sector_code,
        data_source_code,
{{stats_insert_labels}}
        tag_path
    ) VALUES (
        new_valid_from,
        new_valid_to,
{{ident_value_labels}}
        NEW.name,
        NEW.birth_date,
        NEW.death_date,
        NEW.physical_address_part1,
        NEW.physical_address_part2,
        NEW.physical_address_part3,
        NEW.physical_postal_code,
        NEW.physical_postal_place,
        NEW.physical_region_code,
        NEW.physical_region_path,
        NEW.physical_country_iso_2,
        NEW.postal_address_part1,
        NEW.postal_address_part2,
        NEW.postal_address_part3,
        NEW.postal_postal_code,
        NEW.postal_postal_place,
        NEW.postal_region_code,
        NEW.postal_region_path,
        NEW.postal_country_iso_2,
        NEW.primary_activity_category_code,
        NEW.secondary_activity_category_code,
        NEW.sector_code,
        NEW.data_source_code,
{{stats_value_labels}}
        NEW.tag_path
        );
    RETURN NULL;
END;
$import_establishment_current_without_legal_unit_upsert$;
    $function_template$;
    view_sql TEXT;
    function_sql TEXT;
BEGIN
    SELECT
        string_agg(format(E'     %I,', code), E'\n'),
        string_agg(format(E'        %I,', code), E'\n'),
        string_agg(format(E'        NEW.%I,', code), E'\n')
    INTO
        ident_type_columns,
        ident_insert_labels,
        ident_value_labels
    FROM (SELECT code FROM public.external_ident_type_active) AS ordered;

    SELECT
        string_agg(format(E'     %L AS %I,','', code), E'\n'),
        string_agg(format(E'        %I,', code), E'\n'),
        string_agg(format(E'        NEW.%I,', code), E'\n')
    INTO
        stat_definition_columns,
        stats_insert_labels,
        stats_value_labels
    FROM (SELECT code FROM public.stat_definition_active) AS ordered;

    -- Render the view template
    view_sql := admin.render_template(view_template, jsonb_build_object(
        'ident_type_columns', ident_type_columns,
        'stat_definition_columns', stat_definition_columns
    ));

    -- Render the function template
    function_sql := admin.render_template(function_template, jsonb_build_object(
        'ident_insert_labels', ident_insert_labels,
        'stats_insert_labels', stats_insert_labels,
        'ident_value_labels', ident_value_labels,
        'stats_value_labels', stats_value_labels
    ));

    -- Continue with the rest of your procedure logic
    RAISE NOTICE 'Creating public.import_establishment_current_without_legal_unit';
    EXECUTE view_sql;
    COMMENT ON VIEW public.import_establishment_current_without_legal_unit IS 'Upload of establishment without a legal unit for a specified time';

    RAISE NOTICE 'Creating admin.import_establishment_current_without_legal_unit_upsert()';
    EXECUTE function_sql;

    CREATE TRIGGER import_establishment_current_without_legal_unit_upsert_trigger
    INSTEAD OF INSERT ON public.import_establishment_current_without_legal_unit
    FOR EACH ROW
    EXECUTE FUNCTION admin.import_establishment_current_without_legal_unit_upsert();

END;
$generate_import_establishment_current_without_legal_unit$;

\echo admin.cleanup_import_establishment_current_without_legal_unit()
CREATE PROCEDURE admin.cleanup_import_establishment_current_without_legal_unit()
LANGUAGE plpgsql AS $$
BEGIN
    RAISE NOTICE 'Deleting public.import_establishment_current_without_legal_unit';
    DROP VIEW public.import_establishment_current_without_legal_unit;
    RAISE NOTICE 'Deleting admin.import_establishment_current_without_legal_unit_upsert';
    DROP FUNCTION admin.import_establishment_current_without_legal_unit_upsert();
END;
$$;

\echo Add import_legal_unit_current callbacks
CALL lifecycle_callbacks.add(
    'import_establishment_current_without_legal_unit',
    ARRAY['public.external_ident_type','public.stat_definition']::regclass[],
    'admin.generate_import_establishment_current_without_legal_unit',
    'admin.cleanup_import_establishment_current_without_legal_unit'
    );

\echo Generating admin.generate_import_establishment_current_without_legal_unit
CALL admin.generate_import_establishment_current_without_legal_unit();


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