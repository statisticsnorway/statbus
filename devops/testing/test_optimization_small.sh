#!/bin/bash
# Test script for the optimization with a small dataset

cd samples/norway/brreg

echo "Setting up small test with only hovedenhet (less data to debug faster)..."

# Use USER_EMAIL to set up the environment  
USER_EMAIL=jorgen@veridit.no ./set-up-statbus-for-norway.sh

# Create a job for just the hovedenhet data (smaller dataset)
cd ../../..

echo "Creating import job for hovedenhet only..."

echo "
INSERT INTO public.import_job (
    slug, name, data_source_id, import_definition_id, 
    valid_from, valid_until, state
) 
SELECT 
    'test_hovedenhet_optimization',
    'Test hovedenhet optimization', 
    ds.id,
    def.id,
    CURRENT_DATE, 
    CURRENT_DATE + INTERVAL '1 year',
    'upload_completed'
FROM public.data_source ds, public.import_definition def
WHERE ds.code = 'brreg' 
  AND def.slug = 'brreg_hovedenhet_2024'
LIMIT 1;
" | ./devops/manage-statbus.sh psql

# Load a small sample of data
echo "Loading small sample data..."
head -n 100 samples/norway/brreg/selection/hovedenhet_selection.csv | echo "
CREATE TEMP TABLE temp_load_data (data TEXT);
COPY temp_load_data FROM STDIN CSV;
$(cat -)

-- Get the job ID and table name
WITH job_info AS (
    SELECT ij.id as job_id, ij.data_table_name
    FROM public.import_job ij
    WHERE ij.slug = 'test_hovedenhet_optimization'
)
-- Copy the data to the actual import table
INSERT INTO public.import_data_brreg_hovedenhet_2024_20261024_072629_b2a60e86 (row_id, brreg_orgnr_raw, navn_raw, forretningsadresse_postboks_raw, forretningsadresse_postnummer_raw, forretningsadresse_poststed_raw, naeringskode1_raw, stiftelsesdato_raw, maalform_raw, ansatte_raw, valid_from, valid_until, data_source_id, edit_by_user_id, edit_at, action)
SELECT 
    row_number() OVER () as row_id,
    split_part(data, ',', 1) as brreg_orgnr_raw,
    split_part(data, ',', 2) as navn_raw,
    split_part(data, ',', 3) as forretningsadresse_postboks_raw,
    split_part(data, ',', 4) as forretningsadresse_postnummer_raw, 
    split_part(data, ',', 5) as forretningsadresse_poststed_raw,
    split_part(data, ',', 6) as naeringskode1_raw,
    split_part(data, ',', 7) as stiftelsesdato_raw,
    split_part(data, ',', 8) as maalform_raw,
    split_part(data, ',', 9) as ansatte_raw,
    CURRENT_DATE as valid_from,
    CURRENT_DATE + INTERVAL '1 year' as valid_until,
    (SELECT ds.id FROM public.data_source ds WHERE ds.code = 'brreg'),
    (SELECT au.id FROM public.auth_user au WHERE au.email = 'jorgen@veridit.no'),
    CURRENT_TIMESTAMP as edit_at,
    'use' as action
FROM temp_load_data
WHERE data != 'brreg_orgnr,navn,forretningsadresse_postboks,forretningsadresse_postnummer,forretningsadresse_poststed,naeringskode1,stiftelsesdato,maalform,ansatte'
LIMIT 50;  -- Even smaller test set
" | ./devops/manage-statbus.sh psql

echo "Checking initial state..."
echo "SELECT id, state, slug FROM public.import_job WHERE slug = 'test_hovedenhet_optimization';" | ./devops/manage-statbus.sh psql

echo "Waiting for job to process..."
sleep 60

echo "Checking final state..."
echo "SELECT id, state, slug, CASE WHEN error IS NOT NULL THEN 'ERROR' ELSE 'OK' END FROM public.import_job WHERE slug = 'test_hovedenhet_optimization';" | ./devops/manage-statbus.sh psql

echo "Checking results..."
echo "SELECT count(*) as stat_rows FROM public.stat_for_unit;" | ./devops/manage-statbus.sh psql
echo "SELECT count(*) as legal_units FROM public.legal_unit;" | ./devops/manage-statbus.sh psql