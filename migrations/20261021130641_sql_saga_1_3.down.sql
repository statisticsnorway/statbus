-- Down Migration 20261021130641: sql_saga 1.3
--
-- sql_saga ships no 1.3 -> 1.1/1.2 script, and an extension at 1.3 needs the
-- 1.3 libraries. Returning to the previous version means restoring the
-- pre-upgrade backup, which the upgrade's rollback does.
BEGIN;

DO $sql_saga_1_3_down$
BEGIN
    RAISE EXCEPTION 'sql_saga 1.3 cannot be downgraded in place; restore the pre-upgrade backup';
END;
$sql_saga_1_3_down$;

END;
