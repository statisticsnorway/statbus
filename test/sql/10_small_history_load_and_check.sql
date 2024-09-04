BEGIN;

\echo "Setting up Statbus for Norway"
\i samples/norway/setup.sql

\echo "Adding tags for insert into right part of history"
\i samples/norway/small-history/add-tags.sql


CREATE TEMP TABLE import_small_history (
    organisasjonsnummer TEXT,
    navn TEXT,
    organisasjonsform_kode TEXT,
    organisasjonsform_beskrivelse TEXT,
    naeringskode1_kode TEXT,
    naeringskode1_beskrivelse TEXT,
    naeringskode2_kode TEXT,
    naeringskode2_beskrivelse TEXT,
    naeringskode3_kode TEXT,
    naeringskode3_beskrivelse TEXT,
    hjelpeenhetskode_kode TEXT,
    hjelpeenhetskode_beskrivelse TEXT,
    harRegistrertAntallAnsatte TEXT,
    antallAnsatte TEXT,
    hjemmeside TEXT,
    postadresse_adresse TEXT,
    postadresse_poststed TEXT,
    postadresse_postnummer TEXT,
    postadresse_kommune TEXT,
    postadresse_kommunenummer TEXT,
    postadresse_land TEXT,
    postadresse_landkode TEXT,
    forretningsadresse_adresse TEXT,
    forretningsadresse_poststed TEXT,
    forretningsadresse_postnummer TEXT,
    forretningsadresse_kommune TEXT,
    forretningsadresse_kommunenummer TEXT,
    forretningsadresse_land TEXT,
    forretningsadresse_landkode TEXT,
    institusjonellSektorkode_kode TEXT,
    institusjonellSektorkode_beskrivelse TEXT,
    sisteInnsendteAarsregnskap TEXT,
    registreringsdatoenhetsregisteret TEXT,
    stiftelsesdato TEXT,
    registrertIMvaRegisteret TEXT,
    frivilligMvaRegistrertBeskrivelser TEXT,
    registrertIFrivillighetsregisteret TEXT,
    registrertIForetaksregisteret TEXT,
    registrertIStiftelsesregisteret TEXT,
    konkurs TEXT,
    konkursdato TEXT,
    underAvvikling TEXT,
    underAvviklingDato TEXT,
    underTvangsavviklingEllerTvangsopplosning TEXT,
    tvangsopplostPgaManglendeDagligLederDato TEXT,
    tvangsopplostPgaManglendeRevisorDato TEXT,
    tvangsopplostPgaManglendeRegnskapDato TEXT,
    tvangsopplostPgaMangelfulltStyreDato TEXT,
    tvangsavvikletPgaManglendeSlettingDato TEXT,
    overordnetEnhet TEXT,
    maalform TEXT,
    vedtektsdato TEXT,
    vedtektsfestetFormaal TEXT,
    aktivitet TEXT
);


CREATE TEMP TABLE prepared_small_history (
    valid_from DATE,
    valid_to DATE,
    organisasjonsnummer TEXT,
    navn TEXT,
    forretningsadresse_adresse TEXT,
    forretningsadresse_postnummer TEXT,
    forretningsadresse_poststed TEXT,
    forretningsadresse_kommunenummer TEXT,
    forretningsadresse_landkode TEXT,
    postadresse_adresse TEXT,
    postadresse_postnummer TEXT,
    postadresse_poststed TEXT,
    postadresse_kommunenummer TEXT,
    postadresse_landkode TEXT,
    naeringskode1_kode TEXT,
    antallAnsatte TEXT
);

\echo "Loading historical units"
\copy import_small_history FROM 'samples/norway/small-history/2015-enheter.csv' WITH CSV HEADER;

INSERT INTO prepared_small_history (
    valid_from,
    valid_to,
    organisasjonsnummer,
    navn,
    forretningsadresse_adresse,
    forretningsadresse_postnummer,
    forretningsadresse_poststed,
    forretningsadresse_kommunenummer,
    forretningsadresse_landkode,
    postadresse_adresse,
    postadresse_postnummer,
    postadresse_poststed,
    postadresse_kommunenummer,
    postadresse_landkode,
    naeringskode1_kode,
    antallAnsatte
)
SELECT
    '2015-01-01'::DATE AS valid_from,
    'infinity'::DATE AS valid_to,
    organisasjonsnummer,
    navn,
    forretningsadresse_adresse,
    forretningsadresse_postnummer,
    forretningsadresse_poststed,
    forretningsadresse_kommunenummer,
    forretningsadresse_landkode,
    postadresse_adresse,
    postadresse_postnummer,
    postadresse_poststed,
    postadresse_kommunenummer,
    postadresse_landkode,
    naeringskode1_kode,
    antallAnsatte
FROM import_small_history;
TRUNCATE import_small_history;

