BEGIN;

\i test/setup.sql

-- Display all import definitions with their mappings
SELECT 
    id.slug AS import_definition_slug,
    id.name AS import_name,
    it.schema_name AS target_schema_name,
    it.table_name AS data_table_name,
    id.note AS import_note,
    isc.column_name AS source_column,
    itc.column_name AS target_column,
    im.source_expression,
    im.source_value,
    isc.priority AS source_column_priority
FROM public.import_definition id
JOIN public.import_target it ON id.target_id = it.id
LEFT JOIN public.import_mapping im ON id.id = im.definition_id
LEFT JOIN public.import_source_column isc ON im.source_column_id = isc.id
LEFT JOIN public.import_target_column itc ON im.target_column_id = itc.id
ORDER BY id.slug, isc.priority NULLS LAST;


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
       sc.priority AS source_column_priority,
       tc.column_name AS target_column
FROM mapped m
LEFT JOIN def d ON d.id = m.definition_id
LEFT JOIN inserted_source_column sc ON sc.id = m.source_column_id
LEFT JOIN public.import_target_column tc ON tc.id = m.target_column_id
ORDER BY source_column_priority, target_column;

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
LEFT JOIN public.data_source ds ON ds.id = d.data_source_id
WHERE d.slug = 'brreg_hovedenhet';

UPDATE public.import_definition
SET draft = false
WHERE draft
  AND slug = 'brreg_hovedenhet';

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
LEFT JOIN public.data_source ds ON ds.id = d.data_source_id
WHERE d.slug = 'brreg_hovedenhet';

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_job_2015', '2015-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet', 'This job handles the import of BRREG Hovedenhet data.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, import_information_snapshot_table_name, status;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_job_2016', '2016-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet', 'This job handles the import of BRREG Hovedenhet data.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, import_information_snapshot_table_name, status;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_job_2017', '2017-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet', 'This job handles the import of BRREG Hovedenhet data.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, import_information_snapshot_table_name, status;


WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_job_2018', '2018-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet', 'This job handles the import of BRREG Hovedenhet data.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, import_information_snapshot_table_name, status;

\d public.import_job_2015_upload
\d public.import_job_2015_data
\d public.import_job_2015_import_information_snapshot

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

-- Verify that snapshot tables were created
SELECT slug, import_information_snapshot_table_name 
FROM public.import_job
ORDER BY id;

-- Verify that the snapshot tables exist in the database
SELECT ij.slug, ij.import_information_snapshot_table_name, 
       CASE WHEN EXISTS (
           SELECT 1 FROM pg_tables 
           WHERE schemaname = 'public' AND tablename = ij.import_information_snapshot_table_name
       ) THEN 'exists' ELSE 'missing' END AS table_status
FROM public.import_job ij
ORDER BY ij.id;

-- Validate all inserted rows.
SET CONSTRAINTS ALL IMMEDIATE;

-- Process the import jobs
SELECT admin.import_job_process(job.id) FROM public.import_job AS job order by id ASC;

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
