BEGIN;

\echo "Setting up Statbus for Norway"
\i samples/norway/setup.sql

\echo "Adding tags for insert into right part of history"
\i samples/norway/small-history/add-tags.sql


CREATE TEMP TABLE prepared_small_history (
    valid_from DATE,
    valid_to DATE,
    tax_ident TEXT,
    name TEXT,
    physical_address_part1 TEXT,
    physical_postal_code TEXT,
    physical_postal_place TEXT,
    physical_region_code TEXT,
    physical_country_iso_2 TEXT,
    postal_address_part1 TEXT,
    postal_postal_code TEXT,
    postal_postal_place TEXT,
    postal_region_code TEXT,
    postal_country_iso_2 TEXT,
    primary_activity_category_code TEXT,
    employees TEXT
);

CREATE TEMP VIEW import_small_history AS
SELECT
    tax_ident AS organisasjonsnummer,
    name AS navn,
    ''::TEXT AS organisasjonsform_kode,
    ''::TEXT AS organisasjonsform_beskrivelse,
    primary_activity_category_code AS naeringskode1_kode,
    ''::TEXT AS naeringskode1_beskrivelse,
    ''::TEXT AS naeringskode2_kode,
    ''::TEXT AS naeringskode2_beskrivelse,
    ''::TEXT AS naeringskode3_kode,
    ''::TEXT AS naeringskode3_beskrivelse,
    ''::TEXT AS hjelpeenhetskode_kode,
    ''::TEXT AS hjelpeenhetskode_beskrivelse,
    ''::TEXT AS harRegistrertAntallAnsatte,
    employees AS antallAnsatte,
    ''::TEXT AS hjemmeside,
    postal_address_part1 AS postadresse_adresse,
    postal_postal_place AS postadresse_poststed,
    postal_postal_code AS postadresse_postnummer,
    ''::TEXT AS postadresse_kommune,
    postal_region_code AS postadresse_kommunenummer,
    ''::TEXT AS postadresse_land,
    postal_country_iso_2 AS postadresse_landkode,
    physical_address_part1 AS forretningsadresse_adresse,
    physical_postal_place AS forretningsadresse_poststed,
    physical_postal_code AS forretningsadresse_postnummer,
    ''::TEXT AS forretningsadresse_kommune,
    physical_region_code AS forretningsadresse_kommunenummer,
    ''::TEXT AS forretningsadresse_land,
    physical_country_iso_2 AS forretningsadresse_landkode,
    ''::TEXT AS institusjonellSektorkode_kode,
    ''::TEXT AS institusjonellSektorkode_beskrivelse,
    ''::TEXT AS sisteInnsendteAarsregnskap,
    ''::TEXT AS registreringsdatoenhetsregisteret,
    ''::TEXT AS stiftelsesdato,
    ''::TEXT AS registrertIMvaRegisteret,
    ''::TEXT AS frivilligMvaRegistrertBeskrivelser,
    ''::TEXT AS registrertIFrivillighetsregisteret,
    ''::TEXT AS registrertIForetaksregisteret,
    ''::TEXT AS registrertIStiftelsesregisteret,
    ''::TEXT AS konkurs,
    ''::TEXT AS konkursdato,
    ''::TEXT AS underAvvikling,
    ''::TEXT AS underAvviklingDato,
    ''::TEXT AS underTvangsavviklingEllerTvangsopplosning,
    ''::TEXT AS tvangsopplostPgaManglendeDagligLederDato,
    ''::TEXT AS tvangsopplostPgaManglendeRevisorDato,
    ''::TEXT AS tvangsopplostPgaManglendeRegnskapDato,
    ''::TEXT AS tvangsopplostPgaMangelfulltStyreDato,
    ''::TEXT AS tvangsavvikletPgaManglendeSlettingDato,
    ''::TEXT AS overnetEnhet,
    ''::TEXT AS maalform,
    ''::TEXT AS vedtektsdato,
    ''::TEXT AS vedtektsfestetFormaal,
    ''::TEXT AS aktivitet
FROM prepared_small_history;

CREATE OR REPLACE FUNCTION insert_into_import_small_history()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO prepared_small_history (
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
    ) VALUES (
        NULL,
        NULL,
        NEW.organisasjonsnummer,
        NEW.navn,
        NEW.forretningsadresse_adresse,
        NEW.forretningsadresse_postnummer,
        NEW.forretningsadresse_poststed,
        NEW.forretningsadresse_kommunenummer,
        NEW.forretningsadresse_landkode,
        NEW.postadresse_adresse,
        NEW.postadresse_postnummer,
        NEW.postadresse_poststed,
        NEW.postadresse_kommunenummer,
        NEW.postadresse_landkode,
        NEW.naeringskode1_kode,
        NEW.antallAnsatte
    );
    RETURN NULL; -- As this is an INSTEAD OF trigger
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_insert_import_small_history
INSTEAD OF INSERT ON import_small_history
FOR EACH ROW
EXECUTE FUNCTION insert_into_import_small_history();


