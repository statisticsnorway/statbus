-- Migration 20260327214113: add_published_at_to_upgrade
BEGIN;

ALTER TABLE public.upgrade ADD COLUMN published_at TIMESTAMPTZ;

END;
