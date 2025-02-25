BEGIN;

\i test/setup.sql

\echo public.import_target
CREATE TABLE public.import_target(
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    schema_name text NOT NULL,
    table_name text,
    name text UNIQUE NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW(),
    UNIQUE (schema_name, table_name)
);
INSERT INTO public.import_target (schema_name,table_name, name)
VALUES
    ('public','import_legal_unit_era', 'Legal Unit')
    ,('public','import_establishment_era_for_legal_unit', 'Formal Establishment for Legal Unit')
    ,('public','import_establishment_era_without_legal_unit', 'Informal Establishment without Legal Unit')
   ;

\echo public.import_target_column
CREATE TABLE public.import_target_column(
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    target_id int REFERENCES public.import_target(id),
    column_name text NOT NULL,
    column_type text NOT NULL,
    uniquely_identifying boolean NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW()
);
WITH cols AS (
     SELECT it.id AS target_id
          , column_name
          , data_type AS column_type
          , is_nullable
          , EXISTS (SELECT * FROM public.external_ident_type WHERE code = column_name) AS uniquely_identifying
          , ROW_NUMBER() OVER (PARTITION BY it.id ORDER BY ordinal_position) AS priority
      FROM information_schema.columns AS c
      JOIN public.import_target AS it
        ON c.table_schema = it.schema_name
        AND c.table_name = it.table_name
      ORDER BY target_id, ordinal_position
) INSERT INTO public.import_target_column(target_id, column_name, column_type, uniquely_identifying)
  SELECT target_id, column_name, column_type, uniquely_identifying
  FROM cols
  ;

SELECT it.schema_name || '.' || it.table_name AS target_table_name
     , itc.column_name
     , itc.column_type
     , itc.uniquely_identifying
FROM public.import_target_column itc
JOIN public.import_target it ON it.id = itc.target_id
ORDER BY it.id, it.table_name, itc.column_name;

\echo public.import_definition
CREATE TABLE public.import_definition(
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    slug text UNIQUE NOT NULL,
    name text UNIQUE NOT NULL,
    target_id int REFERENCES public.import_target(id),
    note text,
    data_source_id integer REFERENCES public.data_source(id) ON DELETE RESTRICT,
    time_context_ident TEXT, -- For lookup in public.time_context(ident) to get computed valid_from/valid_to
    user_id integer REFERENCES public.statbus_user(id) ON DELETE SET NULL,
    draft boolean NOT NULL DEFAULT true,
    valid boolean NOT NULL DEFAULT false,
    validation_error text,
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW(),
    CONSTRAINT draft_valid_error_states CHECK (
        CASE WHEN draft THEN NOT valid
            WHEN NOT draft THEN valid AND validation_error IS NULL
            ELSE false                             -- All other combinations forbidden
        END
    )
);
CREATE INDEX ix_import_user_id ON public.import_definition USING btree (user_id);
CREATE INDEX ix_import_data_source_id ON public.import_definition USING btree (data_source_id);


CREATE OR REPLACE FUNCTION admin.import_definition_validate_before()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    target_has_temporal boolean;
    missing_temporal text[];
BEGIN
    -- Skip validation if in draft mode
    IF NEW.draft THEN
        RETURN NEW;
    END IF;

    -- Check if target table has temporal columns
    SELECT EXISTS (
        SELECT 1 FROM public.import_target_column
        WHERE target_id = NEW.target_id
        AND column_name IN ('valid_from', 'valid_to')
    ) INTO target_has_temporal;

    IF NOT target_has_temporal THEN
        -- No temporal columns needed, validation passes
        NEW.valid := true;
        NEW.validation_error := NULL;
        RETURN NEW;
    END IF;

    -- Check which temporal columns are missing mappings
    SELECT array_agg(column_name)
    FROM public.import_target_column itc
    WHERE itc.target_id = NEW.target_id
    AND itc.column_name IN ('valid_from', 'valid_to')
    AND NOT EXISTS (
        SELECT 1 FROM public.import_mapping im
        WHERE im.target_column_id = itc.id
        AND im.definition_id = NEW.id
        AND (
            im.source_column_id IS NOT NULL OR
            im.source_expression = 'default'::import_source_expression OR
            im.source_value IS NOT NULL
        )
    ) INTO missing_temporal;

    -- Set validation results on NEW record
    NEW.valid := (missing_temporal IS NULL);
    NEW.validation_error := CASE
        WHEN missing_temporal IS NULL THEN NULL
        ELSE format(
            'Missing required mappings for temporal columns: %s. Either map source columns or use ''default'' expression',
            array_to_string(missing_temporal, ', ')
        )
    END;
    NEW.draft := CASE
        WHEN missing_temporal IS NULL THEN false
        ELSE true
    END;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION validate_time_context_ident()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.time_context_ident IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.time_context WHERE ident = NEW.time_context_ident) THEN
        RAISE EXCEPTION 'Invalid time_context_ident: %', NEW.time_context_ident;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER validate_time_context_ident_trigger
    BEFORE INSERT OR UPDATE OF time_context_ident ON public.import_definition
    FOR EACH ROW
    EXECUTE FUNCTION validate_time_context_ident();

