-- Migration 20250228000000: generate_default_import_definitions
BEGIN;

-- Define standard import steps
-- These represent logical components of importing a statistical unit.
-- Procedures are placeholders initially and will be implemented later.
INSERT INTO public.import_step (code, name, priority, analyse_procedure, process_procedure) VALUES
    ('external_idents',                  'External Identifiers',       10, 'admin.analyse_external_idents'::regproc, NULL), -- Process procedure removed, analysis resolves IDs
    ('valid_time_from_context',          'Validity (Context)',         15, 'admin.analyse_valid_time_from_context'::regproc, NULL),
    ('valid_time_from_source',           'Validity (Source)',          15, 'admin.analyse_valid_time_from_source'::regproc, NULL),
    ('enterprise_link_for_legal_unit',   'Link LU to Enterprise',      18, 'admin.analyse_enterprise_link_for_legal_unit'::regproc, 'admin.process_enterprise_link_for_legal_unit'::regproc), -- For LUs
    ('enterprise_link_for_establishment','Link EST to Enterprise',     19, 'admin.analyse_enterprise_link_for_establishment'::regproc, 'admin.process_enterprise_link_for_establishment'::regproc), -- For standalone ESTs
    ('legal_unit',                       'Legal Unit Core',            20, 'admin.analyse_legal_unit'::regproc,                     'admin.process_legal_unit'::regproc),
    ('establishment',                    'Establishment Core',         20, 'admin.analyse_establishment'::regproc,                  'admin.process_establishment'::regproc),
    ('link_establishment_to_legal_unit', 'Link EST to LU',             25, 'admin.analyse_link_establishment_to_legal_unit'::regproc, NULL),
    ('physical_location',                'Physical Location',          30, 'admin.analyse_location'::regproc,                       'admin.process_location'::regproc),
    ('postal_location',                  'Postal Location',            40, 'admin.analyse_location'::regproc,                       'admin.process_location'::regproc),
    ('primary_activity',                 'Primary Activity',           50, 'admin.analyse_activity'::regproc,                       'admin.process_activity'::regproc),
    ('secondary_activity',               'Secondary Activity',         60, 'admin.analyse_activity'::regproc,                       'admin.process_activity'::regproc),
    ('contact',                          'Contact Info',               70, 'admin.analyse_contact'::regproc,                        'admin.process_contact'::regproc),
    ('statistical_variables',            'Statistical Variables',      80, 'admin.analyse_statistical_variables'::regproc,          'admin.process_statistical_variables'::regproc),
    ('tags',                             'Tags',                       90, 'admin.analyse_tags'::regproc,                           'admin.process_tags'::regproc),
    ('edit_info',                        'Edit Info',                 100, 'admin.analyse_edit_info'::regproc,               NULL), -- Step to populate common edit columns
    ('metadata',                         'Job Row Metadata',          110, NULL,                                                                        NULL) -- Handles row state, error, last_completed_priority
