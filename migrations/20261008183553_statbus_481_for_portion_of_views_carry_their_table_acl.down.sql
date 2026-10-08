-- Down for STATBUS-481 B: intentionally a no-op.
--
-- The up migration only ADDED grants to sql_saga for-portion-of views so that
-- each view's ACL equals its base table's ACL. Revoking them again would
-- recreate the inconsistent state that makes sql_saga's health check reject
-- every REVOKE in the database, and the grants are exactly what the base
-- table already grants, so leaving them is privilege-neutral.
BEGIN;
END;