CREATE TRIGGER validate_on_draft_change
    BEFORE UPDATE OF draft ON public.import_definition
    FOR EACH ROW
    WHEN (OLD.draft = true AND NEW.draft = false)
    EXECUTE FUNCTION admin.import_definition_validate_before();

CREATE OR REPLACE FUNCTION admin.prevent_changes_to_non_draft_definition()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    def public.import_definition;
BEGIN
    IF TG_TABLE_NAME = 'import_definition' THEN
        -- For direct changes to import_definition
        IF NOT NEW.draft AND OLD.draft = NEW.draft THEN
            RAISE EXCEPTION 'Can only modify import definition % when in draft mode', OLD.id;
        END IF;
    ELSE
        -- For changes to related tables (mapping, source_column)
        SELECT * INTO def FROM public.import_definition WHERE id =
            CASE TG_TABLE_NAME
                WHEN 'import_mapping' THEN
                    CASE TG_OP
                        WHEN 'DELETE' THEN OLD.definition_id
                        ELSE NEW.definition_id
                    END
                WHEN 'import_source_column' THEN NEW.definition_id
            END;

        IF NOT def.draft THEN
            RAISE EXCEPTION 'Can only modify % for import definition % when in draft mode',
                TG_TABLE_NAME, def.id;
        END IF;
    END IF;
    RETURN CASE TG_OP WHEN 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

CREATE TRIGGER prevent_non_draft_changes
    BEFORE UPDATE ON public.import_definition
    FOR EACH ROW
    EXECUTE FUNCTION admin.prevent_changes_to_non_draft_definition();

\echo public.import_source_column
CREATE TABLE public.import_source_column(
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    definition_id int REFERENCES public.import_definition(id),
    column_name text NOT NULL,
    priority int NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW()
);
COMMENT ON COLUMN public.import_source_column.priority IS 'The ordering of the columns in the CSV file.';

CREATE TRIGGER prevent_non_draft_source_column_changes
    BEFORE INSERT OR UPDATE OR DELETE ON public.import_source_column
    FOR EACH ROW
    EXECUTE FUNCTION admin.prevent_changes_to_non_draft_definition();


\echo public.import_mapping
CREATE TYPE public.import_source_expression AS ENUM ('now', 'default');

CREATE TABLE public.import_mapping(
    definition_id int NOT NULL REFERENCES public.import_definition(id),
    source_column_id int REFERENCES public.import_source_column(id),
    CONSTRAINT unique_source_column_mapping UNIQUE (definition_id, source_column_id),
    source_value TEXT,
    source_expression public.import_source_expression,
    target_column_id int REFERENCES public.import_target_column(id),
    CONSTRAINT unique_target_column_mapping UNIQUE (definition_id, target_column_id),
    CONSTRAINT "only_one_source_can_be_defined"
    CHECK( source_column_id IS NOT NULL AND source_value IS     NULL AND source_expression IS     NULL
        OR source_column_id IS     NULL AND source_value IS NOT NULL AND source_expression IS     NULL
        OR source_column_id IS     NULL AND source_value IS     NULL AND source_expression IS NOT NULL
        ),
    CONSTRAINT "at_least_one_column_must_be_defined" CHECK(
      source_column_id IS NOT NULL OR target_column_id IS NOT NULL
    ),
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    updated_at timestamp with time zone NOT NULL DEFAULT NOW()
);

