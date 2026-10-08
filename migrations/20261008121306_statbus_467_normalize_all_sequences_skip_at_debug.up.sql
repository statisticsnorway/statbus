-- Migration 20261008121306: statbus_467_normalize_all_sequences_skip_at_debug
--
-- STATBUS-467. public.normalize_all_sequences() (migration 20260829114700,
-- STATBUS-316) reports the sequences it skips because no column owns them.
-- Skipping those is the procedure's documented, intended behaviour, yet it
-- was raised at NOTICE, the level clients show by default, so every seed
-- restore printed it in otherwise clean output where it read like a warning.
--
-- The only change: that report is raised at DEBUG instead of NOTICE. The
-- message text is byte-for-byte unchanged and the normalisation itself is
-- untouched (body dumped with \sf from a database at HEAD). The skip stays
-- observable on demand with SET client_min_messages TO debug, which is how
-- test/sql/127_statbus_316_normalize_all_sequences.sql keeps asserting it.
BEGIN;

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
        RAISE DEBUG 'normalize_all_sequences: skipped % (no owning column to derive an authoritative max from -- this procedure only ever normalizes column-owned sequences)', v_skipped;
    END IF;
END;
$procedure$;

END;
