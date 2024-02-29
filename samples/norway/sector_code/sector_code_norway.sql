BEGIN;

\copy public.sector_code_custom_only FROM 'samples/norway/sector_code/sector_code_norway.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

END;