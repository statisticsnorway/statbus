# StatBus Data Model Summary

This document provides a compact overview of the StatBus database schema, focusing on entities, relationships, and key patterns.

## Core Statistical Units (Hierarchy)
The system revolves around four main statistical units, often with temporal validity (`valid_from`, `valid_after`, `valid_to`):
- `enterprise_group(id, name, short_name, enterprise_group_type_id, unit_size_id, data_source_id, reorg_type_id, foreign_participation_id, valid_from, valid_after, valid_to, active, ...)` (EG) (temporal)
  - Key FKs: `enterprise_group_type_id`, `unit_size_id`, `data_source_id`, `reorg_type_id`, `foreign_participation_id`.
- `enterprise(id, short_name, active, edit_by_user_id, ...)` (E)
  - Belongs to an EG implicitly. Core attributes are often linked via its Legal Units or Establishments.
- `legal_unit(id, name, short_name, enterprise_id, sector_id, status_id, legal_form_id, unit_size_id, foreign_participation_id, data_source_id, valid_from, valid_after, valid_to, active, ...)` (LU) (temporal)
  - Belongs to one `enterprise` (E). (Relationship: E 1--* LU)
  - Key FKs: `enterprise_id`, `sector_id`, `status_id`, `legal_form_id`, `unit_size_id`, `foreign_participation_id`, `data_source_id`.
- `establishment(id, name, short_name, legal_unit_id, enterprise_id, sector_id, status_id, unit_size_id, data_source_id, valid_from, valid_after, valid_to, active, ...)` (EST) (temporal)
  - Belongs to one `legal_unit` (LU) OR one `enterprise` (E) directly (if not part of an LU).
  - Key FKs: `legal_unit_id` (opt), `enterprise_id` (opt, XOR with `legal_unit_id`), `sector_id` (if `enterprise_id` is set), `status_id`, `unit_size_id`, `data_source_id`.

## Common Links for Core Units (EG, E, LU, EST)
These tables link to any of the four core statistical units:
- `external_ident(id, ident, type_id, establishment_id, legal_unit_id, enterprise_id, enterprise_group_id, ...)`: Links a CoreUnit to an `external_ident_type`. Stores various external identifiers.
- `tag_for_unit(id, tag_id, establishment_id, legal_unit_id, enterprise_id, enterprise_group_id, ...)`: Links a CoreUnit to a `tag`.
- `unit_notes(id, notes, establishment_id, legal_unit_id, enterprise_id, enterprise_group_id, ...)`: Stores textual notes for a CoreUnit (1-to-1 relationship).

## Key Supporting Entities & Classifications

### Activity
- `activity(id, type, category_id, establishment_id, legal_unit_id, data_source_id, valid_from, valid_after, valid_to, ...)` (temporal): Links `establishment` or `legal_unit` to an `activity_category`.
  - FKs: `establishment_id` (opt) / `legal_unit_id` (opt), `category_id` (->`activity_category`), `data_source_id`.
- `activity_category(id, standard_id, path, parent_id, code, name, active, custom, ...)`: Defines activity classifications (e.g., NACE sections, divisions). It is a tree structure using `path` (ltree) and `parent_id`, and has `custom`/`active` flags.
  - FK: `standard_id` (->`activity_category_standard`).
- `activity_category_standard(id, code, name, description, code_pattern, obsolete, ...)`: Defines activity standards (e.g., 'NACE_V2.1', 'ISIC_V4').
- Views for specific standards & custom entries: `activity_category_nace_v2_1(standard, path, code, name, ...)` (writable), `activity_category_isic_v4(standard, path, code, name, ...)` (writable), `activity_category_available_custom(path, name, description, ...)` (writable for new custom categories).

### Location & Contact
- `location(id, type, establishment_id, legal_unit_id, region_id, country_id, data_source_id, address_part1, postcode, valid_from, valid_after, valid_to, ...)` (temporal): Links `establishment` or `legal_unit` to geographical information.
  - FKs: `establishment_id` (opt) / `legal_unit_id` (opt), `region_id`, `country_id`, `data_source_id`.
- `contact(id, establishment_id, legal_unit_id, data_source_id, web_address, email_address, phone_number, valid_from, valid_after, valid_to, ...)` (temporal): Stores contact information for `establishment` or `legal_unit`.
  - FKs: `establishment_id` (opt) / `legal_unit_id` (opt), `data_source_id`.