CREATE TRIGGER prevent_non_draft_mapping_changes
    BEFORE INSERT OR UPDATE OR DELETE ON public.import_mapping
    FOR EACH ROW
    EXECUTE FUNCTION admin.prevent_changes_to_non_draft_definition();


\echo public.import_job_status
CREATE TYPE public.import_job_status AS ENUM ('waiting_for_upload', 'analysing_data', 'waiting_for_approval', 'importing_data', 'finished');

\echo public.import_job
CREATE TABLE public.import_job (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    slug varchar,
    description text,
    note text,
    default_valid_from DATE,
    default_valid_to DATE,
    upload_table_name text NOT NULL,
    data_table_name text NOT NULL,
    analysis_start_at timestamp with time zone,
    analysis_stop_at timestamp with time zone,
    changes_approved_at timestamp with time zone,
    import_start_at timestamp with time zone,
    import_stop_at timestamp with time zone,
    status public.import_job_status NOT NULL DEFAULT 'waiting_for_upload',
    definition_id integer NOT NULL REFERENCES public.import_definition(id) ON DELETE CASCADE,
    user_id integer REFERENCES public.statbus_user(id) ON DELETE SET NULL
);
CREATE INDEX ix_import_job_definition_id ON public.import_job USING btree (definition_id);
CREATE INDEX ix_import_job_user_id ON public.import_job USING btree (user_id);

-- Create function to set default slug
CREATE OR REPLACE FUNCTION admin.import_job_derive()
RETURNS TRIGGER LANGUAGE plpgsql AS $import_job_derive$
DECLARE
    definition public.import_definition;
BEGIN
    SELECT * INTO definition
    FROM public.import_definition
    WHERE id = NEW.definition_id;

    IF NOT definition.valid THEN
        RAISE EXCEPTION 'Cannot create import job for invalid import_definition % (%): %',
            definition.id, definition.name, COALESCE(definition.validation_error,'Is still draft');
    END IF;

    IF NEW.slug IS NULL THEN
        NEW.slug := format('import_job_%s', NEW.id);
    END IF;

    NEW.upload_table_name := format('%s_upload', NEW.slug);
    NEW.data_table_name := format('%s_data', NEW.slug);

    -- Set default validity dates from time context if available and not already set
    IF NEW.default_valid_from IS NULL OR NEW.default_valid_to IS NULL THEN
        SELECT tc.valid_from, tc.valid_to
        INTO NEW.default_valid_from, NEW.default_valid_to
        FROM public.import_definition id
        LEFT JOIN public.time_context tc ON tc.ident = id.time_context_ident
        WHERE id.id = NEW.definition_id;
    END IF;

    RETURN NEW;
END;
$import_job_derive$;

-- Create trigger to set slug before insert
CREATE TRIGGER import_job_derive_trigger
    BEFORE INSERT ON public.import_job
    FOR EACH ROW
    EXECUTE FUNCTION admin.import_job_derive();

-- Create functions to manage import job tables and views
CREATE OR REPLACE FUNCTION admin.import_job_generate()
RETURNS TRIGGER LANGUAGE plpgsql AS $import_job_generate$
BEGIN
    PERFORM admin.import_job_generate(NEW);
    RETURN NEW;
END;
$import_job_generate$;

-- Create trigger to create objects when job is inserted
CREATE TRIGGER import_job_generate
    AFTER INSERT OR UPDATE OF upload_table_name, data_table_name ON public.import_job
    FOR EACH ROW
    EXECUTE FUNCTION admin.import_job_generate();

-- Function to clean up job objects
CREATE OR REPLACE FUNCTION admin.import_job_cleanup()
RETURNS TRIGGER AS $import_job_cleanup$
BEGIN
    -- Drop the view first since it depends on the table
    EXECUTE format('DROP VIEW IF EXISTS public.%I', OLD.import_view);
    EXECUTE format('DROP TABLE IF EXISTS public.%I', OLD.import_table);

    RETURN OLD;
END;
$import_job_cleanup$ LANGUAGE plpgsql;

-- Create trigger to clean up objects when job is deleted
CREATE TRIGGER import_job_cleanup
    BEFORE UPDATE OF upload_table_name, data_table_name OR DELETE ON public.import_job
    FOR EACH ROW
    EXECUTE FUNCTION admin.import_job_cleanup();


