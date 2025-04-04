```sql
CREATE OR REPLACE FUNCTION public.generate_mermaid_er_diagram()
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
    rec RECORD;
    result text := 'erDiagram';
BEGIN
    -- First part of the query (tables and columns)
    result := result || E'\n\t%% Entities (derived from tables)';
    FOR rec IN
        SELECT format(E'\t%s["%s"] {\n%s\n\t}',
            -- Include the schema and a underscore if different than 'public' for the source table
            -- since period is not valid syntax for an entity name.
            CASE WHEN n.nspname <> 'public'
                 THEN n.nspname || '_' || c.relname
                 ELSE c.relname
            END,
            -- Provide the correct name with period as the label.
            CASE WHEN n.nspname <> 'public'
                 THEN n.nspname || '.' || c.relname
                 ELSE c.relname
            END,
            -- Notice that mermaid uses the "attribute_type attribute_name" pattern
            -- and that if there are spaces there must be double quoting.
            string_agg(format(E'\t\t"%s" %s',
                format_type(t.oid, a.atttypmod),
                a.attname
            ), E'\n' ORDER BY a.attnum)
        )
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        LEFT JOIN pg_attribute a ON c.oid = a.attrelid AND a.attnum > 0 AND NOT a.attisdropped
        LEFT JOIN pg_type t ON a.atttypid = t.oid
        WHERE c.relkind IN ('r', 'p')
          AND NOT c.relispartition
          AND n.nspname !~ '^pg_'
          AND n.nspname !~ '^_'
          AND n.nspname <> 'information_schema'
        GROUP BY n.nspname, c.relname
        ORDER BY n.nspname, c.relname
    LOOP
        result := result || E'\n' || rec.format;
    END LOOP;

    -- Second part of the query (foreign key constraints)
    result := result || E'\n\t%% Relationships (derived from foreign keys)';
    -- Documentation of relationship syntax from https://mermaid.js.org/syntax/entityRelationshipDiagram.html#relationship-syntax
    -- In particular:
    --     Value (left)    Value (right)   Meaning
    --     |o              o|              Zero or one
    --     ||              ||              Exactly one
    --     }o              o{              Zero or more (no upper limit)
    --     }|              |{              One or more (no upper limit)
    FOR rec IN
        SELECT format(E'\t%s %s--%s %s : %s',
            -- Include the schema and a underscore if different than 'public' for the source table
            -- since period is not valid syntax for an entity name.
            CASE WHEN n1.nspname <> 'public'
                 THEN n1.nspname || '_' || c1.relname
                 ELSE c1.relname
            END,
            -- The relationship cardinality from the referenced table (target) towards the referencing table (source).
            CASE
                WHEN EXISTS (
                    SELECT 1
                    FROM pg_constraint con
                    WHERE con.conrelid = c.confrelid
                    AND con.conkey = c.conkey
                    AND con.contype IN ('p', 'u')
                )
                THEN '}|' -- Every instance in the target can have one or more instances in the source
                ELSE '}o' -- Every instance in the target can have zero or more instances in the source
            END,
            -- The relationship cardinality from the referencing table (source) towards the referenced table (target).
            CASE
                WHEN a.attnotnull THEN '||' -- Every instance in the source must reference exactly one instance in the target
                ELSE 'o|'                   -- Every instance in the source may reference zero or one instance in the target
            END,
            -- Include the schema and a period if different than 'public' for the target table
            CASE WHEN n2.nspname <> 'public'
                 THEN n2.nspname || '.' || c2.relname
                 ELSE c2.relname
            END,
            c.conname
        )
        FROM pg_constraint c
        JOIN pg_class c1 ON c.conrelid = c1.oid AND c.contype = 'f'
        JOIN pg_class c2 ON c.confrelid = c2.oid
        JOIN pg_namespace n1 ON n1.oid = c1.relnamespace
        JOIN pg_namespace n2 ON n2.oid = c2.relnamespace
        JOIN pg_attribute a ON a.attnum = ANY (c.conkey) AND a.attrelid = c.conrelid
        WHERE NOT c1.relispartition
          AND NOT c2.relispartition
          AND n1.nspname !~ '^pg_'
          AND n1.nspname !~ '^_'
          AND n1.nspname <> 'information_schema'
          AND n2.nspname !~ '^pg_'
          AND n2.nspname !~ '^_'
          AND n2.nspname <> 'information_schema'
        ORDER BY n1.nspname, c1.relname, n2.nspname, c2.relname, c.conname
    LOOP
        result := result || E'\n' || rec.format;
    END LOOP;

    RETURN result;
END;
$function$
```
