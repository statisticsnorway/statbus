BEGIN;
--SET LOCAL client_min_messages TO DEBUG;
\copy public.legal_unit_region_activity_category_stats_current(tax_reg_ident,name,employees,physical_region_code,primary_activity_category_code) FROM 'samples/100BREGUnits.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
--SET LOCAL client_min_messages TO INFO;
END;