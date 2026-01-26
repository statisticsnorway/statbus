-- Tmp script to generate database.types.ts from SQL
--
-- Plan:
-- 1. [DONE] Generate Enums
-- 2. [DONE] Generate Tables (Row)
-- 3. [DONE] Generate Tables (Insert, Update)
-- 4. [DONE] Generate Relationships

CREATE OR REPLACE FUNCTION public.generate_typescript_types()
RETURNS text LANGUAGE plpgsql AS $generate_typescript_types$
DECLARE
    v_output text := '';
    v_constants_output text;
    v_enums_output text;
    v_tables_output text;
    v_views_output text;
    v_functions_output text;
    v_composite_types_output text;
    v_schemas text[] := ARRAY['public']; -- Schemas to include
    v_schema_name text;
BEGIN
    -- Static header for the file
    v_output := v_output || 'export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
';

    -- Loop through schemas
    FOREACH v_schema_name IN ARRAY v_schemas
    LOOP
        v_output := v_output || format('  %I: {
', v_schema_name);

        -- Generate Enums
        WITH enum_definitions AS (
            SELECT
                t.typname AS enum_type_name,
                string_agg('"' || e.enumlabel || '"', ' | ' ORDER BY e.enumsortorder) AS single_line_values,
                array_agg('"' || e.enumlabel || '"' ORDER BY e.enumsortorder) AS multi_line_values_array
            FROM pg_type t
            JOIN pg_namespace n ON n.oid = t.typnamespace
            JOIN pg_enum e ON t.oid = e.enumtypid
            WHERE n.nspname = v_schema_name
              AND t.typtype = 'e'
            GROUP BY t.typname
        ),
        formatted_enum_definitions AS (
            SELECT
                enum_type_name,
                CASE
                    WHEN length(single_line_definition) > 80 THEN multi_line_definition
                    ELSE single_line_definition
                END AS enum_ts
            FROM (
                SELECT
                    enum_type_name,
                    '      ' || enum_type_name || ': ' || single_line_values as single_line_definition,
                    '      ' || enum_type_name || ': ' || E'\n          | ' || array_to_string(multi_line_values_array, E'\n          | ') as multi_line_definition
                FROM enum_definitions
            ) AS definitions
        )
        SELECT
            '    Enums: {' || E'\n' ||
            COALESCE(string_agg(
                enum_ts,
                E',\n' ORDER BY enum_type_name
            ), '') || E'\n' ||
            '    }'
        INTO v_enums_output
        FROM formatted_enum_definitions;

        -- Generate Tables, Views, Functions, Composite Types
        WITH fk_constraints AS (
            -- FKs from tables in public schema
            SELECT
                con.conrelid,
                con.conname,
                con.conkey, -- FK column numbers for isOneToOne check
                (SELECT string_agg(a.attname, '", "') FROM pg_attribute AS a WHERE a.attrelid = con.conrelid AND a.attnum = ANY(con.conkey)) AS columns,
                con.confrelid,
                (SELECT string_agg(a.attname, '", "') FROM pg_attribute AS a WHERE a.attrelid = con.confrelid AND a.attnum = ANY(con.confkey)) AS referenced_columns,
                referenced_class.relname as referenced_relation_name,
                referenced_class.relkind as referenced_relation_kind,
                referenced_ns.nspname as referenced_schema_name,
                constrained_ns.nspname as constrained_schema_name
            FROM pg_constraint AS con
            JOIN pg_class AS constrained_class ON con.conrelid = constrained_class.oid
            JOIN pg_namespace AS constrained_ns ON constrained_class.relnamespace = constrained_ns.oid
            JOIN pg_class AS referenced_class ON con.confrelid = referenced_class.oid
            JOIN pg_namespace AS referenced_ns ON referenced_class.relnamespace = referenced_ns.oid
            WHERE constrained_ns.nspname = v_schema_name
              AND con.contype = 'f'
              AND referenced_class.relkind IN ('r', 'p') -- Only FKs to tables
        ),
        -- FKs from auth tables that have views in public schema
        auth_fk_constraints AS (
            SELECT
                con.conrelid,
                con.conname,
                con.conkey,
                (SELECT string_agg(a.attname, '", "') FROM pg_attribute AS a WHERE a.attrelid = con.conrelid AND a.attnum = ANY(con.conkey)) AS columns,
                con.confrelid,
                (SELECT string_agg(a.attname, '", "') FROM pg_attribute AS a WHERE a.attrelid = con.confrelid AND a.attnum = ANY(con.confkey)) AS referenced_columns,
                -- Remap auth.user -> public.user
                CASE 
                    WHEN referenced_ns.nspname = 'auth' AND referenced_class.relname = 'user'
                         AND EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid 
                                     WHERE n.nspname = v_schema_name AND c.relname = 'user' AND c.relkind = 'v')
                    THEN 'user'::name
                    ELSE referenced_class.relname
                END as referenced_relation_name,
                CASE 
                    WHEN referenced_ns.nspname = 'auth' AND referenced_class.relname = 'user'
                    THEN 'v'::"char"
                    ELSE referenced_class.relkind
                END as referenced_relation_kind,
                referenced_ns.nspname as referenced_schema_name,
                constrained_class.relname as constrained_relation_name
            FROM pg_constraint AS con
            JOIN pg_class AS constrained_class ON con.conrelid = constrained_class.oid
            JOIN pg_namespace AS constrained_ns ON constrained_class.relnamespace = constrained_ns.oid
            JOIN pg_class AS referenced_class ON con.confrelid = referenced_class.oid
            JOIN pg_namespace AS referenced_ns ON referenced_class.relnamespace = referenced_ns.oid
            WHERE constrained_ns.nspname = 'auth'
              AND con.contype = 'f'
              AND referenced_class.relkind IN ('r', 'p')
              -- Only include if there's a corresponding view in public schema
              AND EXISTS (
                  SELECT 1 FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
                  WHERE n.nspname = v_schema_name AND c.relname = constrained_class.relname AND c.relkind = 'v'
              )
        ),
        -- Find views that transitively depend on FK target tables and expose their id column
        -- This enables queries like .select('*, data_source_available(*)') in addition to .select('*, data_source(*)')
        view_aliases AS (
            WITH RECURSIVE view_deps AS (
                -- Base: direct view dependencies on tables in public schema
                SELECT 
                    t.oid as base_table_oid,
                    t.relname as base_table_name,
                    v.oid as view_oid,
                    v.relname as view_name,
                    1 as depth
                FROM pg_class t 
                JOIN pg_namespace tn ON t.relnamespace = tn.oid
                JOIN pg_rewrite r ON TRUE
                JOIN pg_class v ON r.ev_class = v.oid AND v.relkind = 'v'
                JOIN pg_namespace vn ON v.relnamespace = vn.oid
                JOIN pg_depend d ON d.objid = r.oid AND d.refobjid = t.oid
                WHERE tn.nspname = v_schema_name 
                  AND vn.nspname = v_schema_name
                  AND t.relkind IN ('r', 'p')  -- base tables only
                  AND d.refclassid = 'pg_class'::regclass 
                  AND d.deptype = 'n'
                UNION
                -- Recursive: views that depend on views that depend on the base table
                SELECT 
                    vd.base_table_oid,
                    vd.base_table_name,
                    v.oid,
                    v.relname,
                    vd.depth + 1
                FROM view_deps vd
                JOIN pg_rewrite r ON TRUE
                JOIN pg_class v ON r.ev_class = v.oid AND v.relkind = 'v'
                JOIN pg_namespace vn ON v.relnamespace = vn.oid
                JOIN pg_depend d ON d.objid = r.oid AND d.refobjid = vd.view_oid
                WHERE vn.nspname = v_schema_name
                  AND d.refclassid = 'pg_class'::regclass 
                  AND d.deptype = 'n'
                  AND vd.depth < 5  -- limit recursion
            )
            SELECT DISTINCT 
                base_table_oid,
                base_table_name,
                view_oid,
                view_name,
                -- Determine which column in the view corresponds to the base table's id
                -- Either 'id' directly, or '{table_name}_id' (e.g., 'enterprise_id' for enterprise)
                CASE 
                    WHEN EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = view_oid AND attname = 'id' AND NOT attisdropped)
                    THEN 'id'
                    WHEN EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = view_oid AND attname = base_table_name || '_id' AND NOT attisdropped)
                    THEN base_table_name || '_id'
                    ELSE NULL
                END as view_id_column
            FROM view_deps
            -- Only include views that have either 'id' or '{table_name}_id' column
            WHERE EXISTS (
                SELECT 1 FROM pg_attribute 
                WHERE attrelid = view_oid AND attname = 'id' AND NOT attisdropped
            )
            OR EXISTS (
                SELECT 1 FROM pg_attribute 
                WHERE attrelid = view_oid AND attname = base_table_name || '_id' AND NOT attisdropped
            )
        ),
        -- sql_saga regular_to_temporal FKs (not in pg_constraint, only in sql_saga.foreign_keys)
        sql_saga_regular_to_temporal AS (
            SELECT 
                src_class.oid as conrelid,
                sfk.foreign_key_name as conname,
                -- Get column numbers for the FK columns
                (SELECT array_agg(a.attnum ORDER BY ord)
                 FROM unnest(sfk.column_names) WITH ORDINALITY AS cols(col_name, ord)
                 JOIN pg_attribute a ON a.attrelid = src_class.oid AND a.attname = cols.col_name
                ) as conkey,
                (SELECT string_agg(col_name, '", "' ORDER BY ord) 
                 FROM unnest(sfk.column_names) WITH ORDINALITY AS cols(col_name, ord)
                ) as columns,
                -- Get referenced columns from the unique key
                (SELECT string_agg(col_name, '", "' ORDER BY ord)
                 FROM unnest(suk.column_names) WITH ORDINALITY AS cols(col_name, ord)
                ) as referenced_columns,
                suk.table_name as referenced_relation_name,
                tgt_class.relkind as referenced_relation_kind
            FROM sql_saga.foreign_keys sfk
            JOIN sql_saga.unique_keys suk ON suk.unique_key_name = sfk.unique_key_name
            JOIN pg_class src_class ON src_class.relname = sfk.table_name
            JOIN pg_namespace src_ns ON src_class.relnamespace = src_ns.oid AND src_ns.nspname = sfk.table_schema
            JOIN pg_class tgt_class ON tgt_class.relname = suk.table_name
            JOIN pg_namespace tgt_ns ON tgt_class.relnamespace = tgt_ns.oid AND tgt_ns.nspname = suk.table_schema
            WHERE sfk.type = 'regular_to_temporal'
              AND sfk.table_schema = v_schema_name
              AND suk.table_schema = v_schema_name
        ),
        all_relations AS (
            -- Only explicit FK constraints (computed relationships are handled via SetofOptions)
            -- Include FKs within same schema
            SELECT conrelid, conname, conkey, columns, referenced_columns, referenced_relation_name, referenced_relation_kind
            FROM fk_constraints
            WHERE referenced_schema_name = v_schema_name
            UNION ALL
            -- sql_saga regular_to_temporal FKs (non-native temporal references)
            SELECT conrelid, conname, conkey, columns, referenced_columns, referenced_relation_name, referenced_relation_kind
            FROM sql_saga_regular_to_temporal
            UNION ALL
            -- Remap FKs to auth.user -> public.user (if the view exists)
            SELECT conrelid, conname, conkey, columns, referenced_columns,
                   'user'::name as referenced_relation_name,
                   'v'::"char" as referenced_relation_kind  -- It's a view
            FROM fk_constraints
            WHERE referenced_schema_name = 'auth'
              AND referenced_relation_name = 'user'
              AND EXISTS (
                  SELECT 1 FROM pg_class c
                  JOIN pg_namespace n ON c.relnamespace = n.oid
                  WHERE n.nspname = v_schema_name AND c.relname = 'user' AND c.relkind = 'v'
              )
            UNION ALL
            -- View aliases: for each FK to a table, also create relationships to views that expose the same id
            SELECT 
                fk.conrelid, 
                fk.conname, 
                fk.conkey, 
                fk.columns, 
                va.view_id_column as referenced_columns,  -- Use the view's column (id or {table}_id)
                va.view_name as referenced_relation_name,
                'v'::"char" as referenced_relation_kind
            FROM fk_constraints fk
            JOIN view_aliases va ON va.base_table_name = fk.referenced_relation_name
            WHERE fk.referenced_schema_name = v_schema_name
              AND va.view_id_column IS NOT NULL  -- Must have a matching id column
        ),
        formatted_relations AS (
            SELECT
                ar.conrelid,
                ar.conname,  -- Add constraint name for deterministic ordering
                ar.columns,  -- Keep columns for view inheritance check
                format(
                    E'          {\n' ||
                    E'            foreignKeyName: "%s"\n' ||
                    E'            columns: ["%s"]\n' ||
                    E'            isOneToOne: %s\n' ||
                    E'            referencedRelation: "%s"\n' ||
                    E'            referencedColumns: ["%s"]\n' ||
                    E'          }',
                    ar.conname,
                    ar.columns,
                    -- isOneToOne is true if the FK columns have a unique or primary key constraint
                    CASE WHEN EXISTS (
                        SELECT 1 FROM pg_constraint uc 
                        WHERE uc.conrelid = ar.conrelid 
                          AND uc.contype IN ('u', 'p')
                          AND uc.conkey = ar.conkey
                    ) THEN 'true' ELSE 'false' END,
                    ar.referenced_relation_name,
                    ar.referenced_columns
                ) as formatted_ts,
                ar.referenced_relation_name,
                ar.referenced_relation_kind
            FROM all_relations ar
        ),
        table_relationships AS (
            SELECT
                conrelid,
                '        Relationships: [' || E'\n' ||
                string_agg(
                    formatted_ts,
                    E',\n'
                    ORDER BY
                        CASE WHEN referenced_relation_kind IN ('r', 'p') THEN 1 ELSE 2 END,
                        referenced_relation_name,
                        conname  -- Add constraint name as tie-breaker for deterministic ordering
                ) || E'\n' ||
                '        ]'
                 AS relationships_ts
            FROM formatted_relations
            GROUP BY conrelid
        ),
        -- Format auth FKs for views over auth tables
        formatted_auth_relations AS (
            SELECT
                ar.conrelid,
                ar.conname,  -- Add constraint name for deterministic ordering
                ar.constrained_relation_name,
                format(
                    E'          {\n' ||
                    E'            foreignKeyName: "%s"\n' ||
                    E'            columns: ["%s"]\n' ||
                    E'            isOneToOne: %s\n' ||
                    E'            referencedRelation: "%s"\n' ||
                    E'            referencedColumns: ["%s"]\n' ||
                    E'          }',
                    ar.conname,
                    ar.columns,
                    CASE WHEN EXISTS (
                        SELECT 1 FROM pg_constraint uc 
                        WHERE uc.conrelid = ar.conrelid 
                          AND uc.contype IN ('u', 'p')
                          AND uc.conkey = ar.conkey
                    ) THEN 'true' ELSE 'false' END,
                    ar.referenced_relation_name,
                    ar.referenced_columns
                ) as formatted_ts,
                ar.referenced_relation_name,
                ar.referenced_relation_kind
            FROM auth_fk_constraints ar
            -- Only include if target is in public schema or remapped to public
            WHERE ar.referenced_schema_name = v_schema_name 
               OR (ar.referenced_schema_name = 'auth' AND ar.referenced_relation_name = 'user')
        ),
        -- Views inherit relationships from their base tables ONLY if they have all the FK columns
        view_base_relations AS (
            -- From public schema tables
            SELECT DISTINCT
                v.oid as view_oid,
                fr.conname,  -- Add constraint name for deterministic ordering
                fr.formatted_ts,
                fr.referenced_relation_name,
                fr.referenced_relation_kind
            FROM pg_class v
            JOIN pg_rewrite r ON r.ev_class = v.oid
            JOIN pg_depend d ON d.objid = r.oid
            JOIN formatted_relations fr ON fr.conrelid = d.refobjid
            WHERE v.relkind IN ('v', 'm') -- views and materialized views
              AND v.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = v_schema_name)
              AND d.refclassid = 'pg_class'::regclass
              AND d.deptype = 'n' -- normal dependency
              -- Only inherit FK if view has ALL the FK columns
              AND NOT EXISTS (
                  SELECT 1 
                  FROM unnest(string_to_array(fr.columns, '", "')) AS col_name
                  WHERE NOT EXISTS (
                      SELECT 1 FROM pg_attribute a 
                      WHERE a.attrelid = v.oid 
                        AND a.attname = col_name 
                        AND NOT a.attisdropped
                  )
              )
            UNION
            -- From auth tables that have public views
            SELECT DISTINCT
                v.oid as view_oid,
                far.conname,  -- Add constraint name for deterministic ordering
                far.formatted_ts,
                far.referenced_relation_name,
                far.referenced_relation_kind
            FROM pg_class v
            JOIN pg_namespace vn ON v.relnamespace = vn.oid
            JOIN formatted_auth_relations far ON far.constrained_relation_name = v.relname
            WHERE v.relkind = 'v'
              AND vn.nspname = v_schema_name
        ),
        view_relationships AS (
            SELECT
                view_oid as conrelid,
                '        Relationships: [' || E'\n' ||
                string_agg(
                    formatted_ts,
                    E',\n'
                    ORDER BY
                        CASE WHEN referenced_relation_kind IN ('r', 'p') THEN 1 ELSE 2 END,
                        referenced_relation_name,
                        conname  -- Add constraint name as tie-breaker for deterministic ordering
                ) || E'\n' ||
                '        ]'
                 AS relationships_ts
            FROM view_base_relations
            GROUP BY view_oid
        ),
        all_relationships AS (
            -- Tables get relationships from table_relationships (explicit FKs + inferred)
            SELECT tr.conrelid, tr.relationships_ts 
            FROM table_relationships tr
            JOIN pg_class c ON c.oid = tr.conrelid
            WHERE c.relkind IN ('r', 'p') -- only actual tables
            UNION ALL
            -- Views get relationships from view_relationships (inherited from base tables)
            SELECT conrelid, relationships_ts FROM view_relationships
        ),
        columns AS (
            SELECT
                c.oid as table_oid,
                c.relname AS table_name,
                c.relkind,
                a.attname AS column_name,
                a.attnum,
                (isc.is_nullable = 'NO') AS attnotnull,
                (isc.column_default IS NOT NULL) AS atthasdef,
                a.attidentity, -- 'a' for ALWAYS, 'd' for BY DEFAULT, '' for normal
                -- Logic to determine TS type
                CASE
                    -- Enums
                    WHEN t.typtype = 'e' THEN format('Database["%s"]["Enums"]["%s"]', n.nspname, t.typname)
                    -- Composite types
                    WHEN t.typtype = 'c' THEN format('Database["%s"]["CompositeTypes"]["%s"]', n.nspname, t.typname)
                    -- Arrays
                    WHEN t.typcategory = 'A' THEN
                        -- Array of enums
                        CASE WHEN t_element.typtype = 'e' THEN format('Database["%s"]["Enums"]["%s"][]', n.nspname, t_element.typname)
                        -- Array of composite types
                        WHEN t_element.typtype = 'c' THEN format('Database["%s"]["CompositeTypes"]["%s"][]', n.nspname, t_element.typname)
                        -- Other arrays
                        ELSE
                            CASE t_element.typname
                                WHEN 'bool' THEN 'boolean[]'
                                WHEN 'int2' THEN 'number[]'
                                WHEN 'int4' THEN 'number[]'
                                WHEN 'int8' THEN 'number[]'
                                WHEN 'float4' THEN 'number[]'
                                WHEN 'float8' THEN 'number[]'
                                WHEN 'numeric' THEN 'number[]'
                                WHEN 'text' THEN 'string[]'
                                WHEN 'varchar' THEN 'string[]'
                                WHEN 'char' THEN 'string[]'
                                WHEN 'uuid' THEN 'string[]'
                                WHEN 'date' THEN 'string[]'
                                WHEN 'timestamp' THEN 'string[]'
                                WHEN 'timestamptz' THEN 'string[]'
                                WHEN 'json' THEN 'Json[]'
                                WHEN 'jsonb' THEN 'Json[]'
                                WHEN 'ltree' THEN 'string[]'
                                WHEN 'daterange' THEN 'string[]'
                                WHEN 'tsrange' THEN 'string[]'
                                WHEN 'tstzrange' THEN 'string[]'
                                WHEN 'int4range' THEN 'string[]'
                                WHEN 'int8range' THEN 'string[]'
                                WHEN 'numrange' THEN 'string[]'
                                WHEN 'tsvector' THEN 'string[]'
                                WHEN 'name' THEN 'string[]'
                                WHEN 'oid' THEN 'number[]'
                                WHEN 'regproc' THEN 'string[]'
                                WHEN 'interval' THEN 'string[]'
                                WHEN 'bytea' THEN 'string[]'
                                WHEN 'inet' THEN 'string[]'
                                WHEN 'cidr' THEN 'string[]'
                                WHEN 'macaddr' THEN 'string[]'
                                ELSE 'unknown[]'
                            END
                        END
                    -- Base types
                    ELSE
                        CASE t.typname
                            WHEN 'bool' THEN 'boolean'
                            WHEN 'int2' THEN 'number'
                            WHEN 'int4' THEN 'number'
                            WHEN 'int8' THEN 'number'
                            WHEN 'float4' THEN 'number'
                            WHEN 'float8' THEN 'number'
                            WHEN 'numeric' THEN 'number'
                            WHEN 'text' THEN 'string'
                            WHEN 'varchar' THEN 'string'
                            WHEN 'char' THEN 'string'
                            WHEN 'uuid' THEN 'string'
                            WHEN 'date' THEN 'string'
                            WHEN 'timestamp' THEN 'string'
                            WHEN 'timestamptz' THEN 'string'
                            WHEN 'json' THEN 'Json'
                            WHEN 'jsonb' THEN 'Json'
                            WHEN 'ltree' THEN 'string'
                            WHEN 'daterange' THEN 'string'
                            WHEN 'tsrange' THEN 'string'
                            WHEN 'tstzrange' THEN 'string'
                            WHEN 'int4range' THEN 'string'
                            WHEN 'int8range' THEN 'string'
                            WHEN 'numrange' THEN 'string'
                            WHEN 'tsvector' THEN 'string'
                            WHEN 'name' THEN 'string'
                            WHEN 'oid' THEN 'number'
                            WHEN 'regproc' THEN 'string'
                            WHEN 'interval' THEN 'string'
                            WHEN 'bytea' THEN 'string'
                            WHEN 'inet' THEN 'string'
                            WHEN 'cidr' THEN 'string'
                            WHEN 'macaddr' THEN 'string'
                            ELSE 'unknown'
                        END
                END AS base_ts_type
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            JOIN pg_attribute a ON a.attrelid = c.oid
            JOIN pg_type t ON t.oid = a.atttypid
            LEFT JOIN pg_type t_element ON t_element.oid = t.typelem
            JOIN information_schema.columns isc ON isc.table_schema = n.nspname
                AND isc.table_name = c.relname
                AND isc.column_name = a.attname
            WHERE n.nspname = v_schema_name
              AND c.relname NOT LIKE 'pg_%'
              AND c.relkind IN ('r', 'v', 'm', 'p') -- regular table, view, materialized view, partitioned table
              AND a.attnum > 0 -- user columns
              AND NOT a.attisdropped
        ),
        tables AS (
            SELECT
                c.relkind,
                table_name,
                string_agg('          ' || column_name || ': ' || base_ts_type || (CASE WHEN NOT attnotnull THEN ' | null' ELSE '' END), E'\n' ORDER BY column_name) as row_columns,
                string_agg(
                    '          ' || column_name ||
                    CASE
                        -- For ALWAYS generated identity columns, type is 'never' on insert
                        WHEN attidentity = 'a' THEN '?: never'
                        -- For other columns, optional if nullable, has default, or is named 'id'
                        ELSE
                            (CASE
                                WHEN NOT attnotnull OR atthasdef OR column_name = 'id' THEN '?: '
                                ELSE ': '
                            END) ||
                            base_ts_type ||
                            (CASE WHEN NOT attnotnull THEN ' | null' ELSE '' END)
                    END,
                    E'\n' ORDER BY column_name
                ) as insert_columns,
                string_agg(
                    '          ' || column_name ||
                    CASE
                        -- For ALWAYS generated identity columns, type is 'never' on update
                        WHEN attidentity = 'a' THEN '?: never'
                        -- For all other columns, it's optional
                        ELSE '?: ' || base_ts_type || (CASE WHEN NOT attnotnull THEN ' | null' ELSE '' END)
                    END,
                    E'\n' ORDER BY column_name
                ) as update_columns,
                r.relationships_ts
            FROM columns c
            LEFT JOIN all_relationships r ON c.table_oid = r.conrelid
            GROUP BY c.table_name, c.table_oid, c.relkind, r.relationships_ts
        )
        SELECT
            '    Tables: {' || E'\n' ||
            COALESCE(string_agg(
                '      ' || table_name || ': {' || E'\n' ||
                '        Row: {' || E'\n' ||
                row_columns || E'\n' ||
                E'        },\n' ||
                '        Insert: {' || E'\n' ||
                insert_columns || E'\n' ||
                E'        },\n' ||
                '        Update: {' || E'\n' ||
                update_columns || E'\n' ||
                '        }' ||
                E',\n' || COALESCE(relationships_ts, '        Relationships: []') || E'\n' ||
                '      }',
                E',\n' ORDER BY table_name
            ) FILTER (WHERE relkind IN ('r', 'p')), '') || E'\n' ||
            '    }',
            '    Views: {' || E'\n' ||
            COALESCE(string_agg(
                '      ' || table_name || ': {' || E'\n' ||
                '        Row: {' || E'\n' ||
                row_columns || E'\n' ||
                E'        },\n' ||
                '        Insert: {' || E'\n' ||
                insert_columns || E'\n' ||
                E'        },\n' ||
                '        Update: {' || E'\n' ||
                update_columns || E'\n' ||
                '        }' ||
                E',\n' || COALESCE(relationships_ts, '        Relationships: []') || E'\n' ||
                '      }',
                E',\n' ORDER BY table_name
            ) FILTER (WHERE relkind IN ('v', 'm')), '') || E'\n' ||
            '    }'
        INTO v_tables_output, v_views_output
        FROM tables;

        -- Generate Functions
        WITH functions AS (
            SELECT
                p.oid,
                p.proname AS function_name,
                p.proretset AS returns_set,
                p.prorettype AS return_type_oid,
                COALESCE(p.proargnames, ARRAY[]::text[]) AS arg_names,
                (CASE WHEN p.pronargs = 0 THEN ARRAY[]::oid[] ELSE string_to_array(p.proargtypes::text, ' ')::oid[] END) AS arg_types,
                p.pronargs as arg_count
            FROM pg_proc p
            JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = v_schema_name AND p.prokind = 'f' AND NOT (
                p.proname LIKE E'\\_%' OR
                p.proname LIKE 'pg_%' OR
                p.proname LIKE 'plpgsql_%' OR
                p.proname IN ('armor', 'dearmor', 'http', 'sign', 'verify', 'url_decode', 'url_encode', 'try_cast_double', 'text2ltree')
            )
        ),
        function_signatures AS (
            SELECT
                f.oid,
                f.function_name,
                '        Args: ' ||
                CASE
                    WHEN f.arg_count = 0 THEN 'never'
                    ELSE '{' || E'\n' || (
                        SELECT string_agg(
                            '          ' || COALESCE(NULLIF(f.arg_names[s.idx], ''), 'arg' || (s.idx - 1)) || '?: ' ||
                            CASE
                                -- Enums: only reference if in included schemas
                                WHEN t.typtype = 'e' AND tn.nspname = ANY(v_schemas) THEN format('Database["%s"]["Enums"]["%s"]', tn.nspname, t.typname)
                                WHEN t.typtype = 'e' THEN 'unknown'
                                -- Composite types: determine if it's a table, view, or pure composite type
                                WHEN t.typtype = 'c' AND tn.nspname = ANY(v_schemas) THEN
                                    CASE tc.relkind
                                        WHEN 'r' THEN format('Database["%s"]["Tables"]["%s"]["Row"]', tn.nspname, t.typname) -- table
                                        WHEN 'p' THEN format('Database["%s"]["Tables"]["%s"]["Row"]', tn.nspname, t.typname) -- partitioned table
                                        WHEN 'v' THEN format('Database["%s"]["Views"]["%s"]["Row"]', tn.nspname, t.typname) -- view
                                        WHEN 'm' THEN format('Database["%s"]["Views"]["%s"]["Row"]', tn.nspname, t.typname) -- materialized view
                                        WHEN 'c' THEN format('Database["%s"]["CompositeTypes"]["%s"]', tn.nspname, t.typname) -- pure composite
                                        ELSE 'unknown'
                                    END
                                WHEN t.typtype = 'c' THEN 'unknown'
                                -- Arrays
                                WHEN t.typcategory = 'A' THEN
                                    CASE
                                        WHEN t_element.typtype = 'e' AND tn.nspname = ANY(v_schemas) THEN format('Database["%s"]["Enums"]["%s"][]', tn.nspname, t_element.typname)
                                        WHEN t_element.typtype = 'e' THEN 'unknown[]'
                                        WHEN t_element.typtype = 'c' AND tn.nspname = ANY(v_schemas) THEN
                                            CASE tc_element.relkind
                                                WHEN 'r' THEN format('Database["%s"]["Tables"]["%s"]["Row"][]', tn.nspname, t_element.typname)
                                                WHEN 'p' THEN format('Database["%s"]["Tables"]["%s"]["Row"][]', tn.nspname, t_element.typname)
                                                WHEN 'v' THEN format('Database["%s"]["Views"]["%s"]["Row"][]', tn.nspname, t_element.typname)
                                                WHEN 'm' THEN format('Database["%s"]["Views"]["%s"]["Row"][]', tn.nspname, t_element.typname)
                                                WHEN 'c' THEN format('Database["%s"]["CompositeTypes"]["%s"][]', tn.nspname, t_element.typname)
                                                ELSE 'unknown[]'
                                            END
                                        WHEN t_element.typtype = 'c' THEN 'unknown[]'
                                        ELSE CASE t_element.typname WHEN 'bool' THEN 'boolean[]' WHEN 'int2' THEN 'number[]' WHEN 'int4' THEN 'number[]' WHEN 'int8' THEN 'number[]' WHEN 'float4' THEN 'number[]' WHEN 'float8' THEN 'number[]' WHEN 'numeric' THEN 'number[]' WHEN 'text' THEN 'string[]' WHEN 'varchar' THEN 'string[]' WHEN 'char' THEN 'string[]' WHEN 'uuid' THEN 'string[]' WHEN 'date' THEN 'string[]' WHEN 'timestamp' THEN 'string[]' WHEN 'timestamptz' THEN 'string[]' WHEN 'json' THEN 'Json[]' WHEN 'jsonb' THEN 'Json[]' WHEN 'ltree' THEN 'string[]' WHEN 'daterange' THEN 'string[]' WHEN 'tsrange' THEN 'string[]' WHEN 'tstzrange' THEN 'string[]' WHEN 'int4range' THEN 'string[]' WHEN 'int8range' THEN 'string[]' WHEN 'numrange' THEN 'string[]' WHEN 'tsvector' THEN 'string[]' WHEN 'name' THEN 'string[]' WHEN 'oid' THEN 'number[]' WHEN 'regproc' THEN 'string[]' WHEN 'interval' THEN 'string[]' WHEN 'bytea' THEN 'string[]' WHEN 'inet' THEN 'string[]' WHEN 'cidr' THEN 'string[]' WHEN 'macaddr' THEN 'string[]' ELSE 'unknown[]' END
                                    END
                                ELSE
                                    CASE t.typname WHEN 'bool' THEN 'boolean' WHEN 'int2' THEN 'number' WHEN 'int4' THEN 'number' WHEN 'int8' THEN 'number' WHEN 'float4' THEN 'number' WHEN 'float8' THEN 'number' WHEN 'numeric' THEN 'number' WHEN 'text' THEN 'string' WHEN 'varchar' THEN 'string' WHEN 'char' THEN 'string' WHEN 'uuid' THEN 'string' WHEN 'date' THEN 'string' WHEN 'timestamp' THEN 'string' WHEN 'timestamptz' THEN 'string' WHEN 'json' THEN 'Json' WHEN 'jsonb' THEN 'Json' WHEN 'ltree' THEN 'string' WHEN 'daterange' THEN 'string' WHEN 'tsrange' THEN 'string' WHEN 'tstzrange' THEN 'string' WHEN 'int4range' THEN 'string' WHEN 'int8range' THEN 'string' WHEN 'numrange' THEN 'string' WHEN 'tsvector' THEN 'string' WHEN 'name' THEN 'string' WHEN 'oid' THEN 'number' WHEN 'regproc' THEN 'string' WHEN 'interval' THEN 'string' WHEN 'bytea' THEN 'string' WHEN 'inet' THEN 'string' WHEN 'cidr' THEN 'string' WHEN 'macaddr' THEN 'string' ELSE 'unknown' END
                            END,
                            E'\n' ORDER BY s.idx
                        )
                        FROM generate_subscripts(f.arg_types, 1) AS s(idx)
                        JOIN pg_type t ON t.oid = f.arg_types[s.idx]
                        JOIN pg_namespace tn ON tn.oid = t.typnamespace
                        LEFT JOIN pg_type t_element ON t_element.oid = t.typelem
                        LEFT JOIN pg_class tc ON tc.oid = t.typrelid -- for determining table/view/composite
                        LEFT JOIN pg_class tc_element ON tc_element.oid = t_element.typrelid -- for array element type
                    ) || E'\n' || '        }'
                END as args_ts,
                '        Returns: ' ||
                CASE
                    -- Enums: only reference if in included schemas
                    WHEN rt.typtype = 'e' AND rtn.nspname = ANY(v_schemas) THEN format('Database["%s"]["Enums"]["%s"]', rtn.nspname, rt.typname)
                    WHEN rt.typtype = 'e' THEN 'unknown'
                    -- Composite types: determine if it's a table, view, or pure composite type
                    WHEN rt.typtype = 'c' AND rtn.nspname = ANY(v_schemas) THEN
                        CASE rtc.relkind
                            WHEN 'r' THEN format('Database["%s"]["Tables"]["%s"]["Row"]', rtn.nspname, rt.typname) -- table
                            WHEN 'p' THEN format('Database["%s"]["Tables"]["%s"]["Row"]', rtn.nspname, rt.typname) -- partitioned table
                            WHEN 'v' THEN format('Database["%s"]["Views"]["%s"]["Row"]', rtn.nspname, rt.typname) -- view
                            WHEN 'm' THEN format('Database["%s"]["Views"]["%s"]["Row"]', rtn.nspname, rt.typname) -- materialized view
                            WHEN 'c' THEN format('Database["%s"]["CompositeTypes"]["%s"]', rtn.nspname, rt.typname) -- pure composite
                            ELSE 'unknown'
                        END
                    WHEN rt.typtype = 'c' THEN 'unknown'
                    -- Arrays
                    WHEN rt.typcategory = 'A' THEN
                        CASE
                            WHEN rt_element.typtype = 'e' AND rtn.nspname = ANY(v_schemas) THEN format('Database["%s"]["Enums"]["%s"][]', rtn.nspname, rt_element.typname)
                            WHEN rt_element.typtype = 'e' THEN 'unknown[]'
                            WHEN rt_element.typtype = 'c' AND rtn.nspname = ANY(v_schemas) THEN
                                CASE rtc_element.relkind
                                    WHEN 'r' THEN format('Database["%s"]["Tables"]["%s"]["Row"][]', rtn.nspname, rt_element.typname)
                                    WHEN 'p' THEN format('Database["%s"]["Tables"]["%s"]["Row"][]', rtn.nspname, rt_element.typname)
                                    WHEN 'v' THEN format('Database["%s"]["Views"]["%s"]["Row"][]', rtn.nspname, rt_element.typname)
                                    WHEN 'm' THEN format('Database["%s"]["Views"]["%s"]["Row"][]', rtn.nspname, rt_element.typname)
                                    WHEN 'c' THEN format('Database["%s"]["CompositeTypes"]["%s"][]', rtn.nspname, rt_element.typname)
                                    ELSE 'unknown[]'
                                END
                            WHEN rt_element.typtype = 'c' THEN 'unknown[]'
                            ELSE CASE rt_element.typname WHEN 'bool' THEN 'boolean[]' WHEN 'int2' THEN 'number[]' WHEN 'int4' THEN 'number[]' WHEN 'int8' THEN 'number[]' WHEN 'float4' THEN 'number[]' WHEN 'float8' THEN 'number[]' WHEN 'numeric' THEN 'number[]' WHEN 'text' THEN 'string[]' WHEN 'varchar' THEN 'string[]' WHEN 'char' THEN 'string[]' WHEN 'uuid' THEN 'string[]' WHEN 'date' THEN 'string[]' WHEN 'timestamp' THEN 'string[]' WHEN 'timestamptz' THEN 'string[]' WHEN 'json' THEN 'Json[]' WHEN 'jsonb' THEN 'Json[]' WHEN 'ltree' THEN 'string[]' WHEN 'daterange' THEN 'string[]' WHEN 'tsrange' THEN 'string[]' WHEN 'tstzrange' THEN 'string[]' WHEN 'int4range' THEN 'string[]' WHEN 'int8range' THEN 'string[]' WHEN 'numrange' THEN 'string[]' WHEN 'tsvector' THEN 'string[]' WHEN 'name' THEN 'string[]' WHEN 'oid' THEN 'number[]' WHEN 'regproc' THEN 'string[]' WHEN 'interval' THEN 'string[]' WHEN 'bytea' THEN 'string[]' WHEN 'inet' THEN 'string[]' WHEN 'cidr' THEN 'string[]' WHEN 'macaddr' THEN 'string[]' ELSE 'unknown[]' END
                        END
                    ELSE
                        CASE rt.typname WHEN 'bool' THEN 'boolean' WHEN 'int2' THEN 'number' WHEN 'int4' THEN 'number' WHEN 'int8' THEN 'number' WHEN 'float4' THEN 'number' WHEN 'float8' THEN 'number' WHEN 'numeric' THEN 'number' WHEN 'text' THEN 'string' WHEN 'varchar' THEN 'string' WHEN 'char' THEN 'string' WHEN 'uuid' THEN 'string' WHEN 'date' THEN 'string' WHEN 'timestamp' THEN 'string' WHEN 'timestamptz' THEN 'string' WHEN 'json' THEN 'Json' WHEN 'jsonb' THEN 'Json' WHEN 'record' THEN 'Record<string, unknown>[]' WHEN 'ltree' THEN 'string' WHEN 'daterange' THEN 'string' WHEN 'tsrange' THEN 'string' WHEN 'tstzrange' THEN 'string' WHEN 'int4range' THEN 'string' WHEN 'int8range' THEN 'string' WHEN 'numrange' THEN 'string' WHEN 'tsvector' THEN 'string' WHEN 'name' THEN 'string' WHEN 'oid' THEN 'number' WHEN 'regproc' THEN 'string' WHEN 'interval' THEN 'string' WHEN 'bytea' THEN 'string' WHEN 'inet' THEN 'string' WHEN 'cidr' THEN 'string' WHEN 'macaddr' THEN 'string' ELSE 'unknown' END
                END ||
                (CASE WHEN f.returns_set AND rt.typname <> 'record' THEN '[]' ELSE '' END) as returns_ts
            FROM functions f
            JOIN pg_type rt ON rt.oid = f.return_type_oid
            JOIN pg_namespace rtn ON rtn.oid = rt.typnamespace
            LEFT JOIN pg_type rt_element ON rt_element.oid = rt.typelem
            LEFT JOIN pg_class rtc ON rtc.oid = rt.typrelid -- for determining table/view/composite
            LEFT JOIN pg_class rtc_element ON rtc_element.oid = rt_element.typrelid -- for array element type
        ),
        -- Add SetofOptions for computed relationships (functions that take a row and return SETOF)
        function_setof_options AS (
            SELECT
                f.oid,
                f.function_name,
                -- from: the argument table/view name
                (SELECT t.typname FROM pg_type t WHERE t.oid = f.arg_types[1]) as from_type,
                -- to: the return table/view name
                rt.typname as to_type,
                f.returns_set
            FROM functions f
            JOIN pg_type rt ON rt.oid = f.return_type_oid
            WHERE f.arg_count = 1  -- single argument
              AND f.returns_set    -- returns SETOF
              AND rt.typtype = 'c' -- returns composite type (table/view row)
              AND (SELECT t.typtype FROM pg_type t WHERE t.oid = f.arg_types[1]) = 'c' -- arg is composite
        ),
        function_overloads AS (
            SELECT
                fs.function_name,
                array_agg(
                    '{' || E'\n' ||
                    fs.args_ts || E'\n' ||
                    fs.returns_ts ||
                    -- Add SetofOptions if this is a computed relationship function
                    COALESCE((
                        SELECT E'\n        SetofOptions: {\n          from: "' || fso.from_type || E'"\n          to: "' || fso.to_type || E'"\n          isOneToOne: true\n          isSetofReturn: true\n        }'
                        FROM function_setof_options fso
                        WHERE fso.oid = fs.oid
                    ), '') || E'\n' ||
                    '      }'
                    ORDER BY fs.oid
                ) AS signatures
            FROM function_signatures fs
            GROUP BY fs.function_name
        )
        SELECT
            '    Functions: {' || E'\n' ||
            COALESCE(string_agg(
                '      ' || function_name || ': ' ||
                CASE
                    WHEN array_length(signatures, 1) > 1 THEN array_to_string(signatures, E'\n' || '        | ')
                    ELSE signatures[1]
                END,
                E',\n' ORDER BY function_name
            ), '') || E'\n' ||
            '    }'
        INTO v_functions_output
        FROM function_overloads;

        -- Generate Composite Types
        WITH composite_type_columns AS (
            SELECT
                pt.oid as type_oid,
                pt.typname as type_name,
                pa.attname as column_name,
                pa.attnum,
                pa.attnotnull,
                CASE
                    WHEN ct.typtype = 'e' THEN format('Database["%s"]["Enums"]["%s"]', pn.nspname, ct.typname)
                    WHEN ct.typtype = 'c' THEN format('Database["%s"]["CompositeTypes"]["%s"]', pn.nspname, ct.typname)
                    WHEN ct.typcategory = 'A' THEN
                        CASE
                            WHEN ct_element.typtype = 'e' THEN format('Database["%s"]["Enums"]["%s"][]', pn.nspname, ct_element.typname)
                            WHEN ct_element.typtype = 'c' THEN format('Database["%s"]["CompositeTypes"]["%s"][]', pn.nspname, ct_element.typname)
                            ELSE CASE ct_element.typname WHEN 'bool' THEN 'boolean[]' WHEN 'int2' THEN 'number[]' WHEN 'int4' THEN 'number[]' WHEN 'int8' THEN 'number[]' WHEN 'float4' THEN 'number[]' WHEN 'float8' THEN 'number[]' WHEN 'numeric' THEN 'number[]' WHEN 'text' THEN 'string[]' WHEN 'varchar' THEN 'string[]' WHEN 'char' THEN 'string[]' WHEN 'uuid' THEN 'string[]' WHEN 'date' THEN 'string[]' WHEN 'timestamp' THEN 'string[]' WHEN 'timestamptz' THEN 'string[]' WHEN 'json' THEN 'Json[]' WHEN 'jsonb' THEN 'Json[]' WHEN 'ltree' THEN 'string[]' WHEN 'daterange' THEN 'string[]' WHEN 'tsrange' THEN 'string[]' WHEN 'tstzrange' THEN 'string[]' WHEN 'int4range' THEN 'string[]' WHEN 'int8range' THEN 'string[]' WHEN 'numrange' THEN 'string[]' WHEN 'tsvector' THEN 'string[]' WHEN 'name' THEN 'string[]' WHEN 'oid' THEN 'number[]' WHEN 'regproc' THEN 'string[]' WHEN 'interval' THEN 'string[]' WHEN 'bytea' THEN 'string[]' WHEN 'inet' THEN 'string[]' WHEN 'cidr' THEN 'string[]' WHEN 'macaddr' THEN 'string[]' ELSE 'unknown[]' END
                        END
                    ELSE
                        CASE ct.typname WHEN 'bool' THEN 'boolean' WHEN 'int2' THEN 'number' WHEN 'int4' THEN 'number' WHEN 'int8' THEN 'number' WHEN 'float4' THEN 'number' WHEN 'float8' THEN 'number' WHEN 'numeric' THEN 'number' WHEN 'text' THEN 'string' WHEN 'varchar' THEN 'string' WHEN 'char' THEN 'string' WHEN 'uuid' THEN 'string' WHEN 'date' THEN 'string' WHEN 'timestamp' THEN 'string' WHEN 'timestamptz' THEN 'string' WHEN 'json' THEN 'Json' WHEN 'jsonb' THEN 'Json' WHEN 'ltree' THEN 'string' WHEN 'daterange' THEN 'string' WHEN 'tsrange' THEN 'string' WHEN 'tstzrange' THEN 'string' WHEN 'int4range' THEN 'string' WHEN 'int8range' THEN 'string' WHEN 'numrange' THEN 'string' WHEN 'tsvector' THEN 'string' WHEN 'name' THEN 'string' WHEN 'oid' THEN 'number' WHEN 'regproc' THEN 'string' WHEN 'interval' THEN 'string' WHEN 'bytea' THEN 'string' WHEN 'inet' THEN 'string' WHEN 'cidr' THEN 'string' WHEN 'macaddr' THEN 'string' ELSE 'unknown' END
                END as ts_type
            FROM pg_type pt
            JOIN pg_namespace pn ON pn.oid = pt.typnamespace
            JOIN pg_class pc ON pc.oid = pt.typrelid
            JOIN pg_attribute pa ON pa.attrelid = pt.typrelid
            JOIN pg_type ct ON ct.oid = pa.atttypid
            LEFT JOIN pg_type ct_element ON ct_element.oid = ct.typelem
            WHERE pn.nspname = v_schema_name
              AND pt.typtype = 'c'
              AND pc.relkind = 'c' -- Exclude composite types that are tables/views
              AND pa.attnum > 0 AND NOT pa.attisdropped
        ),
        composite_types AS (
            SELECT
                type_name,
                string_agg(
                    '        ' || column_name || ': ' || ts_type || (CASE WHEN NOT attnotnull THEN ' | null' ELSE '' END),
                    E'\n' ORDER BY attnum
                ) AS columns_ts
            FROM composite_type_columns
            GROUP BY type_name
        )
        SELECT
            '    CompositeTypes: {' || E'\n' ||
            COALESCE(string_agg(
                '      ' || type_name || ': {' || E'\n' ||
                columns_ts || E'\n' ||
                '      }',
                E',\n' ORDER BY type_name
            ), '') || E'\n' ||
            '    }'
        INTO v_composite_types_output
        FROM composite_types;

        -- Combine generated parts
        v_output := v_output || array_to_string(
            ARRAY[
                v_tables_output,
                v_views_output,
                v_functions_output,
                v_enums_output,
                v_composite_types_output
            ],
            E',\n'
        );

        v_output := v_output || '
  }';
    END LOOP;


    -- Final closing brace for Database type
    v_output := v_output || '
}
';

    -- Append helper types (matching Supabase's exact format)
    v_output := v_output || $$

type PublicSchema = Database[Extract<keyof Database, "public">]

export type Tables<
  PublicTableNameOrOptions extends
    | keyof (PublicSchema["Tables"] & PublicSchema["Views"])
    | { schema: keyof Database },
  TableName extends PublicTableNameOrOptions extends { schema: keyof Database }
    ? keyof (Database[PublicTableNameOrOptions["schema"]]["Tables"] &
        Database[PublicTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = PublicTableNameOrOptions extends { schema: keyof Database }
  ? (Database[PublicTableNameOrOptions["schema"]]["Tables"] &
      Database[PublicTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : PublicTableNameOrOptions extends keyof (PublicSchema["Tables"] &
        PublicSchema["Views"])
    ? (PublicSchema["Tables"] &
        PublicSchema["Views"])[PublicTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  PublicTableNameOrOptions extends
    | keyof PublicSchema["Tables"]
    | { schema: keyof Database },
  TableName extends PublicTableNameOrOptions extends { schema: keyof Database }
    ? keyof Database[PublicTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = PublicTableNameOrOptions extends { schema: keyof Database }
  ? Database[PublicTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : PublicTableNameOrOptions extends keyof PublicSchema["Tables"]
    ? PublicSchema["Tables"][PublicTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  PublicTableNameOrOptions extends
    | keyof PublicSchema["Tables"]
    | { schema: keyof Database },
  TableName extends PublicTableNameOrOptions extends { schema: keyof Database }
    ? keyof Database[PublicTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = PublicTableNameOrOptions extends { schema: keyof Database }
  ? Database[PublicTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : PublicTableNameOrOptions extends keyof PublicSchema["Tables"]
    ? PublicSchema["Tables"][PublicTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  PublicEnumNameOrOptions extends
    | keyof PublicSchema["Enums"]
    | { schema: keyof Database },
  EnumName extends PublicEnumNameOrOptions extends {
    schema: keyof Database
  }
    ? keyof Database[PublicEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = PublicEnumNameOrOptions extends {
  schema: keyof Database
}
  ? Database[PublicEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : PublicEnumNameOrOptions extends keyof PublicSchema["Enums"]
    ? PublicSchema["Enums"][PublicEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof PublicSchema["CompositeTypes"]
    | { schema: keyof Database },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof Database
  }
    ? keyof Database[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof Database
}
  ? Database[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof PublicSchema["CompositeTypes"]
    ? PublicSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never
$$;

    -- Generate and Append Constants
    WITH enum_details AS (
        SELECT
            t.oid as type_oid,
            n.nspname as schema_name,
            t.typname,
            array_agg('"' || e.enumlabel || '"' ORDER BY e.enumsortorder) as enum_values_array,
            string_agg('"' || e.enumlabel || '"', ', ' ORDER BY e.enumsortorder) as single_line_values
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        JOIN pg_enum e ON t.oid = e.enumtypid
        WHERE n.nspname = ANY(v_schemas) AND t.typtype = 'e'
        GROUP BY t.oid, n.nspname, t.typname
    ),
    formatted_enums AS (
        SELECT
            schema_name,
            typname,
            CASE
                WHEN length(single_line_definition) > 80 THEN multi_line_definition
                ELSE single_line_definition
            END as enum_definition
        FROM (
            SELECT
                schema_name,
                typname,
                '      ' || typname || ': [' || single_line_values || ']' as single_line_definition,
                '      ' || typname || ': [' || E'\n        ' || array_to_string(enum_values_array, E',\n        ') || E'\n      ]' as multi_line_definition
            FROM enum_details
        ) as definitions
    )
    SELECT
        E'\nexport const Constants = {\n' ||
        COALESCE(string_agg(
            format('  %I: {', schema_name) || E'\n' ||
            '    Enums: {' || E'\n' ||
            enum_definitions || E'\n' ||
            '    }' || E'\n' ||
            '  }',
            E',\n' ORDER BY schema_name
        ), '') ||
        E'\n} as const\n'
    INTO v_constants_output
    FROM (
        SELECT
            schema_name,
            string_agg(enum_definition, E',\n' ORDER BY typname) as enum_definitions
        FROM formatted_enums
        GROUP BY schema_name
    ) AS schema_enums;

    v_output := v_output || COALESCE(v_constants_output, '');


    RETURN v_output;
END;
$generate_typescript_types$;

-- Generate the file
\t\a
\o app/src/lib/database.types.ts
SELECT public.generate_typescript_types();
\o
