
\copy (SELECT * FROM tmp.enhet WHERE "organisasjonsnummer" IN (SELECT enhet_orgnr FROM tmp.selection ORDER BY periodic_random LIMIT 5000)) TO 'samples/norway/enheter-selection-cli-with-mapping-import.csv' WITH (HEADER true, FORMAT csv, DELIMITER ',', QUOTE '"', FORCE_QUOTE *);
\copy (SELECT * FROM tmp.underenhet WHERE "overordnetEnhet" IN (SELECT enhet_orgnr FROM tmp.selection ORDER BY periodic_random LIMIT 5000)) TO 'samples/norway/underenheter-selection-cli-with-mapping-import.csv' WITH (HEADER true, FORMAT csv, DELIMITER ',', QUOTE '"', FORCE_QUOTE *);

\copy (SELECT * FROM tmp.enhet_for_web_import WHERE tax_reg_ident IN (SELECT enhet_orgnr FROM tmp.selection ORDER BY periodic_random LIMIT 500)) TO 'samples/norway/enheter-selection-web-import.csv' WITH (HEADER true, FORMAT csv, DELIMITER ',', QUOTE '"', FORCE_QUOTE *);
\copy (SELECT * FROM tmp.underenhet_for_web_import WHERE legal_unit_tax_reg_ident IN (SELECT enhet_orgnr FROM tmp.selection ORDER BY periodic_random LIMIT 500)) TO 'samples/norway/underenheter-selection-web-import.csv' WITH (HEADER true, FORMAT csv, DELIMITER ',', QUOTE '"', FORCE_QUOTE *);