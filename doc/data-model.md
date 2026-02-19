# StatBus Data Model Summary

This document is automatically generated from the database schema by `test/sql/015_generate_data_model_doc.sql`. Do not edit it manually.

This document provides a compact overview of the StatBus database schema, focusing on entities, relationships, and key patterns.


## Core Statistical Units (Hierarchy)
The system revolves around four main statistical units, often with temporal validity (`valid_from`, `valid_after`, `valid_to`):

- `enterprise_group(id, short_name, name, enterprise_group_type_id, reorg_type_id, edit_by_user_id, unit_size_id, data_source_id, foreign_participation_id, valid_range, valid_from, valid_to, valid_until, edit_at, contact_person, edit_comment, reorg_references, reorg_date)` (EG) (temporal)
  - Key FKs: data_source_id, edit_by_user_id, enterprise_group_type_id, foreign_participation_id, reorg_type_id, unit_size_id.
- `enterprise(id, short_name, edit_by_user_id, edit_at, enabled, edit_comment)` (EN)
  - Key FKs: edit_by_user_id.
- `legal_unit(id, short_name, name, invalid_codes, sector_id, status_id, legal_form_id, edit_by_user_id, unit_size_id, foreign_participation_id, data_source_id, enterprise_id, image_id, valid_range, valid_from, valid_to, valid_until, edit_at, birth_date, death_date, free_econ_zone, edit_comment, primary_for_enterprise)` (LU) (temporal)
  - Key FKs: data_source_id, edit_by_user_id, enterprise_id, foreign_participation_id, image_id, legal_form_id, sector_id, status_id, unit_size_id.
- `establishment(id, short_name, name, invalid_codes, sector_id, status_id, edit_by_user_id, unit_size_id, data_source_id, enterprise_id, legal_unit_id, image_id, valid_range, valid_from, valid_to, valid_until, edit_at, birth_date, death_date, free_econ_zone, edit_comment, primary_for_legal_unit, primary_for_enterprise)` (EST) (temporal)
  - Key FKs: data_source_id, edit_by_user_id, enterprise_id, image_id, legal_unit_id, sector_id, status_id, unit_size_id, valid_range.

## Common Links for Core Units (EG, EN, LU, EST)
These tables link to any of the four core statistical units:

- `external_ident(id, type_id, ident, idents, labels, establishment_id, legal_unit_id, enterprise_id, enterprise_group_id, edit_by_user_id, edit_at, shape, edit_comment)`
  - Key FKs: edit_by_user_id, enterprise_id, type_id.
  - Enums: `shape` (`public.external_ident_shape`).
- `image(id, type, uploaded_by_user_id, uploaded_at, data)`
  - Key FKs: uploaded_by_user_id.
- `tag_for_unit(id, tag_id, establishment_id, legal_unit_id, enterprise_id, enterprise_group_id, edit_by_user_id, created_at, edit_at, edit_comment)`
  - Key FKs: edit_by_user_id, enterprise_id, tag_id.
- `unit_notes(id, notes, establishment_id, legal_unit_id, enterprise_id, enterprise_group_id, edit_by_user_id, created_at, edit_at, edit_comment)`
  - Key FKs: edit_by_user_id, enterprise_id.
- `enterprise_external_idents(unit_type, external_idents, unit_id, valid_from, valid_to, valid_until)` (temporal)
  - Enums: `unit_type` (`public.statistical_unit_type`).

## Key Supporting Entities & Classifications


### Activity

- `activity(id, type, category_id, data_source_id, edit_by_user_id, establishment_id, legal_unit_id, valid_range, valid_from, valid_to, valid_until, edit_at, edit_comment)` (temporal)
  - Key FKs: category_id, data_source_id, edit_by_user_id, establishment_id, legal_unit_id, valid_range, valid_range.
  - Enums: `type` (`public.activity_type`).
- `activity_category(id, path, label, code, name, standard_id, parent_id, created_at, updated_at, enabled, level, description, custom)`
  - Key FKs: parent_id, standard_id.
