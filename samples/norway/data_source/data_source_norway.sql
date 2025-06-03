\copy public.data_source_custom (code, name) FROM 'samples/norway/data_source/data_source_norway.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