- `region(id, path, parent_id, code, name, ...)`: Defines administrative or geographical regions. It is a tree structure using `path` (ltree) and `parent_id`.
- `country(id, iso_2, iso_3, iso_num, name, active, custom, ...)`: Defines countries with ISO codes.

### Persons
- `person(id, personal_ident, country_id, given_name, family_name, birth_date, sex, ...)`: Stores information about individuals.
  - FK: `country_id`.
- `person_for_unit(id, person_id, person_role_id, establishment_id, legal_unit_id, data_source_id, valid_from, valid_after, valid_to, ...)` (temporal): Links a `person` to an `establishment` or `legal_unit` with a specific `person_role`.
  - FKs: `person_id`, `person_role_id`, `establishment_id` (opt) / `legal_unit_id` (opt), `data_source_id`.
- `person_role(id, code, name, active, custom, ...)` (code, name, custom/active flags): Defines roles a person can have in relation to a unit.

### Statistics
- `stat_for_unit(id, stat_definition_id, establishment_id, legal_unit_id, data_source_id, value_int, value_float, ..., valid_from, valid_after, valid_to, ...)` (temporal): Stores statistical variable values for an `establishment` or `legal_unit`.
  - FKs: `establishment_id` (opt) / `legal_unit_id` (opt), `stat_definition_id`, `data_source_id`.
- `stat_definition(id, code, type, frequency, name, priority, archived, ...)`: Defines statistical variables (code, type, frequency, name).

### General Code/Classification Tables
These tables typically store codes, names, and flags for `custom` and `active` status.
- `data_source(id, code, name, active, custom, ...)`
- `enterprise_group_type(id, code, name, active, custom, ...)`
- `external_ident_type(id, code, name, by_tag_id, priority, archived, ...)` (can be linked to `tag.id` via `by_tag_id`)
- `foreign_participation(id, code, name, active, custom, ...)`
- `legal_form(id, code, name, active, custom, ...)`
- `reorg_type(id, code, name, description, active, custom, ...)` (reorganization types)
- `sector(id, path, parent_id, code, name, active, custom, ...)`: Defines economic sectors. It is a tree structure using `path` (ltree) and `parent_id`.
- `status(id, code, name, assigned_by_default, include_unit_in_reports, priority, active, custom, ...)` (unit status, e.g., active, inactive; has `assigned_by_default`, `include_unit_in_reports` flags)
- `tag(id, path, parent_id, code, name, type, active, context_valid_from, context_valid_to, ...)`: User-defined tags. It is a tree structure using `path` (ltree) and `parent_id`, and can have an optional time context `context_valid_from/to/on`.
- `unit_size(id, code, name, active, custom, ...)` (e.g., based on employee count)

## Temporal Data & History
- `statistical_unit(unit_type, unit_id, valid_after, valid_to, name, external_idents, primary_activity_category_path, sector_path, legal_form_code, physical_region_path, status_code, ...)` (VIEW): The primary denormalized view providing the current state of all units (EG, E, LU, EST). Key data source for the API.
- `timeline_establishment(unit_type, unit_id, valid_after, valid_to, name, establishment_id, legal_unit_id, enterprise_id, ...)` , `timeline_legal_unit(unit_type, unit_id, valid_after, valid_to, name, legal_unit_id, enterprise_id, ...)` , `timeline_enterprise(unit_type, unit_id, valid_after, valid_to, name, enterprise_id, ...)` (TABLES): Materialized, versioned history for specific unit types. These are derived from changes in the base tables.
- `timesegments(unit_type, unit_id, valid_after, valid_to)` (TABLE): Tracks distinct `valid_after`/`valid_to` periods for units, used for historical queries.
- `statistical_history(resolution, year, month, unit_type, count, births, deaths, ...)` (TABLE): Aggregated data like total counts, births, deaths, and change counts, by resolution (year, year-month) and `unit_type`.
- `statistical_history_facet(resolution, year, month, unit_type, primary_activity_category_path, sector_path, legal_form_id, physical_region_path, count, births, deaths, ...)` (TABLE): More granular `statistical_history` including facets like activity category, sector, region, etc.

