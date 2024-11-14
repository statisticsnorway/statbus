
--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------
DROP SCHEMA IF EXISTS samples CASCADE;

--------------------------------------------------------------------------------
-- Load raw data
--------------------------------------------------------------------------------
\i samples/norway/brreg/load-downloads-from-tmp-into-brreg-schema.sql

BEGIN;
CREATE SCHEMA IF NOT EXISTS samples;
--------------------------------------------------------------------------------
-- Schema
--------------------------------------------------------------------------------
CREATE VIEW samples.enhet_for_web_import AS
SELECT "organisasjonsnummer" AS tax_ident
     , "navn" AS name
     , "stiftelsesdato" AS birth_date
     -- There is no death date, the entry simply vanishes!
     --, "nedleggelsesdato" AS death_date
     , "forretningsadresse.adresse" AS physical_address_part1
     , "forretningsadresse.postnummer" AS physical_postcode
     , "forretningsadresse.poststed"   AS physical_postplace
     , "forretningsadresse.kommunenummer" AS physical_region_code
     , "forretningsadresse.landkode" AS physical_country_iso_2
     , "postadresse.adresse" AS postal_address_part1
     , "postadresse.poststed" AS postal_postcode
     , "postadresse.postnummer" AS postal_postplace
     , "postadresse.kommunenummer" AS postal_region_code
     , "postadresse.landkode" AS postal_country_iso_2
     , "naeringskode1.kode" AS primary_activity_category_code
     , "naeringskode2.kode" AS secondary_activity_category_code
     , "institusjonellSektorkode.kode" AS sector_code
     , "organisasjonsform.kode" AS legal_form_code
     , 'brreg' AS data_source_code
FROM brreg.enhet;


CREATE VIEW samples.underenhet_for_web_import AS
SELECT "organisasjonsnummer" AS tax_ident
     , "overordnetEnhet" AS legal_unit_tax_ident
     , "navn" AS name
     , "oppstartsdato" AS birth_date
     , "nedleggelsesdato" AS death_date
     , "beliggenhetsadresse.adresse" AS physical_address_part1
     , "beliggenhetsadresse.postnummer" AS physical_postcode
     , "beliggenhetsadresse.poststed"   AS physical_postplace
     , "beliggenhetsadresse.kommunenummer" AS physical_region_code
     , "beliggenhetsadresse.landkode" AS physical_country_iso_2
     , "postadresse.adresse" AS postal_address_part1
     , "postadresse.poststed" AS postal_postcode
     , "postadresse.postnummer" AS postal_postplace
     , "postadresse.kommunenummer" AS postal_region_code
     , "postadresse.landkode" AS postal_country_iso_2
     , "naeringskode1.kode" AS primary_activity_category_code
     , "naeringskode2.kode" AS secondary_activity_category_code
     , "antallAnsatte" AS employees
FROM brreg.underenhet;

--------------------------------------------------------------------------------
-- Prepare
--------------------------------------------------------------------------------
ALTER TABLE brreg.underenhet ADD periodic_random FLOAT DEFAULT random();
CREATE INDEX underenhet_periodic_random_idx ON brreg.underenhet(periodic_random);

SELECT "organisasjonsnummer" AS underenhet_orgnr
      ,"overordnetEnhet" AS enhet_orgnr
      , periodic_random
INTO TABLE samples.selection
FROM brreg.underenhet
WHERE EXISTS(SELECT * FROM brreg.enhet WHERE enhet."organisasjonsnummer" = underenhet."overordnetEnhet")
ORDER BY periodic_random;

ALTER TABLE brreg.underenhet DROP periodic_random;

--------------------------------------------------------------------------------
-- Extract
--------------------------------------------------------------------------------

\copy (SELECT * FROM brreg.enhet WHERE "organisasjonsnummer" IN (SELECT enhet_orgnr FROM samples.selection ORDER BY periodic_random LIMIT 5000)) TO 'samples/norway/legal_unit/enheter-selection-cli-with-mapping-import.csv' WITH (HEADER true, FORMAT csv, DELIMITER ',', QUOTE '"', FORCE_QUOTE *);
\copy (SELECT * FROM brreg.underenhet WHERE "overordnetEnhet" IN (SELECT enhet_orgnr FROM samples.selection ORDER BY periodic_random LIMIT 5000)) TO 'samples/norway/establishment/underenheter-selection-cli-with-mapping-import.csv' WITH (HEADER true, FORMAT csv, DELIMITER ',', QUOTE '"', FORCE_QUOTE *);

\copy (SELECT * FROM samples.enhet_for_web_import WHERE tax_ident IN (SELECT enhet_orgnr FROM samples.selection ORDER BY periodic_random LIMIT 100)) TO 'samples/norway/legal_unit/enheter-selection-web-import.csv' WITH (HEADER true, FORMAT csv, DELIMITER ',', QUOTE '"', FORCE_QUOTE *);
\copy (SELECT * FROM samples.underenhet_for_web_import WHERE legal_unit_tax_ident IN (SELECT enhet_orgnr FROM samples.selection ORDER BY periodic_random LIMIT 100)) TO 'samples/norway/establishment/underenheter-selection-web-import.csv' WITH (HEADER true, FORMAT csv, DELIMITER ',', QUOTE '"', FORCE_QUOTE *);

--------------------------------------------------------------------------------
END;
