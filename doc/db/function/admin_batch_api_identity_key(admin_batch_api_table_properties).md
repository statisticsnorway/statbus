```sql
CREATE OR REPLACE FUNCTION admin.batch_api_identity_key(table_properties admin.batch_api_table_properties)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    _key_column text;
    _table regclass := format('%I.%I', table_properties.schema_name, table_properties.table_name)::regclass;
BEGIN
    -- STATBUS-477: the identity key a generated upsert must conflict on is the
    -- one the table really has. A unique key on the code/path ALONE wins (one
    -- row per code/path); otherwise (code/path, custom). Non-partial unique
    -- indexes only: a partial index (e.g. WHERE enabled) cannot be an
    -- ON CONFLICT target for every row.
    IF table_properties.has_path THEN
        _key_column := 'path';
    ELSIF table_properties.has_code THEN
        _key_column := 'code';
    ELSE
        RAISE EXCEPTION 'STATBUS-477: % has neither path nor code, so it has no batch API identity key', _table;
    END IF;

    IF EXISTS (
        SELECT 1
          FROM pg_catalog.pg_index AS i
         WHERE i.indrelid = _table
           AND i.indisunique
           AND i.indpred IS NULL
           AND i.indnkeyatts = 1
           AND i.indkey[0] = (SELECT a.attnum FROM pg_catalog.pg_attribute AS a
                               WHERE a.attrelid = _table AND a.attname = _key_column))
    THEN
        RETURN ARRAY[_key_column];
    END IF;

    IF table_properties.has_custom AND EXISTS (
        SELECT 1
          FROM pg_catalog.pg_index AS i
         WHERE i.indrelid = _table
           AND i.indisunique
           AND i.indpred IS NULL
           AND i.indnkeyatts = 2
           AND (SELECT array_agg(a.attname::text ORDER BY a.attname)
                  FROM pg_catalog.pg_attribute AS a
                 WHERE a.attrelid = _table AND a.attnum = ANY (i.indkey::int2[]))
               = (SELECT array_agg(c ORDER BY c) FROM unnest(ARRAY[_key_column, 'custom']) AS c))
    THEN
        RETURN ARRAY[_key_column, 'custom'];
    END IF;

    -- No identity key yet: the default admin.generate_active_code_custom_unique_constraint
    -- creates. Code tables with custom get (code, custom) (one system row and
    -- at most one custom override, STATBUS-477 B); path tables get (path),
    -- since the path upsert derives parent_id by path and needs one row per path.
    IF _key_column = 'code' AND table_properties.has_custom THEN
        RETURN ARRAY['code', 'custom'];
    END IF;
    RETURN ARRAY[_key_column];
END;
$function$
```
