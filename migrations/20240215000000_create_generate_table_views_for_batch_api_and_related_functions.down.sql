BEGIN;

DROP FUNCTION admin.detect_batch_api_table_properties(regclass);
DROP FUNCTION admin.generate_view(admin.batch_api_table_properties,admin.view_type_enum);
DROP FUNCTION admin.generate_code_upsert_function(admin.batch_api_table_properties,admin.view_type_enum);
DROP FUNCTION admin.generate_path_upsert_function(admin.batch_api_table_properties,admin.view_type_enum);
DROP FUNCTION admin.generate_prepare_function_for_custom(admin.batch_api_table_properties);
DROP FUNCTION admin.generate_view_triggers(regclass,regprocedure,regprocedure);
DROP FUNCTION admin.generate_active_code_custom_unique_constraint(admin.batch_api_table_properties);
DROP FUNCTION admin.get_unique_columns(admin.batch_api_table_properties);
DROP FUNCTION admin.generate_table_views_for_batch_api(regclass);
DROP FUNCTION admin.drop_table_views_for_batch_api(regclass);
DROP TYPE admin.view_type_enum;
DROP TYPE admin.batch_api_table_properties;

END;