## Import System
Handles the ingestion of data from external files.
- `import_definition(id, slug, name, data_source_id, user_id, strategy, mode, valid, ...)`: Defines an import process (slug, name, strategy, mode).
  - FKs: `data_source_id`, `user_id`.
  - `import_definition_step(definition_id, step_id)` (M:N): Links `import_definition` to `import_step`.
- `import_step(id, code, name, priority, analyse_procedure, process_procedure, ...)`: A stage in an import process (e.g., data validation, transformation).
  - Defines `analyse_procedure` and `process_procedure`.
- `import_source_column(id, definition_id, column_name, priority, ...)`: Defines columns expected in the source file for an `import_definition`.
- `import_data_column(id, step_id, column_name, column_type, purpose, ...)`: Defines columns in the temporary table used by an `import_step`.
- `import_mapping(id, definition_id, source_column_id, source_value, source_expression, target_data_column_id, ...)`: Maps source data (columns, fixed values, expressions) to target `import_data_column`s for an `import_definition`.
- `import_job(id, slug, definition_id, user_id, state, upload_table_name, data_table_name, total_rows, imported_rows, ...)`: Represents an instance of an import execution (state machine: waiting_for_upload, analysing, processing, completed, failed).
  - FKs: `definition_id`, `user_id`.
  - Manages temporary `upload_table_name` and `data_table_name`.

## Worker System
Handles background processing. A long-running worker process calls `worker.process_tasks()` to process tasks synchronously.
- `worker.tasks(id, command, priority, state, created_at, processed_at, duration_ms, error, scheduled_at, worker_pid, payload)`: The main queue table. Stores tasks with their state, payload, and timing. The `worker_pid` column stores the PostgreSQL backend process ID of the session executing the task, used for cleaning up stale connections.
- `worker.command_registry(command, handler_procedure, before_procedure, after_procedure, queue, ...)`: Maps a `command` name to a PostgreSQL `handler_procedure` and assigns it to a `queue`.
- `worker.queue_registry(queue, concurrent, ...)`: Defines available task queues (e.g., 'analytics', 'maintenance') and concurrency rules.

## Auth & System Tables/Views
- `auth.user(id, sub, email, statbus_role, ...)`: User accounts, stores `statbus_role` (e.g., `admin_user`, `regular_user`).
- `auth.api_key(id, jti, user_id, token, expires_at, ...)`: API keys for users.
- `auth.refresh_session(id, jti, user_id, expires_at, ...)`: User refresh tokens for session management.
- `settings(id, activity_category_standard_id, only_one_setting)` (singleton table): Application-wide settings, e.g., default `activity_category_standard_id`.
- `region_access(id, user_id, region_id)` (M:N): Links `auth.user` to `region`, controlling data access by region.
- `activity_category_access(id, user_id, activity_category_id)` (M:N): Links `auth.user` to `activity_category`, controlling data access by activity.
- `db.migration(id, version, filename, applied_at, ...)`: Tracks applied database schema migrations.
- `lifecycle_callbacks.registered_callback(label, priority, table_names, generate_procedure, cleanup_procedure)` and `lifecycle_callbacks.supported_table(table_name, ...)`: Internal system for managing data generation and cleanup based on table changes.
- **Helper Views:**
    - `*_used_def` (e.g., `country_used_def(id, iso_2, name)`): Views showing distinct classification values currently in use (often for UI dropdowns).
    - `*_available` (e.g., `legal_form_available(id, code, name, active, custom, ...)`): Views listing all available classification codes (system-defined + custom).
    - `*_custom` (e.g., `sector_custom(path, name, description, ...)`): Writable views for inserting new custom classification codes.
    - `*_system` (e.g., `data_source_system(code, name, ...)`): Writable views for inserting new system-defined classification codes (typically used during initial setup).
    - `*_ordered` (e.g., `external_ident_type_ordered(id, code, name, priority, ...)`): Views providing a specific sort order for classifications, often for UI display.

## Naming Conventions (from `CONVENTIONS.md`)
- `x_id`: Foreign key to table `x`.
- `x_ident`: External identifier (not originating from this database).
- `x_at`: Timestamp with time zone (TIMESTAMPTZ).
- `x_on`: Date (DATE).
