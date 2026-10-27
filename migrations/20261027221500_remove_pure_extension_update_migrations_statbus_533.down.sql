-- Down Migration 20261027221500: remove pure extension-update migration ledger rows
--
-- Irreversible by design (STATBUS-533): re-inserting db.migration rows for
-- the deleted pure extension-update migration files would be fake history —
-- the files no longer exist, and assert-db-at-head compares the row set
-- against the on-disk files, so resurrecting the rows would read as drift
-- forever. Rollback to before this change means restoring the pre-upgrade
-- backup, which the upgrade's rollback does.
BEGIN;

DO $remove_pure_extension_update_migrations_down$
BEGIN
    RAISE EXCEPTION 'migration 20261027221500 cannot be undone in place: re-inserting db.migration rows for deleted migration files would be fake history; restore the pre-upgrade backup';
END;
$remove_pure_extension_update_migrations_down$;

END;