- `activity_category_standard(id, code, name, code_pattern, enabled, description)`
  - Enums: `code_pattern` (`public.activity_category_code_behaviour`).
- `activity_category_isic_v4(path, label, code, name, standard, description)`
- `activity_category_nace_v2_1(path, label, code, name, standard, description)`

### Location & Contact

- `location(id, type, postcode, region_id, country_id, establishment_id, legal_unit_id, data_source_id, edit_by_user_id, valid_range, valid_from, valid_to, valid_until, edit_at, address_part1, address_part2, address_part3, postplace, latitude, longitude, altitude, edit_comment)` (temporal)
  - Key FKs: country_id, data_source_id, edit_by_user_id, establishment_id, legal_unit_id, region_id, valid_range, valid_range.
  - Enums: `type` (`public.location_type`).
- `contact(id, email_address, establishment_id, legal_unit_id, data_source_id, edit_by_user_id, valid_range, valid_from, valid_to, valid_until, edit_at, web_address, phone_number, landline, mobile_number, fax_number, edit_comment)` (temporal)
  - Key FKs: data_source_id, edit_by_user_id, establishment_id, legal_unit_id, valid_range, valid_range.
- `region(id, path, label, code, name, parent_id, level, center_latitude, center_longitude, center_altitude)`
  - Key FKs: parent_id.
- `country(id, name, created_at, updated_at, enabled, iso_2, iso_3, iso_num, custom)`
- `country_view(id, name, enabled, iso_2, iso_3, iso_num, custom)`

### Persons

- `person(id, personal_ident, given_name, middle_name, family_name, country_id, created_at, birth_date, sex, phone_number, mobile_number, address_part1, address_part2, address_part3)`
  - Key FKs: country_id.
  - Enums: `sex` (`public.person_sex`).
- `person_for_unit(id, person_id, person_role_id, data_source_id, establishment_id, legal_unit_id, edit_by_user_id, valid_range, valid_from, valid_to, valid_until, edit_at, edit_comment)` (temporal)
  - Key FKs: data_source_id, edit_by_user_id, establishment_id, legal_unit_id, person_id, person_role_id, valid_range, valid_range.
- `person_role(id, code, name, created_at, updated_at, enabled, custom)`

### Statistics

- `stat_for_unit(id, value_int, value_float, value_string, value_bool, stat_definition_id, data_source_id, establishment_id, legal_unit_id, edit_by_user_id, valid_range, valid_from, valid_to, valid_until, edit_at, edit_comment, stat)` (temporal)
  - Key FKs: data_source_id, edit_by_user_id, establishment_id, legal_unit_id, stat_definition_id, valid_range, valid_range.
- `stat_definition(id, code, type, name, enabled, frequency, description, priority)`
  - Enums: `frequency` (`public.stat_frequency`), `type` (`public.stat_type`).

### General Code/Classification Tables
These tables typically store codes, names, and flags for `custom` and `enabled` status.

- `data_source(id, code, name, created_at, updated_at, enabled, custom)`
- `enterprise_group_type(id, code, name, created_at, updated_at, enabled, custom)`
- `enterprise_group_role(id, code, name, created_at, updated_at, enabled, custom)`
- `external_ident_type(id, code, name, labels, enabled, shape, description, priority)`
  - Enums: `shape` (`public.external_ident_shape`).
- `foreign_participation(id, code, name, created_at, updated_at, enabled, custom)`
- `legal_form(id, code, name, created_at, updated_at, enabled, custom)`
- `reorg_type(id, code, name, created_at, updated_at, enabled, description, custom)`
- `sector(id, path, label, code, name, parent_id, created_at, updated_at, enabled, description, custom)`
- `status(id, code, name, created_at, updated_at, enabled, assigned_by_default, used_for_counting, priority, custom)`
- `tag(id, path, label, code, name, type, parent_id, context_valid_on, created_at, updated_at, enabled, level, description, context_valid_from, context_valid_to, context_valid_until)`
  - Key FKs: parent_id.
  - Enums: `type` (`public.tag_type`).
- `unit_size(id, code, name, created_at, updated_at, enabled, custom)`

