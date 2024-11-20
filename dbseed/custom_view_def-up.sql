BEGIN;

\echo public.custom_view_def_target_table
CREATE TABLE public.custom_view_def_target_table(
    id serial PRIMARY KEY,
    schema_name text NOT NULL,
    table_name text NOT NULL,
    name text UNIQUE NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW(),
    UNIQUE (schema_name, table_name)
);
INSERT INTO public.custom_view_def_target_table (schema_name,table_name, name)
VALUES
    ('public','legal_unit', 'Legal Unit')
   ,('public','establishment', 'Establishment')
   ,('public','enterprise', 'Enterprise')
   ,('public','enterprise_group', 'Enterprise Group')
   ;

\echo public.custom_view_def_target_column
CREATE TABLE public.custom_view_def_target_column(
    id serial PRIMARY KEY,
    target_table_id int REFERENCES public.custom_view_def_target_table(id),
    column_name text NOT NULL,
    uniquely_identifying boolean NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW()
);
WITH cols AS (
  SELECT tt.id AS target_table_id
       , column_name
       , data_type
       , is_nullable
       , column_name like '%_ident' AS uniquely_identifying
       , ROW_NUMBER() OVER (PARTITION BY tt.id ORDER BY ordinal_position) AS priority
  FROM information_schema.columns AS c
  JOIN public.custom_view_def_target_table AS tt
    ON c.table_schema = tt.schema_name
    AND c.table_name = tt.table_name
  ORDER BY ordinal_position
) INSERT INTO public.custom_view_def_target_column(target_table_id, column_name, uniquely_identifying)
  SELECT target_table_id, column_name, uniquely_identifying
  FROM cols
  ;

\echo public.custom_view_def
CREATE TABLE public.custom_view_def(
    id serial PRIMARY KEY,
    target_table_id int REFERENCES public.custom_view_def_target_table(id),
    slug text UNIQUE NOT NULL,
    name text NOT NULL,
    note text,
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW()
);

\echo public.custom_view_def_source_column
CREATE TABLE public.custom_view_def_source_column(
    id serial PRIMARY KEY,
    custom_view_def_id int REFERENCES public.custom_view_def(id),
    column_name text NOT NULL,
    priority int NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW()
);
COMMENT ON COLUMN public.custom_view_def_source_column.priority IS 'The ordering of the columns in the CSV file.';

\echo public.custom_view_def_mapping
CREATE TABLE public.custom_view_def_mapping(
    custom_view_def_id int REFERENCES public.custom_view_def(id),
    source_column_id int REFERENCES public.custom_view_def_source_column(id),
    target_column_id int REFERENCES public.custom_view_def_target_column(id),
    CONSTRAINT unique_source_column_mapping UNIQUE (custom_view_def_id, source_column_id),
    CONSTRAINT unique_target_column_mapping UNIQUE (custom_view_def_id, target_column_id),
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW()
);


\echo admin.custom_view_def_expanded
CREATE VIEW admin.custom_view_def_expanded AS
    SELECT cvd.id AS view_def_id,
           cvd.slug AS view_def_slug,
           cvd.name AS view_def_name,
           cvd.note AS view_def_note,
           cvdtt.schema_name AS target_schema_name,
           cvdtt.table_name AS target_table_name,
           cvdsc.column_name AS source_column,
           cvdtc.column_name AS target_column,
           cvdtc.uniquely_identifying AS uniquely_identifying,
           cvdsc.priority AS source_column_priority
    FROM public.custom_view_def cvd,
         public.custom_view_def_target_table cvdtt,
         public.custom_view_def_mapping cvdm,
         public.custom_view_def_source_column cvdsc,
         public.custom_view_def_target_column cvdtc
    WHERE cvd.target_table_id = cvdtt.id
      AND cvd.id = cvdm.custom_view_def_id
      AND cvdm.source_column_id = cvdsc.id
      AND cvdm.target_column_id = cvdtc.id
    ORDER BY cvd.id ASC, cvdsc.priority ASC NULLS LAST, cvdsc.id ASC, cvdtc.id ASC
;


CREATE TYPE admin.custom_view_def_names AS (
    table_name text,
    view_name text,
    upsert_function_name text,
    delete_function_name text,
    upsert_trigger_name text,
    delete_trigger_name text
);

\echo admin.custom_view_def_generate_names
CREATE FUNCTION admin.custom_view_def_generate_names(record public.custom_view_def)
RETURNS admin.custom_view_def_names AS $$
DECLARE
    result admin.custom_view_def_names;
    table_name text;
