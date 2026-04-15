-- Down Migration 20260415120722: add_discover_version_tag_to_upgrade
BEGIN;

ALTER TABLE public.upgrade DROP COLUMN IF EXISTS discover_version_tag;

END;
