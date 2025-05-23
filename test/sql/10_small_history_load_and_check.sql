BEGIN;

\i test/setup.sql

CREATE TEMP TABLE prepared_small_history (
    valid_from DATE,
    valid_to DATE,
    tax_ident TEXT,
    name TEXT,
    physical_address_part1 TEXT,
    physical_postcode TEXT,
    physical_postplace TEXT,
    physical_region_code TEXT,
    physical_country_iso_2 TEXT,
    postal_address_part1 TEXT,
    postal_postcode TEXT,
    postal_postplace TEXT,
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
    postal_postplace AS postadresse_poststed,
    postal_postcode AS postadresse_postnummer,
    ''::TEXT AS postadresse_kommune,
    postal_region_code AS postadresse_kommunenummer,
    ''::TEXT AS postadresse_land,
    postal_country_iso_2 AS postadresse_landkode,
    physical_address_part1 AS forretningsadresse_adresse,
    physical_postplace AS forretningsadresse_poststed,
    physical_postcode AS forretningsadresse_postnummer,
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
        physical_postcode,
        physical_postplace,
        physical_region_code,
        physical_country_iso_2,
        postal_address_part1,
        postal_postcode,
        postal_postplace,
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

-- Grant access to temporary tables and functions
GRANT SELECT, INSERT, UPDATE ON prepared_small_history TO PUBLIC;
GRANT SELECT, INSERT, UPDATE ON import_small_history TO PUBLIC;
GRANT EXECUTE ON FUNCTION insert_into_import_small_history() TO PUBLIC;
GRANT EXECUTE ON FUNCTION update_validity_dates(INTEGER) TO PUBLIC;

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

\echo "Setting up Statbus for Norway"
\i samples/norway/getting-started.sql


\echo "Loading historical units"

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

-- Create Import Job for Legal Units (Small History)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_explicit_dates'), -- Corrected slug
    'import_10_lu_era_smallhist',
    'Import LU Small History (10_small_history_load_and_check.sql)',
    'Import job for prepared_small_history data using legal_unit_explicit_dates definition.', -- Corrected description
    'Test data load (10_small_history_load_and_check.sql)';

-- Insert into target job upload table
INSERT INTO public.import_10_lu_era_smallhist_upload (
    valid_from,
    valid_to,
    tax_ident,
    name,
    physical_address_part1,
    physical_postcode,
    physical_postplace,
    physical_region_code,
    physical_country_iso_2,
    postal_address_part1,
    postal_postcode,
    postal_postplace,
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
    physical_postcode,
    physical_postplace,
    physical_region_code,
    physical_country_iso_2,
    postal_address_part1,
    postal_postcode,
    postal_postplace,
    postal_region_code,
    postal_country_iso_2,
    primary_activity_category_code,
    employees
FROM prepared_small_history
ORDER BY valid_from, tax_ident;

\echo Run worker processing for import jobs
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

-- Validate all inserted rows.
SET CONSTRAINTS ALL IMMEDIATE;

\echo Run worker processing for analytics tasks before EXPLAIN ANALYZE
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

SELECT test.sudo_exec($sql$
  CREATE INDEX IF NOT EXISTS tidx_establishment_valid_after_valid_to ON establishment (valid_after, valid_to);
  CREATE INDEX IF NOT EXISTS tidx_stat_for_unit_establishment_id ON stat_for_unit (establishment_id);
  CREATE INDEX IF NOT EXISTS tidx_activity_establishment_id ON activity (establishment_id);
  CREATE INDEX IF NOT EXISTS tidx_legal_unit_valid_after_valid_to ON legal_unit (valid_after, valid_to);
  CREATE INDEX IF NOT EXISTS tidx_stat_for_unit_legal_unit_id ON stat_for_unit (legal_unit_id);
  CREATE INDEX IF NOT EXISTS tidx_location_legal_unit_id ON location (legal_unit_id);
  CREATE INDEX IF NOT EXISTS tidx_legal_activity_date ON legal_unit (id, valid_after, valid_to);
$sql$);

SELECT test.sudo_exec($sql$
  ANALYZE establishment;
  ANALYZE stat_for_unit;
  ANALYZE activity;
  ANALYZE legal_unit;
  ANALYZE location;
$sql$);

-- Check the query efficiency of the views used for building statistical_unit.
\a
\t
SELECT test.sudo_exec('SELECT pg_stat_monitor_reset()');

\o tmp/timepoints.log
EXPLAIN ANALYZE SELECT * FROM public.timepoints;
SELECT queryid, calls, total_exec_time, rows
FROM pg_stat_monitor
WHERE query LIKE '%SELECT * FROM public.timepoints%';
\o

SELECT test.sudo_exec('SELECT pg_stat_monitor_reset()');

\o tmp/timesegments.log
EXPLAIN ANALYZE SELECT * FROM public.timesegments;
SELECT queryid, calls, total_exec_time, rows
FROM pg_stat_monitor
WHERE query LIKE '%SELECT * FROM public.timesegments%';
\o

SELECT test.sudo_exec('SELECT pg_stat_monitor_reset()');

\o tmp/timeline_establishment.log
EXPLAIN ANALYZE SELECT * FROM public.timeline_establishment;
SELECT queryid, calls, total_exec_time, rows
FROM pg_stat_monitor
WHERE query LIKE '%SELECT * FROM public.timeline_establishment%';
\o

SELECT test.sudo_exec('SELECT pg_stat_monitor_reset()');

\o tmp/timeline_legal_unit.log
EXPLAIN ANALYZE SELECT * FROM public.timeline_legal_unit;
SELECT queryid, calls, total_exec_time, rows
FROM pg_stat_monitor
WHERE query LIKE '%SELECT * FROM public.timeline_legal_unit%';
\o

SELECT test.sudo_exec('SELECT pg_stat_monitor_reset()');

\o tmp/timeline_enterprise.log
EXPLAIN ANALYZE SELECT * FROM public.timeline_enterprise;
SELECT queryid, calls, total_exec_time, rows
FROM pg_stat_monitor
WHERE query LIKE '%SELECT * FROM public.timeline_enterprise%';
\o

SELECT test.sudo_exec('SELECT pg_stat_monitor_reset()');

\o tmp/statistical_unit_def.log
EXPLAIN ANALYZE SELECT * FROM public.statistical_unit_def;
SELECT queryid, calls, total_exec_time, rows
FROM pg_stat_monitor
WHERE query LIKE '%SELECT * FROM public.statistical_unit_def%';
\o

SELECT test.sudo_exec('SELECT pg_stat_monitor_reset()');

\a
\t

\o tmp/top_used_indices.log
-- Get top used indices with additional information from pg_stat_monitor
SELECT
    indexrelid::regclass AS index_name,
    relid::regclass AS table_name,
    idx_scan,
    idx_tup_fetch AS tuples_fetched,
    (SELECT substr(query, 0, 100) FROM pg_stat_monitor 
     WHERE relations::text LIKE '%' || relid::regclass::text || '%' 
     ORDER BY total_exec_time DESC LIMIT 1) AS sample_query
FROM
    pg_stat_user_indexes
WHERE
    idx_scan > 0  -- Focus on indexes that have been used
ORDER BY
    idx_scan DESC
LIMIT 20;  -- Display top used indexes, adjust if necessary
\o

-- The main analytics processing was done before EXPLAIN ANALYZE.
-- This call might process any remaining or newly queued tasks if necessary,
-- or could be removed if the earlier analytics call is comprehensive.
-- For safety and to catch any deferred analytics, we can run it again.
\echo Run worker processing for any remaining analytics tasks
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo "Inspecting import job data for import_10_lu_era_smallhist"
SELECT row_id, state, error, tax_ident, name, valid_from, valid_to
FROM public.import_10_lu_era_smallhist_data
ORDER BY row_id
LIMIT 5;

\echo "Checking import job status for import_10_lu_era_smallhist"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       (SELECT COUNT(*) FROM public.import_10_lu_era_smallhist_data dr WHERE dr.state = 'error') AS error_rows
FROM public.import_job
WHERE slug = 'import_10_lu_era_smallhist';

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