\copy import_small_history FROM 'samples/norway/small-history/2016-enheter.csv' WITH CSV HEADER;
INSERT INTO prepared_small_history (
    valid_from,
    valid_to,
    organisasjonsnummer,
    navn,
    forretningsadresse_adresse,
    forretningsadresse_postnummer,
    forretningsadresse_poststed,
    forretningsadresse_kommunenummer,
    forretningsadresse_landkode,
    postadresse_adresse,
    postadresse_postnummer,
    postadresse_poststed,
    postadresse_kommunenummer,
    postadresse_landkode,
    naeringskode1_kode,
    antallAnsatte
)
SELECT
    '2016-01-01'::DATE AS valid_from,
    'infinity'::DATE AS valid_to,
    organisasjonsnummer,
    navn,
    forretningsadresse_adresse,
    forretningsadresse_postnummer,
    forretningsadresse_poststed,
    forretningsadresse_kommunenummer,
    forretningsadresse_landkode,
    postadresse_adresse,
    postadresse_postnummer,
    postadresse_poststed,
    postadresse_kommunenummer,
    postadresse_landkode,
    naeringskode1_kode,
    antallAnsatte
FROM import_small_history;
TRUNCATE import_small_history;

\copy import_small_history FROM 'samples/norway/small-history/2017-enheter.csv' WITH CSV HEADER;
INSERT INTO prepared_small_history (
    valid_from,
    valid_to,
    organisasjonsnummer,
    navn,
    forretningsadresse_adresse,
    forretningsadresse_postnummer,
    forretningsadresse_poststed,
    forretningsadresse_kommunenummer,
    forretningsadresse_landkode,
    postadresse_adresse,
    postadresse_postnummer,
    postadresse_poststed,
    postadresse_kommunenummer,
    postadresse_landkode,
    naeringskode1_kode,
    antallAnsatte
)
SELECT
    '2017-01-01'::DATE AS valid_from,
    'infinity'::DATE AS valid_to,
    organisasjonsnummer,
    navn,
    forretningsadresse_adresse,
    forretningsadresse_postnummer,
    forretningsadresse_poststed,
    forretningsadresse_kommunenummer,
    forretningsadresse_landkode,
    postadresse_adresse,
    postadresse_postnummer,
    postadresse_poststed,
    postadresse_kommunenummer,
    postadresse_landkode,
    naeringskode1_kode,
    antallAnsatte
FROM import_small_history;
TRUNCATE import_small_history;

\copy import_small_history FROM 'samples/norway/small-history/2018-enheter.csv' WITH CSV HEADER;
INSERT INTO prepared_small_history (
    valid_from,
    valid_to,
    organisasjonsnummer,
    navn,
    forretningsadresse_adresse,
    forretningsadresse_postnummer,
    forretningsadresse_poststed,
    forretningsadresse_kommunenummer,
    forretningsadresse_landkode,
    postadresse_adresse,
    postadresse_postnummer,
    postadresse_poststed,
    postadresse_kommunenummer,
    postadresse_landkode,
    naeringskode1_kode,
    antallAnsatte
)
SELECT
    '2018-01-01'::DATE AS valid_from,
    'infinity'::DATE AS valid_to,
    organisasjonsnummer,
    navn,
    forretningsadresse_adresse,
    forretningsadresse_postnummer,
    forretningsadresse_poststed,
    forretningsadresse_kommunenummer,
    forretningsadresse_landkode,
    postadresse_adresse,
    postadresse_postnummer,
    postadresse_poststed,
    postadresse_kommunenummer,
    postadresse_landkode,
    naeringskode1_kode,
    antallAnsatte
FROM import_small_history;
TRUNCATE import_small_history;

INSERT INTO public.import_legal_unit_era (
    valid_from,
    valid_to,
    tax_ident,
    name,
    physical_address_part1,
    physical_postal_code,
    physical_postal_place,
    physical_region_code,
    physical_country_iso_2,
    postal_address_part1,
    postal_postal_code,
    postal_postal_place,
    postal_region_code,
    postal_country_iso_2,
    primary_activity_category_code,
    employees
)
SELECT
    valid_from,
    valid_to,
    organisasjonsnummer,
    navn,
    forretningsadresse_adresse,
    forretningsadresse_postnummer,
    forretningsadresse_poststed,
    forretningsadresse_kommunenummer,
    forretningsadresse_landkode,
    postadresse_adresse,
    postadresse_postnummer,
    postadresse_poststed,
    postadresse_kommunenummer,
    postadresse_landkode,
    naeringskode1_kode,
    antallAnsatte
FROM prepared_small_history
ORDER BY valid_from, organisasjonsnummer;

\echo Refreshing materialized views
SELECT view_name FROM statistical_unit_refresh_now();

\x
SELECT valid_after
     , valid_from
     , valid_to
     , unit_type
     , external_idents
     , jsonb_pretty(
          public.remove_ephemeral_data_from_hierarchy(
          to_jsonb(statistical_unit.*)
          -'stats'
          -'stats_summary'
          -'valid_after'
          -'valid_from'
          -'valid_to'
          -'unit_type'
          -'external_idents'
          )
     ) AS statistical_unit_data
     , jsonb_pretty(stats) AS stats
     , jsonb_pretty(stats_summary) AS stats_summary
 FROM public.statistical_unit
 ORDER BY unit_type, unit_id, valid_from, valid_to;
\x


ROLLBACK;