SELECT admin.add_rls_regular_user_can_read('public.import_target'::regclass);
SELECT admin.add_rls_regular_user_can_read('public.import_target_column'::regclass);
SELECT admin.add_rls_regular_user_can_read('public.import_definition'::regclass);
SELECT admin.add_rls_regular_user_can_read('public.import_source_column'::regclass);
SELECT admin.add_rls_regular_user_can_read('public.import_mapping'::regclass);
SELECT admin.add_rls_regular_user_can_edit('public.import_job'::regclass);

\echo public.import_information
CREATE VIEW public.import_information WITH (security_barrier = true) AS
    SELECT ij.id AS job_id
    , id.id AS definition_id
    , ij.slug AS import_job_slug
    , id.slug AS import_definition_slug
    , id.name AS import_name
    , id.note AS import_note
    , it.schema_name AS target_schema_name
    , ij.upload_table_name AS upload_table_name
    , ij.data_table_name AS data_table_name
    , isc.column_name AS source_column
    , im.source_value AS source_value
    , im.source_expression AS source_expression
    , itc.column_name AS target_column
    , itc.column_type AS target_type
    , itc.uniquely_identifying AS uniquely_identifying
    , isc.priority AS source_column_priority
    FROM public.import_job ij
    JOIN public.import_definition id ON ij.definition_id = id.id
    JOIN public.import_target it ON id.target_id = it.id
    JOIN public.import_mapping im ON id.id = im.definition_id
    LEFT OUTER JOIN public.import_source_column isc ON im.source_column_id = isc.id
    LEFT OUTER JOIN public.import_target_column itc ON im.target_column_id = itc.id
    ORDER BY id.id ASC
           , ij.id ASC
           , isc.priority ASC NULLS LAST
           , isc.id ASC
           , itc.id ASC
;


\echo admin.import_job_generate
/*
Each import operates on it's on table.
The table is unlogged for good performance on insert.
There is a view that maps from the columns names of the upload to the column names of the table.
*/
CREATE OR REPLACE FUNCTION admin.import_job_generate(job public.import_job)
RETURNS void AS $import_job_generate$
DECLARE
    create_upload_table_stmt text;
    create_data_table_stmt text;
    create_data_indices_stmt text;
    add_separator BOOLEAN := FALSE;
    info RECORD;
BEGIN
  RAISE NOTICE 'Generating %', job.upload_table_name;
  -- Build the sql to create a table for this import job with target columns
  create_upload_table_stmt := format('CREATE UNLOGGED TABLE public.%I (', job.upload_table_name);

  -- Add columns from target table definition
  FOR info IN
      SELECT *
      FROM public.import_information AS ii
      WHERE ii.job_id = job.id
        AND source_column IS NOT NULL
  LOOP
    IF NOT add_separator THEN
        add_separator := true;
    ELSE
      -- Adds a comma after every line but the first.
        create_upload_table_stmt := create_upload_table_stmt || ',';
    END IF;

    create_upload_table_stmt := create_upload_table_stmt || format($format$
  %I TEXT$format$, info.source_column);
  END LOOP;
  create_upload_table_stmt := create_upload_table_stmt ||$EOS$
  );$EOS$;

  RAISE DEBUG '%', create_upload_table_stmt;
  EXECUTE create_upload_table_stmt;

  RAISE NOTICE 'Generating %', job.data_table_name;
  -- Build the sql to create a table for this import job with target columns
  create_data_table_stmt := format('CREATE UNLOGGED TABLE public.%I (', job.data_table_name);

  -- Add columns from target table definition
  add_separator := false;
  FOR info IN
      SELECT *
      FROM public.import_information AS ii
      WHERE ii.job_id = job.id
        AND target_column IS NOT NULL
  LOOP
    IF NOT add_separator THEN
        add_separator := true;
    ELSE
      -- Adds a comma after every line but the first.
        create_data_table_stmt := create_data_table_stmt || ',';
    END IF;

    create_data_table_stmt := create_data_table_stmt || format($format$
  %I %I$format$, info.target_column, info.target_type);
  END LOOP;
  create_data_table_stmt := create_data_table_stmt ||$EOS$
  );$EOS$;

  RAISE DEBUG '%', create_data_table_stmt;
  EXECUTE create_data_table_stmt;

  -- Add unique constraint on uniquely identifying columns
  create_data_indices_stmt := format('ALTER TABLE public.%I ADD CONSTRAINT %I_unique_key UNIQUE (',
    job.data_table_name,
    job.data_table_name
  );

  -- Add columns to unique constraint
  add_separator := false;
  FOR info IN
      SELECT *
      FROM public.import_information AS ii
      WHERE ii.job_id = job.id
        AND uniquely_identifying = TRUE
        AND target_column IS NOT NULL
  LOOP
    IF NOT add_separator THEN
        add_separator := true;
    ELSE
        create_data_indices_stmt := create_data_indices_stmt || ', ';
    END IF;

    create_data_indices_stmt := create_data_indices_stmt || format('%I', info.target_column);
  END LOOP;

  create_data_indices_stmt := create_data_indices_stmt || ');';

  RAISE DEBUG '%', create_data_indices_stmt;
  EXECUTE create_data_indices_stmt;

  PERFORM admin.add_rls_regular_user_can_edit(info.upload_table_name::regclass);
  PERFORM admin.add_rls_regular_user_can_edit(info.data_table_name::regclass);

