BEGIN;

-- Add 'edge' channel for tracking every master commit (rolling releases).
-- Edge servers auto-discover and auto-apply SHA-based upgrades from CI images.
ALTER TYPE public.upgrade_channel ADD VALUE IF NOT EXISTS 'edge';

END;
