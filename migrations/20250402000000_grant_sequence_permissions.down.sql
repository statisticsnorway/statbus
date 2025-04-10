-- Down Migration: Revoke sequence permissions from authenticated role
BEGIN;

-- Drop the event trigger
DROP EVENT TRIGGER IF EXISTS grant_sequence_permissions_on_create;

-- Drop the trigger function
DROP FUNCTION IF EXISTS admin.grant_sequence_permissions_trigger();

-- Drop the function that grants permissions
DROP FUNCTION IF EXISTS admin.grant_sequence_permissions();

-- Note: This migration does not revoke the permissions that were already granted
-- as that would be potentially disruptive. If needed, those would need to be
-- revoked manually or with a separate migration.

END;