END;
$import_job_generate$ LANGUAGE plpgsql;

\echo admin.import_job_cleanup
CREATE OR REPLACE FUNCTION admin.import_job_cleanup(job public.import_job)
RETURNS void AS $import_job_cleanup$
BEGIN
    EXECUTE format('DROP TABLE public.%I', job.upload_table_name);
    EXECUTE format('DROP TABLE public.%I', job.data_table_name);
END;
$import_job_cleanup$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION admin.import_job_process(job_id integer)
RETURNS void LANGUAGE plpgsql AS $import_job_process$
DECLARE
    job public.import_job;
    merge_stmt text;
    add_separator BOOLEAN := FALSE;
    info RECORD;
BEGIN
    -- Get the job details
    SELECT * INTO job FROM public.import_job WHERE id = job_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Import job % not found', job_id;
    END IF;

    /*
    -- Example of generated merge statement:
    INSERT INTO public.import_job_123_data_table (
      tax_ident, name, legal_form_code, primary_activity_category_code
    ) SELECT
      tax_ident, name, legal_form_code, primary_activity_category_code
    FROM public.import_job_123_upload_table
    ON CONFLICT (tax_ident) DO UPDATE SET
      name = EXCLUDED.name,
      legal_form_code = EXCLUDED.legal_form_code,
      primary_activity_category_code = EXCLUDED.primary_activity_category_code;
     */

    -- Build dynamic INSERT statement with ON CONFLICT handling
    merge_stmt := format('INSERT INTO public.%I (', job.data_table_name);

    -- Add target columns
    add_separator := FALSE;
    FOR info IN
        SELECT * FROM public.import_information AS ii
        WHERE ii.job_id = job.id
          AND target_column IS NOT NULL
    LOOP
        IF NOT add_separator THEN
            add_separator := true;
        ELSE
            merge_stmt := merge_stmt || ', ';
        END IF;

        merge_stmt := merge_stmt || format('%I', info.target_column);
    END LOOP;

    merge_stmt := merge_stmt || format(') SELECT ');

    -- Add source columns, values and expressions
    add_separator := FALSE;
    FOR info IN
        SELECT *
        FROM public.import_information AS ii
        WHERE ii.job_id = job.id
          AND target_column IS NOT NULL
          AND (source_column IS NOT NULL
               OR source_value IS NOT NULL
               OR source_expression IS NOT NULL)
    LOOP
        IF NOT add_separator THEN
            add_separator := true;
        ELSE
            merge_stmt := merge_stmt || ', ';
        END IF;

        CASE
            WHEN info.source_value IS NOT NULL THEN
                merge_stmt := merge_stmt || quote_literal(info.source_value);
            WHEN info.source_expression IS NOT NULL THEN
                merge_stmt := merge_stmt || CASE info.source_expression
                    WHEN 'now' THEN 'statement_timestamp()'
                    WHEN 'default' THEN
                        CASE info.target_column
                            WHEN 'valid_from' THEN quote_literal(job.default_valid_from)
                            WHEN 'valid_to' THEN quote_literal(job.default_valid_to)
                            ELSE 'NULL'
                        END
                    ELSE 'NULL'
                    END;
            WHEN info.source_column IS NOT NULL THEN
                merge_stmt := merge_stmt || CASE info.target_column
                    WHEN 'valid_from' THEN format('COALESCE(NULLIF(%I,%L), %L)', info.source_column, '', job.default_valid_from)
                    WHEN 'valid_to' THEN format('COALESCE(NULLIF(%I,%L), %L)', info.source_column, '', job.default_valid_to)
                    ELSE format('NULLIF(%I,%L)', info.source_column, '')
                    END;
            ELSE
                RAISE EXCEPTION 'No valid source (column/value/expression) found for job %', job_id;
        END CASE;
    END LOOP;

    merge_stmt := merge_stmt || format(' FROM public.%I ', job.upload_table_name);

    -- Add ON CONFLICT clause using uniquely identifying columns
    merge_stmt := merge_stmt || ' ON CONFLICT (';

    add_separator := FALSE;
    FOR info IN
        SELECT *
        FROM public.import_information AS ii
        WHERE ii.job_id = job.id
          AND uniquely_identifying = TRUE
          AND target_column IS NOT NULL
    LOOP
        IF NOT add_separator THEN
            add_separator := true;
        ELSE
            merge_stmt := merge_stmt || ', ';
        END IF;

        merge_stmt := merge_stmt || format('%I', info.target_column);
    END LOOP;

    merge_stmt := merge_stmt || ') DO UPDATE SET ';

    -- Add update assignments
    add_separator := FALSE;
    FOR info IN
        SELECT *
        FROM public.import_information AS ii
        WHERE ii.job_id = job.id
          AND source_column IS NOT NULL
          AND target_column IS NOT NULL
          AND NOT uniquely_identifying
    LOOP
        IF NOT add_separator THEN
            add_separator := true;
        ELSE
            merge_stmt := merge_stmt || ', ';
        END IF;

        merge_stmt := merge_stmt || format('%I = EXCLUDED.%I',
                                         info.target_column,
                                         info.target_column);
    END LOOP;

    -- Execute the insert
    RAISE DEBUG 'Executing upsert: %', merge_stmt;
    EXECUTE merge_stmt;

    DECLARE
      data_table_count INT;
    BEGIN
      EXECUTE format('SELECT count(*) FROM public.%I', job.data_table_name) INTO data_table_count;
      RAISE DEBUG 'There are % rows in %', data_table_count, job.data_table_name;
    END;

    -- TODO: Validate the data_ table using the standardised column names, column by column in batches.

    -- Insert validated data into target table
    DECLARE
      target RECORD;
      target_columns TEXT;
      insert_stmt TEXT;
    BEGIN
        SELECT it.* INTO target
        FROM public.import_definition AS id
        JOIN public.import_target AS it ON id.target_id = it.id
        WHERE id.id = job.definition_id;

        SELECT string_agg(quote_ident(target_column), ',') INTO target_columns
           FROM public.import_information AS ii
           WHERE ii.job_id = job.definition_id
           AND target_column IS NOT NULL;

        insert_stmt := format($format$
          INSERT INTO %I.%I (%s)
          SELECT %s FROM public.%I;
        $format$
        , target.schema_name
        , target.table_name
        , target_columns
        , target_columns
        , job.data_table_name
        );

        RAISE DEBUG 'Executing %', insert_stmt;
        EXECUTE insert_stmt;
    END;
