-- This test script generates a markdown summary of the database schema.
-- It is inspired by tests that generate other documentation files.
-- The output is directed to doc/data-model.md.

-- Turn off all decorative output for clean markdown
\t
\a

-- Create the docs directory if it doesn't exist
\! mkdir -p doc

-- Redirect output to the data model file
\o doc/data-model.md

CREATE OR REPLACE FUNCTION public.generate_data_model_summary(OUT markdown TEXT, OUT undocumented TEXT)
LANGUAGE plpgsql AS $generate_data_model_summary$
DECLARE
    v_markdown TEXT := '';
    v_section_record RECORD;
    v_entity_data JSONB;
    v_columns_str TEXT;
    v_fks_str TEXT;
    v_extras_str TEXT;
    v_is_temporal BOOLEAN;
    v_entity_type TEXT;
    v_documented_entities JSONB := '[]'::jsonb;
    v_undocumented_str TEXT;
    v_pattern_data JSONB;
    v_helper_patterns JSONB := '[
        {"pattern": "%_upload", "description": "Stores raw data from user file uploads for an import job. Transient."},
        {"pattern": "%_data", "description": "Intermediate data table for an import job, holding source data and analysis results. Transient."},
        {"pattern": "%_def", "description": "The definition of a view, often used as a building block for other views."},
        {"pattern": "%_used", "description": "Views showing distinct classification values currently in use."},
        {"pattern": "%_available", "description": "Views listing all available classification codes (system-defined + custom)."},
        {"pattern": "%_custom", "description": "Writable views for inserting new custom classification codes."},
        {"pattern": "%_system", "description": "Writable views for inserting new system-defined classification codes (typically used during initial setup)."},
        {"pattern": "%_ordered", "description": "Views providing a specific sort order for classifications, often for UI display."},
        {"pattern": "%_active", "description": "Views that filter for only the `enabled` records in a classification table."},
        {"pattern": "%__for_portion_of_valid", "description": "Helper view created by sql_saga for temporal REST updates (FOR PORTION OF)."},
        {"pattern": "%_custom_only", "description": "Helper view for listing and loading custom classification data, separating it from system-provided data."},
        {"pattern": "%_staging", "description": "Internal staging table for bulk inserts, merged into main table at end of batch processing."}
    ]'::jsonb;
    v_enum_record RECORD;
    v_enum_markdown TEXT;
    v_enums_str TEXT;

    -- Define sections and entities within them. This structure is hardcoded to match the desired output.
    c_sections CURSOR FOR
    SELECT * FROM (VALUES
        (1, 1, 1, 'Core Statistical Units (Hierarchy)', 'The system revolves around four main statistical units, often with temporal validity (`valid_from`, `valid_after`, `valid_to`):', jsonb_build_array(
            '{"schema": "public", "name": "enterprise_group", "short": "EG"}'::jsonb,
            '{"schema": "public", "name": "enterprise", "short": "EN"}'::jsonb,
            '{"schema": "public", "name": "legal_unit", "short": "LU"}'::jsonb,
            '{"schema": "public", "name": "establishment", "short": "EST"}'::jsonb
        )),
        (2, 1, 1, 'Common Links for Core Units (EG, EN, LU, EST)', 'These tables link to any of the four core statistical units:', jsonb_build_array(
            '{"schema": "public", "name": "external_ident"}'::jsonb,
            '{"schema": "public", "name": "image"}'::jsonb,
            '{"schema": "public", "name": "tag_for_unit"}'::jsonb,
            '{"schema": "public", "name": "unit_notes"}'::jsonb,
            '{"schema": "public", "name": "enterprise_external_idents", "type": "VIEW"}'::jsonb
        )),
        (3, 1, 1, 'Key Supporting Entities & Classifications', NULL, NULL),
        (3, 2, 1, 'Activity', NULL, jsonb_build_array(
            '{"schema": "public", "name": "activity"}'::jsonb,
            '{"schema": "public", "name": "activity_category"}'::jsonb,
            '{"schema": "public", "name": "activity_category_standard"}'::jsonb,
            '{"schema": "public", "name": "activity_category_isic_v4", "type": "VIEW"}'::jsonb,
            '{"schema": "public", "name": "activity_category_nace_v2_1", "type": "VIEW"}'::jsonb
        )),
        (3, 2, 2, 'Location & Contact', NULL, jsonb_build_array(
            '{"schema": "public", "name": "location"}'::jsonb,
            '{"schema": "public", "name": "contact"}'::jsonb,
            '{"schema": "public", "name": "region"}'::jsonb,
            '{"schema": "public", "name": "country"}'::jsonb,
            '{"schema": "public", "name": "country_view", "type": "VIEW"}'::jsonb
        )),
        (3, 2, 3, 'Persons', NULL, jsonb_build_array(
            '{"schema": "public", "name": "person"}'::jsonb,
            '{"schema": "public", "name": "person_for_unit"}'::jsonb,
            '{"schema": "public", "name": "person_role"}'::jsonb
        )),
        (3, 2, 4, 'Statistics', NULL, jsonb_build_array(
            '{"schema": "public", "name": "stat_for_unit"}'::jsonb,
            '{"schema": "public", "name": "stat_definition"}'::jsonb
        )),
        (3, 2, 5, 'General Code/Classification Tables', 'These tables typically store codes, names, and flags for `custom` and `enabled` status.', jsonb_build_array(
            '{"schema": "public", "name": "data_source"}'::jsonb,
            '{"schema": "public", "name": "enterprise_group_type"}'::jsonb,
            '{"schema": "public", "name": "enterprise_group_role"}'::jsonb,
            '{"schema": "public", "name": "external_ident_type"}'::jsonb,

            '{"schema": "public", "name": "foreign_participation"}'::jsonb,
            '{"schema": "public", "name": "legal_form"}'::jsonb,
            '{"schema": "public", "name": "reorg_type"}'::jsonb,
            '{"schema": "public", "name": "sector"}'::jsonb,
            '{"schema": "public", "name": "status"}'::jsonb,
            '{"schema": "public", "name": "tag"}'::jsonb,
            '{"schema": "public", "name": "unit_size"}'::jsonb
        )),
        (3, 2, 6, 'Enum Definitions', 'Enumerated types used across the schema, with their possible values.', NULL),
        (4, 1, 1, 'Temporal Data & History', NULL, NULL),
        (4, 2, 1, 'Derivations to create statistical_unit for a complete picture of every EN,LU,ES for every atomic segment. (/search)', NULL, jsonb_build_array(
            '{"schema": "public", "name": "timepoints"}'::jsonb,
            '{"schema": "public", "name": "timesegments"}'::jsonb,
            '{"schema": "public", "name": "timeline_establishment", "suffix": ", `timeline_legal_unit`, `timeline_enterprise`"}'::jsonb,
            '{"schema": "public", "name": "statistical_unit", "type": "VIEW"}'::jsonb
        )),
        (4, 2, 2, 'Derivations for UI listing of relevant time periods', NULL, jsonb_build_array(
            '{"schema": "public", "name": "timesegments_years"}'::jsonb,
            '{"schema": "public", "name": "relative_period"}'::jsonb,
            '{"schema": "public", "name": "relative_period_with_time", "type": "VIEW"}'::jsonb,
            '{"schema": "public", "name": "time_context"}'::jsonb
        )),
        (4, 2, 3, 'Derivations for drilling on facets of statistical_unit (/reports)', NULL, jsonb_build_array(
            '{"schema": "public", "name": "statistical_unit_facet"}'::jsonb,
            '{"schema": "public", "name": "statistical_unit_facet_dirty_partitions"}'::jsonb
        )),
        (4, 2, 4, 'Derivations to create statistical_history for reporting and statistical_history_facet for drilldown.', NULL, jsonb_build_array(
            '{"schema": "public", "name": "statistical_history"}'::jsonb,
            '{"schema": "public", "name": "statistical_history_facet"}'::jsonb
        )),
        (5, 1, 1, 'Import System', 'Handles the ingestion of data from external files.', jsonb_build_array(
            '{"schema": "public", "name": "import_definition"}'::jsonb,
            '{"schema": "public", "name": "import_step"}'::jsonb,
            '{"schema": "public", "name": "import_definition_step"}'::jsonb,
            '{"schema": "public", "name": "import_source_column"}'::jsonb,
            '{"schema": "public", "name": "import_data_column"}'::jsonb,
            '{"schema": "public", "name": "import_mapping"}'::jsonb,
            '{"schema": "public", "name": "import_job"}'::jsonb
        )),
        (6, 1, 1, 'Worker System', 'Handles background processing. A long-running worker process calls `worker.process_tasks()` to process tasks synchronously.', jsonb_build_array(
            '{"schema": "worker", "name": "tasks"}'::jsonb,
            '{"schema": "worker", "name": "command_registry"}'::jsonb,
            '{"schema": "worker", "name": "queue_registry"}'::jsonb,
            '{"schema": "worker", "name": "base_change_log"}'::jsonb,
            '{"schema": "worker", "name": "base_change_log_has_pending"}'::jsonb
        )),
        (7, 1, 1, 'Auth & System Tables/Views', NULL, jsonb_build_array(
            '{"schema": "auth", "name": "user"}'::jsonb,
            '{"schema": "public", "name": "user", "type": "VIEW"}'::jsonb,
            '{"schema": "auth", "name": "api_key"}'::jsonb,
            '{"schema": "public", "name": "api_key", "type": "VIEW"}'::jsonb,
            '{"schema": "auth", "name": "refresh_session"}'::jsonb,
            '{"schema": "auth", "name": "secrets"}'::jsonb,
            '{"schema": "public", "name": "settings"}'::jsonb,
            '{"schema": "public", "name": "region_access"}'::jsonb,
            '{"schema": "public", "name": "activity_category_access"}'::jsonb,
            '{"schema": "db", "name": "migration"}'::jsonb,
            '{"schema": "lifecycle_callbacks", "name": "registered_callback", "suffix": " and `supported_table`"}'::jsonb
        )),
        (8, 1, 1, 'Helper Views & Common Patterns', E'The schema includes numerous helper views, often for UI dropdowns or specific data access patterns. They follow consistent naming conventions:', NULL)
    ) AS t(group_order, level, ordering, title, description, entities) ORDER BY group_order, level, ordering;

