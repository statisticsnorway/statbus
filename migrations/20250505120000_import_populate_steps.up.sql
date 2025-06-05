-- Migration:
-- Defines the standard import steps and their static data columns.
-- This is created early to ensure step_ids are available for dynamic column generation.

BEGIN;

-- Define standard import steps
-- These represent logical components of importing a statistical unit.
INSERT INTO public.import_step (code, name, priority, analyse_procedure, process_procedure) VALUES
    ('external_idents',                  'External Identifiers',       10, 'import.analyse_external_idents'::regproc, NULL),
    ('valid_time_from_context',          'Validity (Context)',         15, 'import.analyse_valid_time_from_context'::regproc, NULL),
    ('valid_time_from_source',           'Validity (Source)',          15, 'import.analyse_valid_time_from_source'::regproc, NULL),
    ('enterprise_link_for_legal_unit',   'Link LU to Enterprise',      18, 'import.analyse_enterprise_link_for_legal_unit'::regproc, 'import.process_enterprise_link_for_legal_unit'::regproc),
    ('enterprise_link_for_establishment','Link EST to Enterprise',     19, 'import.analyse_enterprise_link_for_establishment'::regproc, 'import.process_enterprise_link_for_establishment'::regproc),
    ('link_establishment_to_legal_unit', 'Link EST to LU',             19, 'import.analyse_link_establishment_to_legal_unit'::regproc, NULL), -- Changed priority from 25 to 19
    ('status',                'Status Resolution',          17, 'import.analyse_status'::regproc, NULL), -- New Status Step
    ('legal_unit',                       'Legal Unit Core',            20, 'import.analyse_legal_unit'::regproc,                     'import.process_legal_unit'::regproc),
    ('establishment',                    'Establishment Core',         20, 'import.analyse_establishment'::regproc,                  'import.process_establishment'::regproc),
    ('physical_location',                'Physical Location',          30, 'import.analyse_location'::regproc,                       'import.process_location'::regproc),
    ('postal_location',                  'Postal Location',            40, 'import.analyse_location'::regproc,                       'import.process_location'::regproc),
    ('primary_activity',                 'Primary Activity',           50, 'import.analyse_activity'::regproc,                       'import.process_activity'::regproc),
    ('secondary_activity',               'Secondary Activity',         60, 'import.analyse_activity'::regproc,                       'import.process_activity'::regproc),
    ('contact',                          'Contact Info',               70, 'import.analyse_contact'::regproc,                        'import.process_contact'::regproc),
    ('statistical_variables',            'Statistical Variables',      80, 'import.analyse_statistical_variables'::regproc,          'import.process_statistical_variables'::regproc),
    ('tags',                             'Tags',                       90, 'import.analyse_tags'::regproc,                           'import.process_tags'::regproc),
    ('edit_info',                        'Edit Info',                 100, 'import.analyse_edit_info'::regproc,               NULL),
    ('metadata',                         'Job Row Metadata',          110, NULL,                                                                        NULL)
ON CONFLICT (code) DO NOTHING;

