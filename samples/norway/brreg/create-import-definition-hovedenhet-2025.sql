-- Pretend the user has clicked and created import definition for BRREG Hovedenhet (legal_unit)

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
        , 'brreg_hovedenhet_2025'
        , 'Import of BRREG Hovedenhet using 2025 columns'
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
    , ('registreringsdatoAntallAnsatteEnhetsregisteret', NULL, NULL)
    , ('registreringsdatoantallansatteNAVAaregisteret', NULL, NULL)
    , ('hjemmeside', NULL, NULL)
    , ('epostadresse', NULL, NULL)
    , ('telefon', NULL, NULL)
    , ('mobil', NULL, NULL)
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
    , ('registreringsdatoMerverdiavgiftsregisteret', NULL, NULL)
    , ('registreringsdatoMerverdiavgiftsregisteretEnhetsregisteret', NULL, NULL)
    , ('frivilligMvaRegistrertBeskrivelser', NULL, NULL)
    , ('registreringsdatoFrivilligMerverdiavgiftsregisteret', NULL, NULL)
    , ('registrertIFrivillighetsregisteret', NULL, NULL)
    , ('registreringsdatoFrivillighetsregisteret', NULL, NULL)
    , ('registrertIForetaksregisteret', NULL, NULL)
    , ('registreringsdatoForetaksregisteret', NULL, NULL)
    , ('registrertIStiftelsesregisteret', NULL, NULL)
    , ('registrertIPartiregisteret', NULL, NULL)
    , ('registreringsdatoPartiregisteret', NULL, NULL)
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
    , ('registreringsnummerIHjemlandet', NULL, NULL)
    , ('paategninger', NULL, NULL)
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
WHERE d.slug = 'brreg_hovedenhet_2025';

UPDATE public.import_definition
SET draft = false
WHERE draft
  AND slug = 'brreg_hovedenhet_2025';