BEGIN
    SELECT INTO table_name cvdtt.table_name
    FROM public.custom_view_def_target_table AS cvdtt
    WHERE id = record.target_table_id;

    result.table_name := table_name;
    result.view_name := table_name || '_' || record.slug || '_view';
    result.upsert_function_name := result.view_name || '_upsert';
    result.delete_function_name := result.view_name || '_delete';
    result.upsert_trigger_name := result.view_name || '_upsert_trigger';
    result.delete_trigger_name := result.view_name || '_delete_trigger';

    RAISE NOTICE 'Generated Names for table %: %', table_name, to_json(result);

    RETURN result;
END;
$$ LANGUAGE plpgsql;


\echo admin.custom_view_def_generate
CREATE OR REPLACE FUNCTION admin.custom_view_def_generate(record public.custom_view_def)
RETURNS void AS $custom_view_def_generate$
DECLARE
    names admin.custom_view_def_names;
    upsert_function_stmt text;
    delete_function_stmt text;
    select_stmt text := 'SELECT ';
    add_separator boolean := false;
    mapping RECORD;
BEGIN
    names := admin.custom_view_def_generate_names(record);
    RAISE NOTICE 'Generating view %', names.view_name;

    -- Build a VIEW suitable for extraction from columns of the target_table
    -- and into the columns of the source.
    -- This allows a query of the target_table that returns the expected columns
    -- of the source.
    -- Example:
    --    CREATE VIEW public.legal_unit_brreg_view
    --    WITH (security_invoker=on) AS
    --    SELECT
    --        COALESCE(t."$target_column1",'') AS "source column 1"
    --        , '' AS "source column 2"
    --        COALESCE(t."$target_column2",'') AS "source column 3"
    --        , '' AS "source column 4"
    --        ...
    --    FROM public.legal_unit AS t;
    --
    FOR mapping IN SELECT source_column, target_column
        FROM admin.custom_view_def_expanded
        WHERE view_def_id = record.id
          AND source_column IS NOT NULL
          AND target_column IS NOT NULL
    LOOP
        --RAISE NOTICE 'Processing mapping for source column: %, target column: %', mapping.source_column, mapping.target_column;
        IF NOT add_separator THEN
            add_separator := true;
        ELSE
            select_stmt := select_stmt || ', ';
        END IF;
        IF mapping.target_column IS NULL THEN
            select_stmt := select_stmt || format(
                '%L AS %I'
                , '', mapping.source_column
            );
        ELSE
            select_stmt := select_stmt || format(
                'COALESCE(target.%I::text, %L) AS %I'
                , mapping.target_column, '', mapping.source_column
            );
        END IF;
    END LOOP;
    select_stmt := select_stmt || format(' FROM public.%I AS target', names.table_name);

    EXECUTE 'CREATE VIEW public.' || names.view_name || ' WITH (security_invoker=on) AS ' || select_stmt;

    -- Create Upsert Function
    RAISE NOTICE 'Generating upsert function % for view %', names.upsert_function_name, names.view_name;

    -- Create an UPSERT function that takes data found in the view,
    -- and upserts them into the target table, using the defined column
    -- mappings.
    upsert_function_stmt :=
    'CREATE FUNCTION admin.' || names.upsert_function_name || '() RETURNS TRIGGER AS $$
DECLARE
    result RECORD;