END;
$import_job_process$;


-- Pretend the user has clicked and created an import definition.

WITH it AS (
    SELECT * FROM public.import_target
    WHERE schema_name = 'public'
      AND table_name = 'import_legal_unit_era'
), def AS (
    INSERT INTO public.import_definition
        ( target_id
        , slug
        , name
        , note
        )
    SELECT it.id
        , 'brreg_hovedenhet'
        , 'Import of BRREG Hovedenhet'
        , 'Easy upload of the CSV file found at brreg.'
    FROM it
    RETURNING *
), raw_mapping(source_column_name, source_expression, target_column_name) AS (
VALUES
      (NULL, 'default'::public.import_source_expression, 'valid_from')
      , (NULL, 'default'::public.import_source_expression, 'valid_to')
    , ('organisasjonsnummer', NULL, 'tax_ident')
    , ('navn', NULL, 'name')
    , ('organisasjonsform.kode', NULL, 'legal_form_code')
    , ('organisasjonsform.beskrivelse', NULL, NULL)
    , ('naeringskode1.kode', NULL, 'primary_activity_category_code')
    , ('naeringskode1.beskrivelse', NULL, NULL)
    , ('naeringskode2.kode', NULL, 'secondary_activity_category_code')
    , ('naeringskode2.beskrivelse', NULL, NULL)
    , ('naeringskode3.kode', NULL, NULL)
    , ('naeringskode3.beskrivelse', NULL, NULL)
    , ('hjelpeenhetskode.kode', NULL, NULL)
    , ('hjelpeenhetskode.beskrivelse', NULL, NULL)
    , ('harRegistrertAntallAnsatte', NULL, NULL)
    , ('antallAnsatte', NULL, NULL)
    , ('hjemmeside', NULL, NULL)
    , ('postadresse.adresse', NULL, 'postal_address_part1')
    , ('postadresse.poststed', NULL, 'postal_postplace')
    , ('postadresse.postnummer', NULL, 'postal_postcode')
    , ('postadresse.kommune', NULL, NULL)
    , ('postadresse.kommunenummer', NULL, 'postal_region_code')
    , ('postadresse.land', NULL, NULL)
    , ('postadresse.landkode', NULL, 'postal_country_iso_2')
    , ('forretningsadresse.adresse', NULL, 'physical_address_part1')
    , ('forretningsadresse.poststed', NULL, 'physical_postplace')
    , ('forretningsadresse.postnummer', NULL, 'physical_postcode')
    , ('forretningsadresse.kommune', NULL, NULL)
    , ('forretningsadresse.kommunenummer', NULL, 'physical_region_code')
    , ('forretningsadresse.land', NULL, NULL)
    , ('forretningsadresse.landkode', NULL, 'physical_country_iso_2')
    , ('institusjonellSektorkode.kode', NULL, 'sector_code')
    , ('institusjonellSektorkode.beskrivelse', NULL, NULL)
    , ('sisteInnsendteAarsregnskap', NULL, NULL)
    , ('registreringsdatoenhetsregisteret', NULL, NULL)
    , ('stiftelsesdato', NULL, 'birth_date')
    , ('registrertIMvaRegisteret', NULL, NULL)
    , ('frivilligMvaRegistrertBeskrivelser', NULL, NULL)
    , ('registrertIFrivillighetsregisteret', NULL, NULL)
    , ('registrertIForetaksregisteret', NULL, NULL)
    , ('registrertIStiftelsesregisteret', NULL, NULL)
    , ('konkurs', NULL, NULL)
    , ('konkursdato', NULL, NULL)
    , ('underAvvikling', NULL, NULL)
    , ('underAvviklingDato', NULL, NULL)
    , ('underTvangsavviklingEllerTvangsopplosning', NULL, NULL)
    , ('tvangsopplostPgaManglendeDagligLederDato', NULL, NULL)
    , ('tvangsopplostPgaManglendeRevisorDato', NULL, NULL)
    , ('tvangsopplostPgaManglendeRegnskapDato', NULL, NULL)
    , ('tvangsopplostPgaMangelfulltStyreDato', NULL, NULL)
    , ('tvangsavvikletPgaManglendeSlettingDato', NULL, NULL)
    , ('overordnetEnhet', NULL, NULL)
    , ('maalform', NULL, NULL)
    , ('vedtektsdato', NULL, NULL)
    , ('vedtektsfestetFormaal', NULL, NULL)
    , ('aktivitet', NULL, NULL)
), name_mapping AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as priority,
        source_column_name,
        source_expression,
        target_column_name
    FROM raw_mapping
), inserted_source_column AS (
    INSERT INTO public.import_source_column (definition_id,column_name, priority)
    SELECT def.id, name_mapping.source_column_name, name_mapping.priority
    FROM def, name_mapping
    WHERE source_column_name IS NOT NULL
    ORDER BY priority
   RETURNING *
), mapping AS (
    SELECT def.id
         , isc.id
         , nm.source_expression
         , itc.id
    FROM def
       , name_mapping AS nm
       LEFT JOIN inserted_source_column AS isc
         ON isc.column_name = nm.source_column_name
       LEFT JOIN public.import_target_column AS itc
       ON itc.column_name = nm.target_column_name
       WHERE itc.target_id IS NULL OR itc.target_id = def.target_id
), mapped AS (
  INSERT INTO public.import_mapping
      ( definition_id
      , source_column_id
      , source_expression
      , target_column_id
      )
      SELECT * FROM mapping
  RETURNING *
)
--SELECT * FROM mapped;
SELECT d.slug as definition_slug,
       sc.column_name as source_column,
       m.source_value,
       m.source_expression,
       tc.column_name
