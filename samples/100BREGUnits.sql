
\copy public.legal_unit_region_activity_category_stats_view(tax_reg_ident,name,employees,region_code,activity_category_code) FROM 'samples/100BREGUnits.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