### Enum Definitions
Enumerated types used across the schema, with their possible values.

- **`auth.login_error_code`**: `USER_NOT_FOUND`, `USER_NOT_CONFIRMED_EMAIL`, `USER_DELETED`, `USER_MISSING_PASSWORD`, `WRONG_PASSWORD`, `REFRESH_NO_TOKEN_COOKIE`, `REFRESH_INVALID_TOKEN_TYPE`, `REFRESH_USER_NOT_FOUND_OR_DELETED`, `REFRESH_SESSION_INVALID_OR_SUPERSEDED`
- **`public.activity_category_code_behaviour`**: `digits`, `dot_after_two_digits`
- **`public.activity_type`**: `primary`, `secondary`, `ancilliary`
- **`public.allen_interval_relation`**: `precedes`, `meets`, `overlaps`, `starts`, `during`, `finishes`, `equals`, `overlapped_by`, `started_by`, `contains`, `finished_by`, `met_by`, `preceded_by`
- **`public.external_ident_shape`**: `regular`, `hierarchical`
- **`public.hierarchy_scope`**: `all`, `tree`, `details`
- **`public.history_resolution`**: `year`, `year-month`
- **`public.import_data_column_purpose`**: `source_input`, `internal`, `pk_id`, `metadata`
- **`public.import_data_state`**: `pending`, `analysing`, `analysed`, `processing`, `processed`, `error`
- **`public.import_job_state`**: `waiting_for_upload`, `upload_completed`, `preparing_data`, `analysing_data`, `waiting_for_review`, `approved`, `rejected`, `processing_data`, `failed`, `finished`
- **`public.import_mode`**: `legal_unit`, `establishment_formal`, `establishment_informal`, `generic_unit`
- **`public.import_row_action_type`**: `use`, `skip`
- **`public.import_row_operation_type`**: `insert`, `replace`, `update`
- **`public.import_source_expression`**: `now`, `default`
- **`public.import_step_phase`**: `analyse`, `process`
- **`public.import_strategy`**: `insert_or_replace`, `insert_only`, `replace_only`, `insert_or_update`, `update_only`
- **`public.import_valid_time_from`**: `job_provided`, `source_columns`
- **`public.location_type`**: `physical`, `postal`
- **`public.person_sex`**: `Male`, `Female`
- **`public.relative_period_code`**: `today`, `year_curr`, `year_prev`, `year_curr_only`, `year_prev_only`, `start_of_week_curr`, `stop_of_week_prev`, `start_of_week_prev`, `start_of_month_curr`, `stop_of_month_prev`, `start_of_month_prev`, `start_of_quarter_curr`, `stop_of_quarter_prev`, `start_of_quarter_prev`, `start_of_semester_curr`, `stop_of_semester_prev`, `start_of_semester_prev`, `start_of_year_curr`, `stop_of_year_prev`, `start_of_year_prev`, `start_of_quinquennial_curr`, `stop_of_quinquennial_prev`, `start_of_quinquennial_prev`, `start_of_decade_curr`, `stop_of_decade_prev`, `start_of_decade_prev`
- **`public.relative_period_scope`**: `input_and_query`, `query`, `input`
- **`public.reset_scope`**: `units`, `data`, `getting-started`, `all`
- **`public.stat_frequency`**: `daily`, `weekly`, `biweekly`, `monthly`, `bimonthly`, `quarterly`, `semesterly`, `yearly`
- **`public.stat_type`**: `int`, `float`, `string`, `bool`
- **`public.statbus_role`**: `admin_user`, `regular_user`, `restricted_user`, `external_user`
- **`public.statistical_unit_type`**: `establishment`, `legal_unit`, `enterprise`, `enterprise_group`
- **`public.tag_type`**: `custom`, `system`
- **`public.time_context_type`**: `relative_period`, `tag`, `year`
- **`worker.process_mode`**: `top`, `child`
- **`worker.task_state`**: `pending`, `processing`, `waiting`, `completed`, `failed`


## Temporal Data & History


### Derivations to create statistical_unit for a complete picture of every EN,LU,ES for every atomic segment. (/search)