BEGIN
    WITH su AS (
        SELECT *
        FROM statbus_user
        WHERE uuid = auth.uid()
        LIMIT 1
    ), upsert_data AS (
        SELECT ';

    add_separator := false;
    FOR mapping IN SELECT source_column, target_column
        FROM admin.custom_view_def_expanded
        WHERE view_def_id = record.id
          AND source_column IS NOT NULL
          AND target_column IS NOT NULL
    LOOP
        --RAISE NOTICE 'Processing mapping for source column: %, target column: %', mapping.source_column, mapping.target_column;
        IF NOT add_separator THEN
            add_separator := true;
        ELSE
            upsert_function_stmt := upsert_function_stmt || ', ';
        END IF;
        -- TODO: Support setting NOW as a source in the mapping, instead of a column.
        --   , statement_timestamp() AS updated_at
        -- TODO: Support setting a value as a source in the mapping, instead of a column.
        --   , '2023-01-01'::date AS valid_from
        --   , 'infinity'::date AS valid_to
        -- TODO: Interpret empty string as NULL date.
        --  , CASE NEW."stiftelsesdato"
        --    WHEN NULL THEN NULL
        --    WHEN '' THEN NULL
        --    ELSE NEW."stiftelsesdato"::date
        --    END AS birth_date
        upsert_function_stmt := upsert_function_stmt || format(
            'NEW.%I AS %I'
            , mapping.source_column, mapping.target_column
        );
    END LOOP;
    BEGIN -- Handle fixed columns
        upsert_function_stmt := upsert_function_stmt ||
        ', true AS active' ||
        ', statement_timestamp() AS seen_in_import_at' ||
        ', ''Batch import'' AS edit_comment' ||
        ', (SELECT id FROM su) AS edit_by_user_id';
    END;
    upsert_function_stmt := upsert_function_stmt || format(
    '), update_outcome AS (
        UPDATE public.%I AS target SET ', names.table_name);
        add_separator := false;
        FOR mapping IN SELECT source_column, target_column
        FROM admin.custom_view_def_expanded
        WHERE view_def_id = record.id
          AND source_column IS NOT NULL
          AND target_column IS NOT NULL
        LOOP
            IF NOT add_separator THEN
                add_separator := true;
            ELSE
                upsert_function_stmt := upsert_function_stmt || ', ';
            END IF;
            upsert_function_stmt := upsert_function_stmt || format(
                '%I = upsert_data.%I'
                , mapping.target_column, mapping.target_column
            );
        END LOOP;
        -- TODO: Add mapping expression to support
        -- , valid_from = upsert_data.valid_from
        -- , valid_to = upsert_data.valid_to
        -- , birth_date = upsert_data.birth_date
        upsert_function_stmt := upsert_function_stmt ||
          ', active = upsert_data.active' ||
          ', seen_in_import_at = upsert_data.seen_in_import_at' ||
          ', edit_comment = upsert_data.edit_comment' ||
          ', edit_by_user_id = upsert_data.edit_by_user_id' ||
        ' FROM upsert_data WHERE ';
            add_separator := false;
            FOR mapping IN SELECT source_column, target_column
                FROM admin.custom_view_def_expanded
                WHERE view_def_id = record.id
                  AND source_column IS NOT NULL
                  AND target_column IS NOT NULL
                  AND uniquely_identifying
            LOOP
                IF NOT add_separator THEN
                    add_separator := true;
                ELSE
                    upsert_function_stmt := upsert_function_stmt || ' AND ';
                END IF;
                upsert_function_stmt := upsert_function_stmt || format(
                    'target.%I = upsert_data.%I'
                    , mapping.target_column, mapping.target_column
                );
            END LOOP;
            upsert_function_stmt := upsert_function_stmt ||
            -- TODO: Improve handling of valid_to/valid_from by using custom_view_def
            ' AND legal_unit.valid_to = ''infinity''::date' ||
        ' RETURNING ''update''::text AS action, target.id' ||
    '), insert_outcome AS (';
    upsert_function_stmt := upsert_function_stmt || format(
    'INSERT INTO public.%I(', names.table_name);
            add_separator := false;
            FOR mapping IN SELECT source_column, target_column
                FROM admin.custom_view_def_expanded
                WHERE view_def_id = record.id
                  AND source_column IS NOT NULL
                  AND target_column IS NOT NULL
                  AND uniquely_identifying
            LOOP
                IF NOT add_separator THEN
                    add_separator := true;
                ELSE
                    upsert_function_stmt := upsert_function_stmt || ', ';
                END IF;
                upsert_function_stmt := upsert_function_stmt || format(
                    '%I'
                    , mapping.target_column
                );
            END LOOP;
            -- TODO: Add mapping expression to support
            --   , valid_from
            --   , valid_to
            --   , birth_date
            upsert_function_stmt := upsert_function_stmt ||
            ', active' ||
            ', seen_in_import_at' ||
            ', edit_comment' ||
            ', edit_by_user_id' ||
            ') SELECT ';
            add_separator := false;
            FOR mapping IN SELECT source_column, target_column
                FROM admin.custom_view_def_expanded
                WHERE view_def_id = record.id
                  AND source_column IS NOT NULL
                  AND target_column IS NOT NULL
            LOOP
                IF NOT add_separator THEN
                    add_separator := true;
                ELSE
                    upsert_function_stmt := upsert_function_stmt || ', ';
                END IF;
                upsert_function_stmt := upsert_function_stmt || format(
                    'upsert_data.%I'
                    , mapping.target_column
                );
            END LOOP;
            -- TODO: Add mapping expression to support
            --  , upsert_data.valid_from
            --  , upsert_data.valid_to
            --  , upsert_data.birth_date
            upsert_function_stmt := upsert_function_stmt ||
            ', upsert_data.active' ||
            ', upsert_data.seen_in_import_at' ||
            ', upsert_data.edit_comment' ||
            ', upsert_data.edit_by_user_id' ||
        ' FROM upsert_data' ||
        ' WHERE NOT EXISTS (SELECT id FROM update_outcome LIMIT 1)
        RETURNING ''insert''::text AS action, id
    ), combined AS (
      SELECT * FROM update_outcome UNION ALL SELECT * FROM insert_outcome
    )
    SELECT * INTO result FROM combined;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;';

    RAISE NOTICE 'upsert_function_stmt = %', upsert_function_stmt;
    EXECUTE upsert_function_stmt;

    -- Create Delete Function
    delete_function_stmt := format(
    'CREATE FUNCTION admin.%I() RETURNS TRIGGER AS $$
    BEGIN
        WITH su AS (
            SELECT *
            FROM statbus_user
            WHERE uuid = auth.uid()
            LIMIT 1
        )
        UPDATE public.%I
        SET valid_to = statement_timestamp()
          , edit_comment = ''Absent from upload''
          , edit_by_user_id = (SELECT id FROM su)
          , active = false
        WHERE seen_in_import_at < statement_timestamp();
        RETURN NULL;
    END;
    $$ LANGUAGE plpgsql', names.delete_function_name, names.table_name);

    RAISE NOTICE 'delete_function_stmt = %', delete_function_stmt;
    EXECUTE delete_function_stmt;

    -- Create triggers for the view
    -- Create Triggers
    EXECUTE format(
        'CREATE TRIGGER %I
        INSTEAD OF INSERT ON public.%I
        FOR EACH ROW
        EXECUTE FUNCTION admin.%I(NEW)', names.upsert_trigger_name, names.view_name, names.upsert_function_name);
    EXECUTE format(
        'CREATE TRIGGER %I
        AFTER INSERT ON public.%I
        FOR EACH STATEMENT
        EXECUTE FUNCTION admin.%I()', names.delete_trigger_name, names.view_name, names.delete_function_name);
END;
$custom_view_def_generate$ LANGUAGE plpgsql;

\echo admin.custom_view_def_destroy
CREATE OR REPLACE FUNCTION admin.custom_view_def_destroy(record public.custom_view_def)
RETURNS void AS $custom_view_def_destroy$
DECLARE
    names admin.custom_view_def_names;
BEGIN
    names := admin.custom_view_def_generate_names(record);

    IF names IS NULL THEN
        RAISE NOTICE 'names is NULL for record id %', record.id;
        RETURN;
    ELSE
        RAISE NOTICE 'View name: %', names.view_name;
    END IF;

    -- Drop Upsert and Delete Functions and Triggers
    EXECUTE format('DROP TRIGGER %I ON public.%I', names.upsert_trigger_name, names.view_name);
    EXECUTE format('DROP TRIGGER %I ON public.%I', names.delete_trigger_name, names.view_name);
    EXECUTE format('DROP FUNCTION admin.%I', names.upsert_function_name);
    EXECUTE format('DROP FUNCTION admin.%I', names.delete_function_name);

    -- Drop view
    EXECUTE format('DROP VIEW public.%I', names.view_name);

END;
$custom_view_def_destroy$ LANGUAGE plpgsql;

-- Before trigger for custom_view_def
\echo admin.custom_view_def_before
CREATE OR REPLACE FUNCTION admin.custom_view_def_before()
RETURNS trigger AS $$
BEGIN
    PERFORM admin.custom_view_def_destroy(OLD);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER custom_view_def_before_trigger
BEFORE UPDATE OR DELETE ON public.custom_view_def
FOR EACH ROW EXECUTE FUNCTION admin.custom_view_def_before();

-- After trigger for custom_view_def
\echo admin.custom_view_def_after
CREATE OR REPLACE FUNCTION admin.custom_view_def_after()
RETURNS trigger AS $$
BEGIN
    PERFORM admin.custom_view_def_generate(NEW);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER custom_view_def_after_trigger
AFTER INSERT OR UPDATE ON public.custom_view_def
FOR EACH ROW EXECUTE FUNCTION admin.custom_view_def_after();





WITH tt AS (
    SELECT * FROM public.custom_view_def_target_table
    WHERE schema_name = 'public'
      AND table_name = 'legal_unit'
), def AS (
    INSERT INTO public.custom_view_def(target_table_id, slug, name, note)
    SELECT id, 'brreg_hovedenhet', 'Import of BRREG Hovedenhet', 'Easy upload of the CSV file found at brreg.'
    FROM tt
    RETURNING *
), name_mapping(priority, source_column_name, target_column_name) AS (
VALUES (1, 'organisasjonsnummer', 'tax_ident')
    , ( 2, 'navn', 'name')
    , ( 3, 'organisasjonsform.kode', 'legal_form_code')
    , ( 4, 'organisasjonsform.beskrivelse', NULL)
    , ( 5, 'naeringskode1.kode', 'primary_activity_category_code')
    , ( 6, 'naeringskode1.beskrivelse', NULL)
    , ( 7, 'naeringskode2.kode', 'secondary_activity_category_code')
    , ( 8, 'naeringskode2.beskrivelse', NULL)
    , ( 9, 'naeringskode3.kode', NULL)
    , (10, 'naeringskode3.beskrivelse', NULL)
    , (11, 'hjelpeenhetskode.kode', NULL)
    , (12, 'hjelpeenhetskode.beskrivelse', NULL)
    , (13, 'harRegistrertAntallAnsatte', NULL)
    , (14, 'antallAnsatte', NULL)
    , (15, 'hjemmeside', NULL)
    , (16, 'postadresse.adresse', 'postal_address_part1')
    , (17, 'postadresse.poststed', 'postal_postplace')
    , (18, 'postadresse.postnummer', 'postal_postcode')
    , (19, 'postadresse.kommune', NULL)
    , (20, 'postadresse.kommunenummer', 'postal_region_code')
    , (21, 'postadresse.land', NULL)
    , (22, 'postadresse.landkode', 'postal_country_iso_2')
    , (23, 'forretningsadresse.adresse', 'physical_address_part1')
    , (24, 'forretningsadresse.poststed', 'physical_postplace')
    , (25, 'forretningsadresse.postnummer', 'physical_postcode')
    , (26, 'forretningsadresse.kommune', NULL)
    , (27, 'forretningsadresse.kommunenummer', 'physical_region_code')
    , (28, 'forretningsadresse.land', NULL)
    , (29, 'forretningsadresse.landkode', 'physical_country_iso_2')
    , (30, 'institusjonellSektorkode.kode', 'sector_code')
    , (31, 'institusjonellSektorkode.beskrivelse', NULL)
    , (32, 'sisteInnsendteAarsregnskap', NULL)
    , (33, 'registreringsdatoenhetsregisteret', NULL)
    , (34, 'stiftelsesdato', 'birth_date')
    , (35, 'registrertIMvaRegisteret', NULL)
    , (36, 'frivilligMvaRegistrertBeskrivelser', NULL)
    , (37, 'registrertIFrivillighetsregisteret', NULL)
    , (38, 'registrertIForetaksregisteret', NULL)
    , (39, 'registrertIStiftelsesregisteret', NULL)
    , (40, 'konkurs', NULL)
    , (41, 'konkursdato', NULL)
    , (42, 'underAvvikling', NULL)
    , (43, 'underAvviklingDato', NULL)
    , (44, 'underTvangsavviklingEllerTvangsopplosning', NULL)
    , (45, 'tvangsopplostPgaManglendeDagligLederDato', NULL)
    , (46, 'tvangsopplostPgaManglendeRevisorDato', NULL)
    , (47, 'tvangsopplostPgaManglendeRegnskapDato', NULL)
    , (48, 'tvangsopplostPgaMangelfulltStyreDato', NULL)
    , (49, 'tvangsavvikletPgaManglendeSlettingDato', NULL)
    , (50, 'overordnetEnhet', NULL)
    , (51, 'maalform', NULL)
    , (52, 'vedtektsdato', NULL)
    , (53, 'vedtektsfestetFormaal', NULL)
    , (54, 'aktivitet', NULL)
), inserted_source_column AS (
    INSERT INTO public.custom_view_def_source_column (custom_view_def_id,column_name, priority)
    SELECT def.id, name_mapping.source_column_name, name_mapping.priority
    FROM def, name_mapping
    ORDER BY priority
   RETURNING *
), mapping AS (
    SELECT def.id
         , isc.id
         , cvdtc.id
    FROM def
       , name_mapping AS nm
       JOIN inserted_source_column AS isc
         ON isc.column_name = nm.source_column_name
       LEFT JOIN public.custom_view_def_target_column AS cvdtc
         ON cvdtc.column_name = nm.target_column_name
    WHERE cvdtc.target_table_id = def.target_table_id
)
INSERT INTO public.custom_view_def_mapping
    ( custom_view_def_id
    , source_column_id
    , target_column_id
    )
SELECT * FROM mapping
;


END;