ON CONFLICT (code) DO NOTHING; -- Avoid errors if run multiple times

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
        -- external_idents (pk_id columns 'legal_unit_id' and 'establishment_id' are defined by the 'legal_unit' and 'establishment' steps respectively;
        -- this step resolves and populates them. Source_input columns for external_idents are dynamic, added by lifecycle callbacks.)
        -- enterprise_link (for LUs)
        ('enterprise_link_for_legal_unit',   'enterprise_id',               'INTEGER',   'internal', true, NULL, false),
        ('enterprise_link_for_legal_unit',   'is_primary',                  'BOOLEAN',   'internal', true, NULL, false),
        -- enterprise_link_for_establishment (for standalone ESTs)
        ('enterprise_link_for_establishment', 'enterprise_id', 'INTEGER', 'internal', true, NULL, false), -- Populates the same column
        ('enterprise_link_for_establishment', 'is_primary',    'BOOLEAN', 'internal', true, NULL, false), -- Populates the same column
        -- valid_time_from_context (now populates derived_valid_from/to)
        ('valid_time_from_context', 'derived_valid_from',  'DATE', 'internal', true, NULL, false),
        ('valid_time_from_context', 'derived_valid_to',    'DATE', 'internal', true, NULL, false),
        -- valid_time_from_source (now populates derived_valid_from/to)
        ('valid_time_from_source', 'valid_from',            'TEXT', 'source_input', true, NULL, false), -- Source text
        ('valid_time_from_source', 'valid_to',              'TEXT', 'source_input', true, NULL, false), -- Source text
        ('valid_time_from_source', 'derived_valid_from',    'DATE', 'internal',     true, NULL, false), -- Common derived date
        ('valid_time_from_source', 'derived_valid_to',      'DATE', 'internal',     true, NULL, false), -- Common derived date
        -- legal_unit
        ('legal_unit', 'name',                           'TEXT',    'source_input', true, NULL, false),
        ('legal_unit', 'birth_date',                     'TEXT',    'source_input', true, NULL, false),
        ('legal_unit', 'death_date',                     'TEXT',    'source_input', true, NULL, false),
        ('legal_unit', 'sector_code',                    'TEXT',    'source_input', true, NULL, false),
        ('legal_unit', 'unit_size_code',                 'TEXT',    'source_input', true, NULL, false),
        ('legal_unit', 'status_code',                    'TEXT',    'source_input', true, NULL, false),
        ('legal_unit', 'legal_form_code',                'TEXT',    'source_input', true, NULL, false),
        ('legal_unit', 'data_source_code',               'TEXT',    'source_input', true, NULL, false),
        ('legal_unit', 'legal_unit_id',                  'INTEGER', 'pk_id',        true, NULL, false),
        ('legal_unit', 'sector_id',                      'INTEGER', 'internal',     true, NULL, false),
        ('legal_unit', 'unit_size_id',                   'INTEGER', 'internal',     true, NULL, false),
        ('legal_unit', 'status_id',                      'INTEGER', 'internal',     true, NULL, false),
        ('legal_unit', 'legal_form_id',                  'INTEGER', 'internal',     true, NULL, false),
        ('legal_unit', 'data_source_id',                 'INTEGER', 'internal',     true, NULL, false),
        ('legal_unit', 'typed_birth_date',               'DATE',    'internal',     true, NULL, false),
        ('legal_unit', 'typed_death_date',               'DATE',    'internal',     true, NULL, false),
        -- establishment
        ('establishment', 'name',                           'TEXT',    'source_input', true, NULL, false),
        ('establishment', 'birth_date',                     'TEXT',    'source_input', true, NULL, false),
        ('establishment', 'death_date',                     'TEXT',    'source_input', true, NULL, false),
        ('establishment', 'sector_code',                    'TEXT',    'source_input', true, NULL, false),
        ('establishment', 'unit_size_code',                 'TEXT',    'source_input', true, NULL, false),
        ('establishment', 'status_code',                    'TEXT',    'source_input', true, NULL, false),
        ('establishment', 'data_source_code',               'TEXT',    'source_input', true, NULL, false),
        ('establishment', 'establishment_id',               'INTEGER', 'pk_id',        true, NULL, false),
        ('establishment', 'sector_id',                      'INTEGER', 'internal',     true, NULL, false),
        ('establishment', 'unit_size_id',                   'INTEGER', 'internal',     true, NULL, false),
        ('establishment', 'status_id',                      'INTEGER', 'internal',     true, NULL, false),
        ('establishment', 'data_source_id',                 'INTEGER', 'internal',     true, NULL, false),
        ('establishment', 'typed_birth_date',               'DATE',    'internal',     true, NULL, false),
        ('establishment', 'typed_death_date',               'DATE',    'internal',     true, NULL, false),
        -- link_establishment_to_legal_unit (pk_id column only; source_input are dynamic)
        -- The column 'linked_legal_unit_id' stores the pk_id of the Legal Unit an Establishment is linked to.
        ('link_establishment_to_legal_unit', 'linked_legal_unit_id', 'INTEGER', 'pk_id', true, NULL, false),
        -- physical_location
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
        -- postal_location
        ('postal_location',   'postal_address_part1',        'TEXT',    'source_input', true, NULL, false),
        ('postal_location',   'postal_address_part2',        'TEXT',    'source_input', true, NULL, false),
        ('postal_location',   'postal_address_part3',        'TEXT',    'source_input', true, NULL, false),
        ('postal_location',   'postal_postcode',             'TEXT',    'source_input', true, NULL, false),
        ('postal_location',   'postal_postplace',            'TEXT',    'source_input', true, NULL, false),
        ('postal_location',   'postal_region_code',          'TEXT',    'source_input', true, NULL, false),
        ('postal_location',   'postal_country_iso_2',        'TEXT',    'source_input', true, NULL, false),
        ('postal_location',   'postal_latitude',             'TEXT',    'source_input', true, NULL, false), -- Added for completeness, though typically NULL
        ('postal_location',   'postal_longitude',            'TEXT',    'source_input', true, NULL, false), -- Added for completeness, though typically NULL
        ('postal_location',   'postal_altitude',             'TEXT',    'source_input', true, NULL, false), -- Added for completeness, though typically NULL
        ('postal_location',   'postal_location_id',          'INTEGER', 'pk_id',        true, NULL, false),
        ('postal_location',   'postal_region_id',            'INTEGER', 'internal',     true, NULL, false),
        ('postal_location',   'postal_country_id',           'INTEGER', 'internal',     true, NULL, false),
        ('postal_location',   'typed_postal_latitude',       'numeric(9,6)', 'internal', true, NULL, false), -- Added for completeness
        ('postal_location',   'typed_postal_longitude',      'numeric(9,6)', 'internal', true, NULL, false), -- Added for completeness
        ('postal_location',   'typed_postal_altitude',       'numeric(6,1)', 'internal', true, NULL, false), -- Added for completeness
        -- primary_activity
        ('primary_activity',  'primary_activity_category_code', 'TEXT', 'source_input', true, NULL, false),
        ('primary_activity',  'primary_activity_id',         'INTEGER', 'pk_id',        true, NULL, false),
        ('primary_activity',  'primary_activity_category_id','INTEGER', 'internal',     true, NULL, false),
        -- secondary_activity
        ('secondary_activity','secondary_activity_category_code', 'TEXT', 'source_input', true, NULL, false),
        ('secondary_activity','secondary_activity_id',       'INTEGER', 'pk_id',        true, NULL, false),
        ('secondary_activity','secondary_activity_category_id','INTEGER', 'internal',     true, NULL, false),
        -- contact
        ('contact',      'web_address',                 'TEXT',    'source_input', true, NULL, false),
        ('contact',      'email_address',               'TEXT',    'source_input', true, NULL, false),
        ('contact',      'phone_number',                'TEXT',    'source_input', true, NULL, false),
        ('contact',      'landline',                    'TEXT',    'source_input', true, NULL, false),
        ('contact',      'mobile_number',               'TEXT',    'source_input', true, NULL, false),
        ('contact',      'fax_number',                  'TEXT',    'source_input', true, NULL, false),
        ('contact',      'contact_id',                  'INTEGER', 'pk_id',        true, NULL, false),
        -- statistical_variables (source_input and pk_id columns are dynamic)
        -- tags
        ('tags',             'tag_path',                    'TEXT',    'source_input', true, NULL, false),
        ('tags',             'tag_id',                      'INTEGER', 'internal',     true, NULL, false),
        ('tags',             'tag_for_unit_id',             'INTEGER', 'pk_id',        true, NULL, false),
        -- edit_info
        ('edit_info',         'edit_by_user_id',             'INTEGER',   'internal', true, NULL, false),
        ('edit_info',         'edit_at',                     'TIMESTAMPTZ','internal', true, NULL, false),
        -- Metadata step columns
        ('metadata',          'state',                       'public.import_data_state','metadata', false, '''pending''', false),
        ('metadata',          'last_completed_priority',     'INTEGER',   'metadata', false, '0',           false),
        ('metadata',          'error',                       'JSONB',     'metadata', true,  NULL,          false)
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


