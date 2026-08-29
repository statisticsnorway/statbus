```sql
CREATE OR REPLACE PROCEDURE public.normalize_all_sequences()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    r RECORD;
    v_max BIGINT;
    v_skipped TEXT;
BEGIN
    FOR r IN
        SELECT
            quote_ident(sn.nspname) || '.' || quote_ident(s.relname) AS seq_ident,
            quote_ident(a.attname) AS col_ident,
            quote_ident(tn.nspname) || '.' || quote_ident(t.relname) AS tbl_ident
        FROM pg_class s
        JOIN pg_namespace sn ON sn.oid = s.relnamespace
        JOIN pg_depend d ON d.objid = s.oid
                         AND d.classid = 'pg_class'::regclass
                         AND d.refclassid = 'pg_class'::regclass
        JOIN pg_class t ON t.oid = d.refobjid
        JOIN pg_namespace tn ON tn.oid = t.relnamespace
        JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = d.refobjsubid
        WHERE s.relkind = 'S'
          AND d.deptype IN ('a', 'i')
        ORDER BY 1
    LOOP
        EXECUTE format('SELECT max(%s) FROM %s', r.col_ident, r.tbl_ident) INTO v_max;
        PERFORM setval(r.seq_ident, COALESCE(v_max, 1), v_max IS NOT NULL);
    END LOOP;

    SELECT string_agg(seq, ', ' ORDER BY seq) INTO v_skipped
    FROM (
        SELECT n.nspname || '.' || c.relname AS seq
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relkind = 'S'
        EXCEPT
        SELECT sn.nspname || '.' || s.relname
        FROM pg_class s
        JOIN pg_namespace sn ON sn.oid = s.relnamespace
        JOIN pg_depend d ON d.objid = s.oid
                         AND d.classid = 'pg_class'::regclass
                         AND d.refclassid = 'pg_class'::regclass
        JOIN pg_class t ON t.oid = d.refobjid
        JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = d.refobjsubid
        WHERE s.relkind = 'S' AND d.deptype IN ('a', 'i')
    ) unowned;

    IF v_skipped IS NOT NULL THEN
        RAISE NOTICE 'normalize_all_sequences: skipped % (no owning column to derive an authoritative max from -- this procedure only ever normalizes column-owned sequences)', v_skipped;
    END IF;
END;
$procedure$
```