-- Define Static Data Columns for each Step
-- These are the columns inherently required or produced by each step's logic.
-- Dynamic columns (like specific external idents or stats) are added by lifecycle callbacks.
WITH ordered_values AS (
    SELECT
        *,
        ROW_NUMBER() OVER () as original_order -- Preserves order of VALUES list
    FROM (
        VALUES
        -- step_code, column_name, column_type, purpose, is_nullable, default_value, is_uniquely_identifying
        ('external_idents', 'operation', 'public.import_row_operation_type', 'internal', true, NULL, false),
        ('external_idents', 'action', 'public.import_row_action_type', 'internal', true, NULL, false),
        ('enterprise_link_for_legal_unit',   'enterprise_id',               'INTEGER',   'internal', true, NULL, false),
        ('enterprise_link_for_legal_unit',   'primary_for_enterprise',      'BOOLEAN',   'internal', true, NULL, false),
        ('enterprise_link_for_establishment', 'enterprise_id', 'INTEGER', 'internal', true, NULL, false),
        ('enterprise_link_for_establishment', 'primary_for_enterprise',    'BOOLEAN', 'internal', true, NULL, false),
        ('link_establishment_to_legal_unit', 'legal_unit_id',        'INTEGER', 'pk_id',    true, NULL, false),
        ('link_establishment_to_legal_unit', 'primary_for_legal_unit','BOOLEAN',   'internal', true, NULL, false),
        ('valid_time_from_context', 'derived_valid_after', 'DATE', 'internal', true, NULL, false), -- Added derived_valid_after
        ('valid_time_from_context', 'derived_valid_from',  'DATE', 'internal', true, NULL, false),
        ('valid_time_from_context', 'derived_valid_to',    'DATE', 'internal', true, NULL, false),
        ('valid_time_from_source', 'valid_from',            'TEXT', 'source_input', true, NULL, false),
        ('valid_time_from_source', 'valid_to',              'TEXT', 'source_input', true, NULL, false),
        ('valid_time_from_source', 'derived_valid_after',   'DATE', 'internal',     true, NULL, false),
        ('valid_time_from_source', 'derived_valid_from',    'DATE', 'internal',     true, NULL, false),
        ('valid_time_from_source', 'derived_valid_to',      'DATE', 'internal',     true, NULL, false),
        ('status', 'status_code',                'TEXT',    'source_input', true, NULL, false),
        ('status', 'status_id',                  'INTEGER', 'internal',     true, NULL, false),
        ('legal_unit', 'name',                           'TEXT',    'source_input', true, NULL, false),
        ('legal_unit', 'birth_date',                     'TEXT',    'source_input', true, NULL, false),
        ('legal_unit', 'death_date',                     'TEXT',    'source_input', true, NULL, false),
        ('legal_unit', 'sector_code',                    'TEXT',    'source_input', true, NULL, false),
        ('legal_unit', 'unit_size_code',                 'TEXT',    'source_input', true, NULL, false),
        ('legal_unit', 'legal_form_code',                'TEXT',    'source_input', true, NULL, false),
        ('legal_unit', 'data_source_code',               'TEXT',    'source_input', true, NULL, false),
        ('legal_unit', 'legal_unit_id',                  'INTEGER', 'pk_id',        true, NULL, false),
        ('legal_unit', 'sector_id',                      'INTEGER', 'internal',     true, NULL, false),
        ('legal_unit', 'unit_size_id',                   'INTEGER', 'internal',     true, NULL, false),
        ('legal_unit', 'legal_form_id',                  'INTEGER', 'internal',     true, NULL, false),
        ('legal_unit', 'data_source_id',                 'INTEGER', 'internal',     true, NULL, false),
        ('legal_unit', 'typed_birth_date',               'DATE',    'internal',     true, NULL, false),
        ('legal_unit', 'typed_death_date',               'DATE',    'internal',     true, NULL, false),
        ('establishment', 'name',                           'TEXT',    'source_input', true, NULL, false),
        ('establishment', 'birth_date',                     'TEXT',    'source_input', true, NULL, false),
        ('establishment', 'death_date',                     'TEXT',    'source_input', true, NULL, false),
        ('establishment', 'sector_code',                    'TEXT',    'source_input', true, NULL, false),
        ('establishment', 'unit_size_code',                 'TEXT',    'source_input', true, NULL, false),
        ('establishment', 'data_source_code',               'TEXT',    'source_input', true, NULL, false),
        ('establishment', 'establishment_id',               'INTEGER', 'pk_id',        true, NULL, false),
        ('establishment', 'sector_id',                      'INTEGER', 'internal',     true, NULL, false),
        ('establishment', 'unit_size_id',                   'INTEGER', 'internal',     true, NULL, false),
        ('establishment', 'data_source_id',                 'INTEGER', 'internal',     true, NULL, false),
        ('establishment', 'typed_birth_date',               'DATE',    'internal',     true, NULL, false),
        ('establishment', 'typed_death_date',               'DATE',    'internal',     true, NULL, false),
        ('physical_location', 'physical_address_part1',      'TEXT',    'source_input', true, NULL, false),
        ('physical_location', 'physical_address_part2',      'TEXT',    'source_input', true, NULL, false),
        ('physical_location', 'physical_address_part3',      'TEXT',    'source_input', true, NULL, false),
        ('physical_location', 'physical_postcode',           'TEXT',    'source_input', true, NULL, false),
        ('physical_location', 'physical_postplace',          'TEXT',    'source_input', true, NULL, false),
        ('physical_location', 'physical_latitude',           'TEXT',    'source_input', true, NULL, false),
        ('physical_location', 'physical_longitude',          'TEXT',    'source_input', true, NULL, false),
        ('physical_location', 'physical_altitude',           'TEXT',    'source_input', true, NULL, false),
        ('physical_location', 'physical_region_code',        'TEXT',    'source_input', true, NULL, false),
        ('physical_location', 'physical_country_iso_2',      'TEXT',    'source_input', true, NULL, false),
        ('physical_location', 'physical_location_id',        'INTEGER', 'pk_id',        true, NULL, false),
        ('physical_location', 'physical_region_id',          'INTEGER', 'internal',     true, NULL, false),
        ('physical_location', 'physical_country_id',         'INTEGER', 'internal',     true, NULL, false),
        ('physical_location', 'typed_physical_latitude',     'numeric(9,6)', 'internal', true, NULL, false),
        ('physical_location', 'typed_physical_longitude',    'numeric(9,6)', 'internal', true, NULL, false),
        ('physical_location', 'typed_physical_altitude',     'numeric(6,1)', 'internal', true, NULL, false),
        ('postal_location',   'postal_address_part1',        'TEXT',    'source_input', true, NULL, false),
        ('postal_location',   'postal_address_part2',        'TEXT',    'source_input', true, NULL, false),
        ('postal_location',   'postal_address_part3',        'TEXT',    'source_input', true, NULL, false),
        ('postal_location',   'postal_postcode',             'TEXT',    'source_input', true, NULL, false),
        ('postal_location',   'postal_postplace',            'TEXT',    'source_input', true, NULL, false),
        ('postal_location',   'postal_region_code',          'TEXT',    'source_input', true, NULL, false),
        ('postal_location',   'postal_country_iso_2',        'TEXT',    'source_input', true, NULL, false),
        ('postal_location',   'postal_latitude',             'TEXT',    'source_input', true, NULL, false),
        ('postal_location',   'postal_longitude',            'TEXT',    'source_input', true, NULL, false),
        ('postal_location',   'postal_altitude',             'TEXT',    'source_input', true, NULL, false),
        ('postal_location',   'postal_location_id',          'INTEGER', 'pk_id',        true, NULL, false),
        ('postal_location',   'postal_region_id',            'INTEGER', 'internal',     true, NULL, false),
        ('postal_location',   'postal_country_id',           'INTEGER', 'internal',     true, NULL, false),
        ('postal_location',   'typed_postal_latitude',       'numeric(9,6)', 'internal', true, NULL, false),
        ('postal_location',   'typed_postal_longitude',      'numeric(9,6)', 'internal', true, NULL, false),
        ('postal_location',   'typed_postal_altitude',       'numeric(6,1)', 'internal', true, NULL, false),
        ('primary_activity',  'primary_activity_category_code', 'TEXT', 'source_input', true, NULL, false),
        ('primary_activity',  'primary_activity_id',         'INTEGER', 'pk_id',        true, NULL, false),
        ('primary_activity',  'primary_activity_category_id','INTEGER', 'internal',     true, NULL, false),
        ('secondary_activity','secondary_activity_category_code', 'TEXT', 'source_input', true, NULL, false),
        ('secondary_activity','secondary_activity_id',       'INTEGER', 'pk_id',        true, NULL, false),
        ('secondary_activity','secondary_activity_category_id','INTEGER', 'internal',     true, NULL, false),
        ('contact',      'web_address',                 'TEXT',    'source_input', true, NULL, false),
        ('contact',      'email_address',               'TEXT',    'source_input', true, NULL, false),
        ('contact',      'phone_number',                'TEXT',    'source_input', true, NULL, false),
        ('contact',      'landline',                    'TEXT',    'source_input', true, NULL, false),
        ('contact',      'mobile_number',               'TEXT',    'source_input', true, NULL, false),
        ('contact',      'fax_number',                  'TEXT',    'source_input', true, NULL, false),
        ('contact',      'contact_id',                  'INTEGER', 'pk_id',        true, NULL, false),
        ('tags',             'tag_path',                    'TEXT',    'source_input', true, NULL, false),
        ('tags',             'tag_path_ltree',              'public.LTREE', 'internal', true, NULL, false),
        ('tags',             'tag_id',                      'INTEGER', 'internal',     true, NULL, false),
        ('tags',             'tag_for_unit_id',             'INTEGER', 'pk_id',        true, NULL, false),
        ('edit_info',         'edit_by_user_id',             'INTEGER',   'internal', true, NULL, false),
        ('edit_info',         'edit_at',                     'TIMESTAMPTZ','internal', true, NULL, false),
        ('edit_info',         'edit_comment',                'TEXT',      'internal', true, NULL, false),
        ('metadata',          'founding_row_id',             'BIGINT',    'internal', true, NULL,          false), -- Added: For linking temporal records of the same entity
        ('metadata',          'state',                       'public.import_data_state','metadata', false, '''pending''', false),
        ('metadata',          'last_completed_priority',     'INTEGER',   'metadata', false, '0',           false),
        ('metadata',          'error',                       'JSONB',     'metadata', true,  NULL,          false),
        ('metadata',          'invalid_codes',               'JSONB',     'metadata', true,  NULL,          false)
    ) AS v_raw(step_code, column_name, column_type, purpose, is_nullable, default_value, is_uniquely_identifying)
),
values_with_priority AS (
    SELECT
        ov.step_code, ov.column_name, ov.column_type, ov.purpose,
        ov.is_nullable, ov.default_value, ov.is_uniquely_identifying,
        ROW_NUMBER() OVER (PARTITION BY ov.step_code ORDER BY ov.original_order) as derived_priority
    FROM ordered_values ov
)
INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, default_value, is_uniquely_identifying, priority)
SELECT
    s.id, v.column_name, v.column_type, v.purpose::public.import_data_column_purpose,
    COALESCE(v.is_nullable, true), v.default_value, COALESCE(v.is_uniquely_identifying, false),
    v.derived_priority
FROM public.import_step s
JOIN values_with_priority v ON s.code = v.step_code
ON CONFLICT (step_id, column_name) DO NOTHING;

-- Dynamically create import_data_column entries for statistical variables
-- This is now handled by the lifecycle callback import.generate_stat_var_data_columns()
-- called in migration 20250506120000_import_lifecycle_for_stat_definition_import_data_columns.up.sql
-- No action needed here for that specific purpose.

COMMIT;
