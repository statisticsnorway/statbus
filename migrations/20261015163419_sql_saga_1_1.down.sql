-- Down Migration 20261015163419: sql_saga 1.1
--
-- sql_saga ships no 1.1 -> 1.0 script: the update normalizes ACLs and removes
-- the 1.0 cache API, which cannot be reconstructed. Returning to 1.0 means
-- restoring the pre-upgrade backup, which the upgrade's rollback does.
BEGIN;

DO $sql_saga_1_1_down$
BEGIN
    RAISE EXCEPTION 'sql_saga 1.1 cannot be downgraded in place; restore the pre-upgrade backup';
END;
$sql_saga_1_1_down$;

END;