-- Helper function to link steps to a definition
CREATE OR REPLACE FUNCTION admin.link_steps_to_definition(
    p_definition_id INT,
    p_step_codes TEXT[]
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.import_definition_step (definition_id, step_id)
    SELECT p_definition_id, s.id
    FROM public.import_step s
    WHERE s.code = ANY(p_step_codes);
END;
$$;

-- Helper function to create source columns and mappings for a definition
CREATE OR REPLACE FUNCTION admin.create_source_and_mappings_for_definition(
    p_definition_id INT,
    p_source_columns TEXT[] -- Array of source column names expected in the file
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_col_name TEXT;
    v_priority INT := 0;
    v_source_col_id INT;
    v_data_col_id INT;
    v_max_priority INT;
BEGIN
    -- Create static source columns based on input array
    FOREACH v_col_name IN ARRAY p_source_columns
    LOOP
        v_priority := v_priority + 1;
        INSERT INTO public.import_source_column (definition_id, column_name, priority)
        VALUES (p_definition_id, v_col_name, v_priority)
        ON CONFLICT DO NOTHING
        RETURNING id INTO v_source_col_id;

        -- Map static source column to corresponding data column
        IF v_source_col_id IS NOT NULL THEN
            -- Find the target data column by joining through the steps linked to this definition
            SELECT dc.id INTO v_data_col_id
            FROM public.import_definition_step ds
            JOIN public.import_data_column dc ON ds.step_id = dc.step_id
            WHERE ds.definition_id = p_definition_id
              AND dc.column_name = v_col_name
              AND dc.purpose = 'source_input';

            IF v_data_col_id IS NOT NULL THEN
                INSERT INTO public.import_mapping (definition_id, source_column_id, target_data_column_id)
                VALUES (p_definition_id, v_source_col_id, v_data_col_id)
                ON CONFLICT DO NOTHING;
            ELSE
                 RAISE EXCEPTION '[Definition %] No matching source_input data column found for source column %', p_definition_id, v_col_name;
            END IF;
        END IF;
    END LOOP;

    -- Add dynamic source columns and mappings for External Idents
    SELECT COALESCE(MAX(priority), v_priority) INTO v_max_priority FROM public.import_source_column WHERE definition_id = p_definition_id;
    INSERT INTO public.import_source_column (definition_id, column_name, priority)
    SELECT p_definition_id, ext.code, v_max_priority + ROW_NUMBER() OVER (ORDER BY ext.priority)
    FROM public.external_ident_type_active ext
    ON CONFLICT DO NOTHING;

    -- Add dynamic source columns and mappings for Statistical Variables
    SELECT COALESCE(MAX(priority), v_max_priority) INTO v_max_priority FROM public.import_source_column WHERE definition_id = p_definition_id;
    INSERT INTO public.import_source_column (definition_id, column_name, priority)
    SELECT p_definition_id, stat.code, v_max_priority + ROW_NUMBER() OVER (ORDER BY stat.priority)
    FROM public.stat_definition_active stat
    ON CONFLICT DO NOTHING;

    -- Mapping for dynamic columns is now handled by the manual mapping in the definition files
    -- or potentially by specific lifecycle callbacks if needed, not this generic helper.
END;
$$;


DO $$
DECLARE
    def_id INT;
    -- Add 'enterprise_link_for_legal_unit' after 'external_idents' and before 'legal_unit'
    -- Add 'metadata' as the last logical step for all definitions.
    lu_steps TEXT[] := ARRAY['external_idents', 'enterprise_link_for_legal_unit', 'legal_unit', 'physical_location', 'postal_location', 'primary_activity', 'secondary_activity', 'contact', 'statistical_variables', 'tags', 'edit_info', 'metadata'];
    -- Establishment steps linked to LU remain unchanged regarding enterprise_link
    es_steps TEXT[] := ARRAY['external_idents', 'link_establishment_to_legal_unit', 'establishment', 'physical_location', 'postal_location', 'primary_activity', 'secondary_activity', 'contact', 'statistical_variables', 'tags', 'edit_info', 'metadata'];
    -- Add 'enterprise_link_for_establishment' for standalone establishments
    es_no_lu_steps TEXT[] := ARRAY['external_idents', 'enterprise_link_for_establishment', 'establishment', 'physical_location', 'postal_location', 'primary_activity', 'secondary_activity', 'contact', 'statistical_variables', 'tags', 'edit_info', 'metadata'];

    -- Define static source columns expected for Legal Unit imports.
    -- Identifier columns (like tax_ident, stat_ident) are added dynamically later.
    -- Postal coordinates are intentionally excluded as per comments in create_data_columns_for_definition.
    lu_source_cols TEXT[] := ARRAY[
        'name', 'birth_date', 'death_date',
        'physical_address_part1', 'physical_address_part2', 'physical_address_part3', 'physical_postcode', 'physical_postplace', 'physical_latitude', 'physical_longitude', 'physical_altitude', 'physical_region_code', 'physical_country_iso_2',
        'postal_address_part1', 'postal_address_part2', 'postal_address_part3', 'postal_postcode', 'postal_postplace', 'postal_region_code', 'postal_country_iso_2', -- Removed postal coordinates
        'web_address', 'email_address', 'phone_number', 'landline', 'mobile_number', 'fax_number',
        'primary_activity_category_code', 'secondary_activity_category_code',
        'sector_code', 'unit_size_code', 'status_code', 'data_source_code', 'legal_form_code',
        'tag_path'
        -- Dynamic external idents and stats added by helper function
    ];
    lu_explicit_source_cols TEXT[] := lu_source_cols || ARRAY['valid_from', 'valid_to'];

    -- establishment_tax_ident removed, it's handled by dynamic external_ident columns
    -- legal_unit_tax_ident removed, handled dynamically by external_idents step
    -- Postal coordinates are intentionally excluded.
    es_source_cols TEXT[] := ARRAY[
        'name', 'birth_date', 'death_date', -- Removed legal_unit_tax_ident
        'physical_address_part1', 'physical_address_part2', 'physical_address_part3', 'physical_postcode', 'physical_postplace', 'physical_latitude', 'physical_longitude', 'physical_altitude', 'physical_region_code', 'physical_country_iso_2',
        'postal_address_part1', 'postal_address_part2', 'postal_address_part3', 'postal_postcode', 'postal_postplace', 'postal_region_code', 'postal_country_iso_2', -- Removed postal coordinates
        'web_address', 'email_address', 'phone_number', 'landline', 'mobile_number', 'fax_number',
        'primary_activity_category_code', 'secondary_activity_category_code',
        'sector_code', 'unit_size_code', 'status_code', 'data_source_code',
        'tag_path'
        -- Dynamic external idents and stats added by helper function
    ];
    es_explicit_source_cols TEXT[] := es_source_cols || ARRAY['valid_from', 'valid_to'];

    -- establishment_tax_ident removed, it's handled by dynamic external_ident columns
    -- Postal coordinates are intentionally excluded.
    es_no_lu_source_cols TEXT[] := ARRAY[
        'name', 'birth_date', 'death_date', -- No legal_unit_tax_ident
        'physical_address_part1', 'physical_address_part2', 'physical_address_part3', 'physical_postcode', 'physical_postplace', 'physical_latitude', 'physical_longitude', 'physical_altitude', 'physical_region_code', 'physical_country_iso_2',
        'postal_address_part1', 'postal_address_part2', 'postal_address_part3', 'postal_postcode', 'postal_postplace', 'postal_region_code', 'postal_country_iso_2', -- Removed postal coordinates
        'web_address', 'email_address', 'phone_number', 'landline', 'mobile_number', 'fax_number',
        'primary_activity_category_code', 'secondary_activity_category_code',
        'sector_code', 'unit_size_code', 'status_code', 'data_source_code',
        'tag_path'
        -- Dynamic external idents and stats added by helper function
    ];
    es_no_lu_explicit_source_cols TEXT[] := es_no_lu_source_cols || ARRAY['valid_from', 'valid_to'];

BEGIN

    -- 1. Legal unit with time_context for current year
    INSERT INTO public.import_definition (slug, name, note, time_context_ident, strategy, valid)
    VALUES ('legal_unit_current_year', 'Legal Unit - Current Year', 'Import legal units with validity period set to current year', 'r_year_curr', 'upsert', false) -- Start invalid
    RETURNING id INTO def_id;
    PERFORM admin.link_steps_to_definition(def_id, lu_steps || ARRAY['valid_time_from_context']);
    PERFORM admin.create_source_and_mappings_for_definition(def_id, lu_source_cols);

    -- 2. Legal unit with explicit valid_from/valid_to
    INSERT INTO public.import_definition (slug, name, note, strategy, valid)
    VALUES ('legal_unit_explicit_dates', 'Legal Unit - Explicit Dates', 'Import legal units with explicit valid_from and valid_to columns', 'upsert', false) -- Start invalid
    RETURNING id INTO def_id;
    PERFORM admin.link_steps_to_definition(def_id, lu_steps || ARRAY['valid_time_from_source']);
    PERFORM admin.create_source_and_mappings_for_definition(def_id, lu_explicit_source_cols);

    -- 3. Establishment for legal unit with time_context for current year
    INSERT INTO public.import_definition (slug, name, note, time_context_ident, strategy, valid)
    VALUES ('establishment_for_lu_current_year', 'Establishment for Legal Unit - Current Year', 'Import establishments linked to legal units with validity period set to current year', 'r_year_curr', 'upsert', false) -- Start invalid
    RETURNING id INTO def_id;
    PERFORM admin.link_steps_to_definition(def_id, es_steps || ARRAY['valid_time_from_context']);
    PERFORM admin.create_source_and_mappings_for_definition(def_id, es_source_cols);

    -- 4. Establishment for legal unit with explicit valid_from/valid_to
    INSERT INTO public.import_definition (slug, name, note, strategy, valid)
    VALUES ('establishment_for_lu_explicit_dates', 'Establishment for Legal Unit - Explicit Dates', 'Import establishments linked to legal units with explicit valid_from and valid_to columns', 'upsert', false) -- Start invalid
    RETURNING id INTO def_id;
    PERFORM admin.link_steps_to_definition(def_id, es_steps || ARRAY['valid_time_from_source']);
    PERFORM admin.create_source_and_mappings_for_definition(def_id, es_explicit_source_cols);

    -- 5. Establishment without legal unit with time_context for current year
    INSERT INTO public.import_definition (slug, name, note, time_context_ident, strategy, valid)
    VALUES ('establishment_without_lu_current_year', 'Establishment without Legal Unit - Current Year', 'Import standalone establishments with validity period set to current year', 'r_year_curr', 'upsert', false) -- Start invalid
    RETURNING id INTO def_id;
    PERFORM admin.link_steps_to_definition(def_id, es_no_lu_steps || ARRAY['valid_time_from_context']);
    PERFORM admin.create_source_and_mappings_for_definition(def_id, es_no_lu_source_cols);

    -- 6. Establishment without legal unit with explicit valid_from/valid_to
    INSERT INTO public.import_definition (slug, name, note, strategy, valid)
    VALUES ('establishment_without_lu_explicit_dates', 'Establishment without Legal Unit - Explicit Dates', 'Import standalone establishments with explicit valid_from and valid_to columns', 'upsert', false) -- Start invalid
    RETURNING id INTO def_id;
    PERFORM admin.link_steps_to_definition(def_id, es_no_lu_steps || ARRAY['valid_time_from_source']);
    PERFORM admin.create_source_and_mappings_for_definition(def_id, es_no_lu_explicit_source_cols);

    -- 7. Unit Stats Update with time_context for current year
    -- This definition finds existing units (LU or EST) via external idents and updates their stats.
    INSERT INTO public.import_definition (slug, name, note, time_context_ident, strategy, valid)
    VALUES ('unit_stats_update_current_year', 'Unit Stats Update - Current Year', 'Updates statistical variables for existing units, validity set to current year', 'r_year_curr', 'update_only', false) -- Start invalid
    RETURNING id INTO def_id;
    PERFORM admin.link_steps_to_definition(def_id, ARRAY['external_idents', 'valid_time_from_context', 'statistical_variables', 'edit_info', 'metadata']);
    -- Source columns are just external idents and stats (added dynamically)
    PERFORM admin.create_source_and_mappings_for_definition(def_id, ARRAY[]::TEXT[]);

    -- 8. Unit Stats Update with explicit valid_from/valid_to
    -- This definition finds existing units (LU or EST) via external idents and updates their stats using explicit dates.
    INSERT INTO public.import_definition (slug, name, note, strategy, valid)
    VALUES ('unit_stats_update_explicit_dates', 'Unit Stats Update - Explicit Dates', 'Updates statistical variables for existing units using explicit valid_from/valid_to', 'update_only', false) -- Start invalid
    RETURNING id INTO def_id;
    PERFORM admin.link_steps_to_definition(def_id, ARRAY['external_idents', 'valid_time_from_source', 'statistical_variables', 'edit_info', 'metadata']);
    -- Source columns are external idents, stats (dynamic), and valid_from/valid_to
    PERFORM admin.create_source_and_mappings_for_definition(def_id, ARRAY['valid_from', 'valid_to']);

END $$;

-- Set all newly created import definitions to valid AFTER callbacks have run
UPDATE public.import_definition
SET valid = true, validation_error = NULL
WHERE valid = false; -- Only update those created in this script


END;