- `timepoints(unit_type, unit_id, timepoint)`
  - Enums: `unit_type` (`public.statistical_unit_type`).
- `timesegments(unit_type, unit_id, valid_from, valid_until)` (temporal)
  - Enums: `unit_type` (`public.statistical_unit_type`).
- `timeline_establishment, `timeline_legal_unit`, `timeline_enterprise`(unit_type, name, primary_activity_category_path, primary_activity_category_code, secondary_activity_category_path, secondary_activity_category_code, activity_category_paths, sector_path, sector_code, sector_name, data_source_codes, legal_form_code, legal_form_name, physical_postcode, physical_region_path, physical_region_code, postal_postcode, postal_region_path, postal_region_code, email_address, unit_size_code, status_code, invalid_codes, unit_id, primary_activity_category_id, secondary_activity_category_id, sector_id, legal_form_id, physical_region_id, physical_country_id, postal_region_id, postal_country_id, unit_size_id, status_id, last_edit_by_user_id, establishment_id, legal_unit_id, enterprise_id, valid_from, valid_to, valid_until, last_edit_at, birth_date, death_date, search, data_source_ids, physical_address_part1, physical_address_part2, physical_address_part3, physical_postplace, physical_country_iso_2, physical_latitude, physical_longitude, physical_altitude, domestic, postal_address_part1, postal_address_part2, postal_address_part3, postal_postplace, postal_country_iso_2, postal_latitude, postal_longitude, postal_altitude, web_address, phone_number, landline, mobile_number, fax_number, used_for_counting, last_edit_comment, has_legal_unit, primary_for_enterprise, primary_for_legal_unit, stats, stats_summary, related_establishment_ids, excluded_establishment_ids, included_establishment_ids, related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids, related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids)` (temporal)
  - Enums: `unit_type` (`public.statistical_unit_type`).
- `statistical_unit(unit_type, external_idents, name, primary_activity_category_path, primary_activity_category_code, secondary_activity_category_path, secondary_activity_category_code, activity_category_paths, sector_path, sector_code, sector_name, data_source_codes, legal_form_code, legal_form_name, physical_postcode, physical_region_path, physical_region_code, postal_postcode, postal_region_path, postal_region_code, email_address, unit_size_code, status_code, invalid_codes, tag_paths, unit_id, primary_activity_category_id, secondary_activity_category_id, sector_id, legal_form_id, physical_region_id, physical_country_id, postal_region_id, postal_country_id, unit_size_id, status_id, last_edit_by_user_id, valid_from, valid_to, valid_until, last_edit_at, valid_range, birth_date, death_date, search, data_source_ids, physical_address_part1, physical_address_part2, physical_address_part3, physical_postplace, physical_country_iso_2, physical_latitude, physical_longitude, physical_altitude, domestic, postal_address_part1, postal_address_part2, postal_address_part3, postal_postplace, postal_country_iso_2, postal_latitude, postal_longitude, postal_altitude, web_address, phone_number, landline, mobile_number, fax_number, used_for_counting, last_edit_comment, has_legal_unit, related_establishment_ids, excluded_establishment_ids, included_establishment_ids, related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids, related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids, stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, report_partition_seq)` (temporal)
  - Enums: `unit_type` (`public.statistical_unit_type`).

### Derivations for UI listing of relevant time periods

- `timesegments_years(year)`
- `relative_period(id, code, name_when_query, name_when_input, enabled, scope)`
  - Enums: `code` (`public.relative_period_code`), `scope` (`public.relative_period_scope`).
- `relative_period_with_time(id, code, name_when_query, name_when_input, valid_on, valid_from, valid_to, enabled, scope)`
  - Enums: `code` (`public.relative_period_code`), `scope` (`public.relative_period_scope`).
- `time_context(type, ident, name_when_query, name_when_input, code, path, valid_from, valid_to, valid_on, scope)`
  - Enums: `code` (`public.relative_period_code`), `scope` (`public.relative_period_scope`), `type` (`public.time_context_type`).

### Derivations for drilling on facets of statistical_unit (/reports)