FROM mapped m
LEFT JOIN def d ON d.id = m.definition_id
LEFT JOIN inserted_source_column sc ON sc.id = m.source_column_id
LEFT JOIN public.import_target_column tc ON tc.id = m.target_column_id;

SELECT d.slug,
       d.name,
       t.table_name as target_table,
       d.note,
       ds.code as data_source,
       d.time_context_ident,
       d.draft,
       d.valid,
       d.validation_error
FROM public.import_definition d
JOIN public.import_target t ON t.id = d.target_id
LEFT JOIN public.data_source ds ON ds.id = d.data_source_id;

UPDATE public.import_definition
SET draft = false
WHERE draft;

SELECT d.slug,
       d.name,
       t.table_name as target_table,
       d.note,
       ds.code as data_source,
       d.time_context_ident,
       d.draft,
       d.valid,
       d.validation_error
FROM public.import_definition d
JOIN public.import_target t ON t.id = d.target_id
LEFT JOIN public.data_source ds ON ds.id = d.data_source_id;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_job_2015', '2015-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet', 'This job handles the import of BRREG Hovedenhet data.'
FROM def RETURNING *;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_job_2016', '2016-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet', 'This job handles the import of BRREG Hovedenhet data.'
FROM def RETURNING *;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_job_2017', '2017-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet', 'This job handles the import of BRREG Hovedenhet data.'
FROM def RETURNING *;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_job_2018', '2018-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet', 'This job handles the import of BRREG Hovedenhet data.'
FROM def RETURNING *;

