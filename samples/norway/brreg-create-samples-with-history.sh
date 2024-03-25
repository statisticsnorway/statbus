#!/bin/bash
#
#!/bin/bash
#
set -e # Exit on any failure for any command

if test -n "$DEBUG"; then
  set -x # Print all commands before running them - for easy debugging.
fi

WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd ../.. && pwd )"

pushd $WORKSPACE/tmp
if test \! -f "enheter.csv"; then
  echo "Download brreg enheter"
  cd tmp
  curl --output enheter.csv.gz 'https://data.brreg.no/enhetsregisteret/oppslag/enheter/lastned/csv/v2'
  gunzip enheter.csv.gz
fi

if test \! -f "underenheter.csv"; then
  echo "Download brreg underenheter"
  cd tmp
  curl --output underenheter.csv.gz 'https://data.brreg.no/enhetsregisteret/oppslag/underenheter/lastned/csv/v2'
  gunzip underenheter.csv.gz
fi
popd

CHECK_TABLE_EXISTENCE_AND_COUNT=$(cat <<EOF
SELECT EXISTS (
    SELECT FROM
        pg_catalog.pg_tables
    WHERE
        schemaname = 'brreg' AND tablename = 'enhet'
) AND (
    SELECT COUNT(*) = 0 FROM brreg.enhet
) AS should_load;
EOF
)

# Execute the SQL command and store the result.
SHOULD_LOAD=$(psql -tA -c "$CHECK_TABLE_EXISTENCE_AND_COUNT")

if [ "$SHOULD_LOAD" = "t" ]; then
    echo "Loading data into brreg"
    psql < samples/norway/load-brreg.sql
else
    echo "Table brreg.enhet exists and is not empty. No action taken."
fi

psql < samples/norway/brreg-create-samples-with-history.sql

OUTPUT_DIR="samples/norway"

# Make sure the output directory exists
mkdir -p "$OUTPUT_DIR"

# Get distinct years from gh.sample
YEARS=$(psql -t -c "SELECT DISTINCT year FROM gh.sample ORDER BY year;")

for YEAR in $YEARS; do
    echo "Exporting data for year: $YEAR"
    psql <<EOS
\echo Writing legal_units from $YEAR
\copy (SELECT legal_unit.* FROM gh.sample AS sample JOIN LATERAL jsonb_populate_recordset(NULL::brreg.enhet, sample.legal_unit) AS legal_unit ON true WHERE sample.year = $YEAR) TO '$OUTPUT_DIR/${YEAR}-enheter.csv' WITH (HEADER true, FORMAT csv, DELIMITER ',', QUOTE '\"', FORCE_QUOTE *);

\echo Writing establishments from $YEAR
\copy (SELECT establishment.* FROM gh.sample AS sample, jsonb_array_elements(sample.establishments) AS establishment_element JOIN LATERAL jsonb_populate_recordset(NULL::brreg.underenhet, establishment_element) AS establishment ON true WHERE sample.year = $YEAR) TO '$OUTPUT_DIR/${YEAR}-underenheter.csv' WITH (HEADER true, FORMAT csv, DELIMITER ',', QUOTE '\"', FORCE_QUOTE *);
EOS
done