- `statistical_unit_facet(unit_type, physical_region_path, primary_activity_category_path, sector_path, legal_form_id, physical_country_id, status_id, valid_from, valid_to, valid_until, count, stats_summary)` (temporal)
  - Enums: `unit_type` (`public.statistical_unit_type`).
- `statistical_unit_facet_dirty_partitions(partition_seq)`

### Derivations to create statistical_history for reporting and statistical_history_facet for drilldown.

- `statistical_history(unit_type, name_change_count, resolution, year, month, exists_count, exists_change, exists_added_count, exists_removed_count, countable_count, countable_change, countable_added_count, countable_removed_count, births, deaths, primary_activity_category_change_count, secondary_activity_category_change_count, sector_change_count, legal_form_change_count, physical_region_change_count, physical_country_change_count, physical_address_change_count, stats_summary, partition_seq)`
  - Enums: `resolution` (`public.history_resolution`), `unit_type` (`public.statistical_unit_type`).
- `statistical_history_facet(unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path, physical_region_path, name_change_count, legal_form_id, physical_country_id, unit_size_id, status_id, resolution, year, month, exists_count, exists_change, exists_added_count, exists_removed_count, countable_count, countable_change, countable_added_count, countable_removed_count, births, deaths, primary_activity_category_change_count, secondary_activity_category_change_count, sector_change_count, legal_form_change_count, physical_region_change_count, physical_country_change_count, physical_address_change_count, unit_size_change_count, status_change_count, stats_summary)`
  - Enums: `resolution` (`public.history_resolution`), `unit_type` (`public.statistical_unit_type`).
- `statistical_history_facet_partitions(unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path, physical_region_path, name_change_count, legal_form_id, physical_country_id, unit_size_id, status_id, partition_seq, resolution, year, month, exists_count, exists_change, exists_added_count, exists_removed_count, countable_count, countable_change, countable_added_count, countable_removed_count, births, deaths, primary_activity_category_change_count, secondary_activity_category_change_count, sector_change_count, legal_form_change_count, physical_region_change_count, physical_country_change_count, physical_address_change_count, unit_size_change_count, status_change_count, stats_summary)`
  - Enums: `resolution` (`public.history_resolution`), `unit_type` (`public.statistical_unit_type`).

## Import System
Handles the ingestion of data from external files.

- `import_definition(id, slug, name, data_source_id, user_id, valid_time_from, created_at, updated_at, enabled, note, strategy, mode, custom, valid, validation_error, default_retention_period, import_as_null)`
  - Key FKs: data_source_id, user_id.
  - Enums: `mode` (`public.import_mode`), `strategy` (`public.import_strategy`), `valid_time_from` (`public.import_valid_time_from`).
- `import_step(id, code, name, created_at, updated_at, priority, analyse_procedure, process_procedure, is_holistic)`
- `import_definition_step(definition_id, step_id)`
  - Key FKs: definition_id, step_id.
- `import_source_column(id, column_name, definition_id, created_at, updated_at, priority)`
  - Key FKs: definition_id.
- `import_data_column(id, column_name, column_type, default_value, is_uniquely_identifying, step_id, created_at, updated_at, priority, purpose, is_nullable)`
  - Key FKs: step_id.
  - Enums: `purpose` (`public.import_data_column_purpose`).
- `import_mapping(id, source_value, definition_id, source_column_id, target_data_column_id, created_at, updated_at, source_expression, is_ignored, target_data_column_purpose)`
  - Key FKs: definition_id, source_column_id, target_data_column_id, target_data_column_id, target_data_column_purpose.
  - Enums: `source_expression` (`public.import_source_expression`), `target_data_column_purpose` (`public.import_data_column_purpose`).