BEGIN
    v_markdown := '# StatBus Data Model Summary

This document is automatically generated from the database schema by `test/sql/015_generate_data_model_doc.sql`. Do not edit it manually.

This document provides a compact overview of the StatBus database schema, focusing on entities, relationships, and key patterns.
';

    OPEN c_sections;
    LOOP
        FETCH c_sections INTO v_section_record;
        EXIT WHEN NOT FOUND;

        v_markdown := v_markdown || E'\n\n' || repeat('#', v_section_record.level + 1) || ' ' || v_section_record.title || E'\n';
        IF v_section_record.description IS NOT NULL THEN
            v_markdown := v_markdown || v_section_record.description || E'\n';
        END IF;

        IF v_section_record.title = 'Helper Views & Common Patterns' THEN
            v_markdown := v_markdown || E'\n';
            FOR v_pattern_data IN SELECT * FROM jsonb_array_elements(v_helper_patterns)
            LOOP
                v_markdown := v_markdown || format('- `*%s*`: %s' || E'\n', regexp_replace(v_pattern_data->>'pattern', '%', '', 'g'), v_pattern_data->>'description');
            END LOOP;
        END IF;

        IF v_section_record.title = 'Enum Definitions' THEN
            v_enum_markdown := E'\n';
            FOR v_enum_record IN
                SELECT
                    t.typname AS enum_name,
                    n.nspname AS enum_schema,
                    string_agg(format('`%s`', e.enumlabel), ', ' ORDER BY e.enumsortorder) AS enum_values
                FROM pg_type t
                JOIN pg_enum e ON t.oid = e.enumtypid
                JOIN pg_namespace n ON n.oid = t.typnamespace
                WHERE t.typtype = 'e' AND n.nspname IN ('public', 'worker', 'auth', 'db', 'lifecycle_callbacks')
                GROUP BY n.nspname, t.typname
                ORDER BY n.nspname, t.typname
            LOOP
                v_enum_markdown := v_enum_markdown || format(E'- **`%s.%s`**: %s\n', v_enum_record.enum_schema, v_enum_record.enum_name, v_enum_record.enum_values);
            END LOOP;
            v_markdown := v_markdown || v_enum_markdown;
        END IF;

        IF v_section_record.entities IS NULL THEN
            CONTINUE;
        END IF;

        FOR v_entity_data IN SELECT * FROM jsonb_array_elements(v_section_record.entities)
        LOOP
            v_documented_entities := v_documented_entities || jsonb_build_object(
                'schema', v_entity_data->>'schema',
                'name', v_entity_data->>'name'
            );
            IF v_entity_data->>'suffix' ILIKE '%`timeline_legal_unit`%' THEN
                v_documented_entities := v_documented_entities || '{"schema": "public", "name": "timeline_legal_unit"}'::jsonb;
                v_documented_entities := v_documented_entities || '{"schema": "public", "name": "timeline_enterprise"}'::jsonb;
            END IF;
            IF v_entity_data->>'suffix' ILIKE '%`supported_table`%' THEN
                v_documented_entities := v_documented_entities || '{"schema": "lifecycle_callbacks", "name": "supported_table"}'::jsonb;
            END IF;

            v_entity_type = COALESCE(v_entity_data->>'type', 'BASE TABLE');

            -- Get all columns, prioritized for readability
            SELECT
                string_agg(column_name, ', ' ORDER BY priority, ordinal_position)
            INTO v_columns_str
            FROM (
                SELECT
                    column_name,
                    ordinal_position,
                    CASE
                        WHEN column_name = 'id' THEN 1
                        WHEN column_name ~ '(name|code|path|ident|slug|title|notes|command|value|label|sub|email|type)' THEN 2
                        WHEN column_name LIKE '%\_id' THEN 3
                        WHEN column_name LIKE 'valid\_%' OR column_name LIKE '%\_at' OR column_name LIKE '%\_on' THEN 4
                        WHEN column_name = 'enabled' THEN 5
                        ELSE 6
                    END as priority
                FROM information_schema.columns
                WHERE table_schema = v_entity_data->>'schema'
                  AND table_name = v_entity_data->>'name'
            ) sub;

            v_extras_str := '';
            IF v_entity_data ? 'short' THEN
                v_extras_str := v_extras_str || ' (' || (v_entity_data->>'short') || ')';
            END IF;

            SELECT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema = v_entity_data->>'schema'
                  AND table_name = v_entity_data->>'name'
                  AND v_entity_data->>'name' NOT IN ('relative_period_with_time', 'time_context')
                  AND (column_name IN ('valid_from', 'valid_after') OR table_name LIKE 'timeline_%')
            ) INTO v_is_temporal;

            IF v_is_temporal THEN
                v_extras_str := v_extras_str || ' (temporal)';
            END IF;

            v_markdown := v_markdown || format(E'\n- `%s(%s)`%s',
                v_entity_data->>'name' || COALESCE(v_entity_data->>'suffix',''),
                v_columns_str,
                v_extras_str
            );

            -- Get FKs for tables only
            IF v_entity_type = 'BASE TABLE' THEN
                SELECT string_agg(kcu.column_name, ', ' ORDER BY kcu.column_name)
                INTO v_fks_str
                FROM
                    information_schema.table_constraints AS tc
                    JOIN information_schema.key_column_usage AS kcu
                      ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
                WHERE tc.constraint_type = 'FOREIGN KEY'
                  AND tc.table_schema = v_entity_data->>'schema'
                  AND tc.table_name = v_entity_data->>'name';

                IF v_fks_str IS NOT NULL THEN
                    v_markdown := v_markdown || format(E'\n  - Key FKs: %s.', v_fks_str);
                END IF;
            END IF;

            WITH enums AS (
                SELECT t.typname, n.nspname
                FROM pg_type t
                JOIN pg_namespace n ON n.oid = t.typnamespace
                WHERE t.typtype = 'e'
            )
            SELECT string_agg(format('`%s` (`%s.%s`)', c.column_name, c.udt_schema, c.udt_name), ', ' ORDER BY c.column_name)
            INTO v_enums_str
            FROM information_schema.columns c
            JOIN enums ON c.udt_name = enums.typname AND c.udt_schema = enums.nspname
            WHERE c.table_schema = v_entity_data->>'schema'
              AND c.table_name = v_entity_data->>'name';

            IF v_enums_str IS NOT NULL THEN
                v_markdown := v_markdown || format(E'\n  - Enums: %s.', v_enums_str);
            END IF;
        END LOOP;
    END LOOP;
    CLOSE c_sections;

    v_markdown := v_markdown || E'\n\n## Naming Conventions (from `CONVENTIONS.md`)