\d public.import_job_2015_upload
\d public.import_job_2015_data

\echo Review public.import_information
SELECT import_job_slug, import_definition_slug, import_name, import_note, target_schema_name, upload_table_name, data_table_name, source_column, source_value, source_expression, target_column, target_type, uniquely_identifying, source_column_priority FROM public.import_information;

-- Disable RLS on import tables to support \copy
ALTER TABLE public.import_job_2015_upload DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.import_job_2016_upload DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.import_job_2017_upload DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.import_job_2018_upload DISABLE ROW LEVEL SECURITY;

-- A Super User configures statbus.
CALL test.set_user_from_email('test.super@statbus.org');

\echo "Setting up Statbus for Norway"
\i samples/norway/getting-started.sql

\echo "Adding tags for insert into right part of history"
\i samples/norway/small-history/add-tags.sql

\echo "Loading historical units"

\copy public.import_job_2015_upload FROM 'samples/norway/small-history/2015-enheter.csv' WITH CSV HEADER;
\copy public.import_job_2016_upload FROM 'samples/norway/small-history/2016-enheter.csv' WITH CSV HEADER;
\copy public.import_job_2017_upload FROM 'samples/norway/small-history/2017-enheter.csv' WITH CSV HEADER;
\copy public.import_job_2018_upload FROM 'samples/norway/small-history/2018-enheter.csv' WITH CSV HEADER;

-- Speed up changes by validating in the end.
SET CONSTRAINTS ALL DEFERRED;

SELECT admin.import_job_process(job.id) FROM public.import_job AS job order by id ASC;

-- Validate all inserted rows.
SET CONSTRAINTS ALL IMMEDIATE;

\echo Run worker processing to generate computed data
SELECT success, count(*) FROM worker.process_tasks() GROUP BY success;

\echo Getting statistical_units after upload
\x
SELECT valid_after
     , valid_from
     , valid_to
     , unit_type
     , external_idents
     , jsonb_pretty(
          public.remove_ephemeral_data_from_hierarchy(
          to_jsonb(statistical_unit.*)
          -'valid_after'
          -'valid_from'
          -'valid_to'
          -'unit_type'
          -'external_idents'
          -'stats'
          -'stats_summary'
          )
     ) AS statistical_unit_data
     , jsonb_pretty(stats) AS stats
     , jsonb_pretty(stats_summary) AS stats_summary
 FROM public.statistical_unit
 ORDER BY unit_type, unit_id, valid_from, valid_to;
\x


ROLLBACK;