- `import_job(id, slug, time_context_ident, default_data_source_code, upload_table_name, data_table_name, current_step_code, definition_id, user_id, created_at, updated_at, preparing_data_at, analysis_start_at, analysis_stop_at, changes_approved_at, changes_rejected_at, processing_start_at, processing_stop_at, expires_at, description, note, default_valid_from, default_valid_to, priority, analysis_batch_size, processing_batch_size, definition_snapshot, analysis_completed_pct, analysis_rows_per_sec, current_step_priority, max_analysis_priority, total_analysis_steps_weighted, completed_analysis_steps_weighted, total_rows, imported_rows, import_completed_pct, import_rows_per_sec, last_progress_update, state, error, review, edit_comment)`
  - Key FKs: definition_id, user_id.
  - Enums: `state` (`public.import_job_state`).

## Worker System
Handles background processing. A long-running worker process calls `worker.process_tasks()` to process tasks synchronously.

- `tasks(id, command, parent_id, created_at, processed_at, completed_at, scheduled_at, priority, state, duration_ms, error, worker_pid, payload)`
  - Key FKs: command, command, parent_id.
  - Enums: `state` (`worker.task_state`).
- `command_registry(command, created_at, handler_procedure, before_procedure, after_procedure, description, queue, batches_per_wave)`
  - Key FKs: queue.
- `queue_registry(queue, description, default_concurrency)`
- `pipeline_progress(updated_at, step, total, completed)`
- `base_change_log(establishment_ids, legal_unit_ids, enterprise_ids, edited_by_valid_range)`
- `base_change_log_has_pending(has_pending)`

## Auth & System Tables/Views

- `user(id, sub, display_name, email, email_confirmed_at, created_at, updated_at, last_sign_in_at, deleted_at, password, encrypted_password, statbus_role)`
  - Enums: `statbus_role` (`public.statbus_role`).
- `user(id, sub, display_name, email, email_confirmed_at, created_at, updated_at, last_sign_in_at, deleted_at, password, statbus_role)`
  - Enums: `statbus_role` (`public.statbus_role`).
- `api_key(id, user_id, created_at, expires_at, revoked_at, jti, description, token)`
  - Key FKs: user_id.
- `api_key(id, user_id, created_at, expires_at, revoked_at, jti, description, token)`
- `refresh_session(id, user_id, created_at, last_used_at, expires_at, jti, refresh_version, user_agent, ip_address)`
  - Key FKs: user_id.
- `secrets(value, created_at, updated_at, key, description)`
- `settings(id, activity_category_standard_id, country_id, only_one_setting, report_partition_count)`
  - Key FKs: activity_category_standard_id, country_id.
- `region_access(id, user_id, region_id)`
  - Key FKs: region_id, user_id.
- `activity_category_access(id, user_id, activity_category_id)`
  - Key FKs: activity_category_id, user_id.
- `migration(id, filename, applied_at, version, description, duration_ms)`
- `registered_callback and `supported_table`(label, table_names, priority, generate_procedure, cleanup_procedure)`

## Helper Views & Common Patterns
The schema includes numerous helper views, often for UI dropdowns or specific data access patterns. They follow consistent naming conventions:

- `*_upload*`: Stores raw data from user file uploads for an import job. Transient.
- `*_data*`: Intermediate data table for an import job, holding source data and analysis results. Transient.
- `*_def*`: The definition of a view, often used as a building block for other views.
- `*_used*`: Views showing distinct classification values currently in use.
- `*_available*`: Views listing all available classification codes (system-defined + custom).
- `*_custom*`: Writable views for inserting new custom classification codes.
- `*_system*`: Writable views for inserting new system-defined classification codes (typically used during initial setup).
- `*_ordered*`: Views providing a specific sort order for classifications, often for UI display.
- `*_active*`: Views that filter for only the `enabled` records in a classification table.
- `*__for_portion_of_valid*`: Helper view created by sql_saga for temporal REST updates (FOR PORTION OF).
- `*_custom_only*`: Helper view for listing and loading custom classification data, separating it from system-provided data.
- `*_staging*`: Internal staging table for bulk inserts, merged into main table at end of batch processing.


## Naming Conventions (from `CONVENTIONS.md`)
- `x_id`: Foreign key to table `x`.
- `x_ident`: External identifier (not originating from this database).
- `x_at`: Timestamp with time zone (TIMESTAMPTZ).
- `x_on`: Date (DATE).