- `x_id`: Foreign key to table `x`.
- `x_ident`: External identifier (not originating from this database).
- `x_at`: Timestamp with time zone (TIMESTAMPTZ).
- `x_on`: Date (DATE).
';

    -- Check for undocumented entities
    WITH all_entities AS (
        SELECT table_schema, table_name, 'TABLE' as type FROM information_schema.tables
        WHERE table_schema IN ('public', 'worker', 'auth', 'db', 'lifecycle_callbacks')
        UNION ALL
        SELECT table_schema, table_name, 'VIEW' as type FROM information_schema.views
        WHERE table_schema IN ('public', 'worker', 'auth', 'db', 'lifecycle_callbacks')
    ),
    documented AS (
        SELECT value->>'schema' as table_schema, value->>'name' as table_name
        FROM jsonb_array_elements(v_documented_entities)
    ),
    patterns AS (
        SELECT value->>'pattern' as pattern
        FROM jsonb_array_elements(v_helper_patterns)
    )
    SELECT string_agg(format('- `%s.%s` (%s)', table_schema, table_name, type), E'\n' ORDER BY table_schema, table_name)
    INTO v_undocumented_str
    FROM all_entities ae
    WHERE NOT EXISTS (
        SELECT 1 FROM documented d
        WHERE d.table_schema = ae.table_schema AND d.table_name = ae.table_name
    )
    AND NOT EXISTS (
        SELECT 1 FROM patterns p WHERE ae.table_name LIKE p.pattern
    )
    -- Exclude postgres extension tables
    AND ae.table_name NOT LIKE 'hypopg_%'
    AND ae.table_name NOT LIKE 'pg_stat_%';

    IF v_undocumented_str IS NOT NULL THEN
        undocumented := E'## Undocumented Entities\nThe following tables/views were found in the schema but are not yet documented. Please add them to a section or a helper pattern in `test/sql/015_generate_data_model_doc.sql`.\n\n' || v_undocumented_str;
    ELSE
        undocumented := 'OK: All entities documented or covered by a helper pattern.';
    END IF;

    markdown := v_markdown;
END;
$generate_data_model_summary$;

-- Generate the documentation and capture the output
SELECT * FROM public.generate_data_model_summary() \gset

-- Write the main doc file to doc/data-model.md
\o doc/data-model.md
SELECT :'markdown';
\o

-- Clean up the function
DROP FUNCTION public.generate_data_model_summary();

-- Turn decorative output back on for the test result
\t
\a

-- A simple select to confirm the script ran
SELECT 'Data model documentation generated in doc/data-model.md' AS result;

-- Output the undocumented list as the test result
SELECT :'undocumented';
