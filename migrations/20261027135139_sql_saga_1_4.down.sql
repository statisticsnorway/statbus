-- Down Migration 20261027135139: sql_saga 1.4
--
-- sql_saga ships no 1.4 -> 1.x script, and an extension at 1.4 needs the
-- 1.4 libraries. Returning to the previous version means restoring the
-- pre-upgrade backup, which the upgrade's rollback does.
BEGIN;

DO $sql_saga_1_4_down$
BEGIN
    RAISE EXCEPTION 'sql_saga 1.4 cannot be downgraded in place; restore the pre-upgrade backup';
END;
$sql_saga_1_4_down$;

END;