\echo "Loading historical units"

-- Function to update valid_from and valid_to
CREATE OR REPLACE FUNCTION update_validity_dates(year INTEGER) RETURNS VOID AS $$
BEGIN
    UPDATE prepared_small_history
    SET
        valid_from = make_date(year, 1, 1),
        valid_to = 'infinity'::DATE
    WHERE valid_from IS NULL AND valid_to IS NULL;
END;
$$ LANGUAGE plpgsql;

-- 2015 data
\copy import_small_history FROM 'samples/norway/small-history/2015-enheter.csv' WITH CSV HEADER;
SELECT update_validity_dates(2015);

-- 2016 data
\copy import_small_history FROM 'samples/norway/small-history/2016-enheter.csv' WITH CSV HEADER;
SELECT update_validity_dates(2016);

-- 2017 data
\copy import_small_history FROM 'samples/norway/small-history/2017-enheter.csv' WITH CSV HEADER;
SELECT update_validity_dates(2017);

-- 2018 data
\copy import_small_history FROM 'samples/norway/small-history/2018-enheter.csv' WITH CSV HEADER;
SELECT update_validity_dates(2018);

-- Speed up changes by validating in the end.
SET CONSTRAINTS ALL DEFERRED;

-- Insert into target table
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
FROM prepared_small_history
ORDER BY valid_from, tax_ident;

-- Validate all inserted rows.
SET CONSTRAINTS ALL IMMEDIATE;

CREATE INDEX IF NOT EXISTS idx_establishment_valid_after_valid_to ON establishment (valid_after, valid_to);
CREATE INDEX IF NOT EXISTS idx_stat_for_unit_establishment_id ON stat_for_unit (establishment_id);
CREATE INDEX IF NOT EXISTS idx_activity_establishment_id ON activity (establishment_id);
CREATE INDEX IF NOT EXISTS idx_legal_unit_valid_after_valid_to ON legal_unit (valid_after, valid_to);
CREATE INDEX IF NOT EXISTS idx_activity_legal_unit_id ON activity (legal_unit_id);
CREATE INDEX IF NOT EXISTS idx_stat_for_unit_legal_unit_id ON stat_for_unit (legal_unit_id);
CREATE INDEX IF NOT EXISTS idx_location_legal_unit_id ON location (legal_unit_id);
CREATE INDEX IF NOT EXISTS idx_activity_est_legal_date ON activity (establishment_id, valid_after, valid_to);
CREATE INDEX IF NOT EXISTS idx_legal_activity_date ON legal_unit (id, valid_after, valid_to);


ANALYZE establishment;
ANALYZE stat_for_unit;
ANALYZE activity;
ANALYZE legal_unit;
ANALYZE location;

-- Check the query efficiency of the views used for building statistical_unit.
\a
\t
SELECT pg_stat_reset();

\o tmp/timepoints.txt
EXPLAIN ANALYZE SELECT * FROM public.timepoints;
SELECT indexrelid::regclass AS index, relid::regclass AS table, idx_scan AS index_scans FROM pg_stat_user_indexes WHERE idx_scan > 0;
SELECT pg_stat_reset();
\o


\o tmp/timesegments.txt
EXPLAIN ANALYZE SELECT * FROM public.timesegments;
SELECT indexrelid::regclass AS index, relid::regclass AS table, idx_scan AS index_scans FROM pg_stat_user_indexes WHERE idx_scan > 0;
SELECT pg_stat_reset();
\o


\o tmp/timeline_establishment.txt
EXPLAIN ANALYZE SELECT * FROM public.timeline_establishment;
SELECT indexrelid::regclass AS index, relid::regclass AS table, idx_scan AS index_scans FROM pg_stat_user_indexes WHERE idx_scan > 0;
SELECT pg_stat_reset();
\o


\o tmp/timeline_legal_unit.txt
EXPLAIN ANALYZE SELECT * FROM public.timeline_legal_unit;
SELECT indexrelid::regclass AS index, relid::regclass AS table, idx_scan AS index_scans FROM pg_stat_user_indexes WHERE idx_scan > 0;
SELECT pg_stat_reset();
\o


\o tmp/timeline_enterprise.txt
EXPLAIN ANALYZE SELECT * FROM public.timeline_enterprise;
SELECT indexrelid::regclass AS index, relid::regclass AS table, idx_scan AS index_scans FROM pg_stat_user_indexes WHERE idx_scan > 0;
SELECT pg_stat_reset();
\o


\o tmp/statistical_unit_def.txt
EXPLAIN ANALYZE SELECT * FROM public.statistical_unit_def;
SELECT indexrelid::regclass AS index, relid::regclass AS table, idx_scan AS index_scans FROM pg_stat_user_indexes WHERE idx_scan > 0;
SELECT pg_stat_reset();
\o

\a
\t

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
