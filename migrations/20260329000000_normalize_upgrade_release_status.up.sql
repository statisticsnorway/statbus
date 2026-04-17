-- Migration 20260329000000: normalize_upgrade_release_status
-- Bridging migration for servers that applied 20260328092344 before it was modified
-- to introduce the release_status enum. Those servers have is_release/is_prerelease
-- booleans instead of release_status. This migration is a no-op on servers that
-- already have the enum column.
BEGIN;

DO $$
BEGIN
  -- Only run if the old boolean columns exist (MA's state after old migration 306)
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'upgrade'
      AND column_name = 'is_release'
  ) THEN

    -- Create the enum if it doesn't exist yet
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'release_status_type') THEN
      CREATE TYPE public.release_status_type AS ENUM ('commit', 'prerelease', 'release');
    END IF;

    -- Add column (nullable first so we can backfill)
    ALTER TABLE public.upgrade ADD COLUMN release_status public.release_status_type;

    -- Backfill from booleans
    UPDATE public.upgrade SET release_status = CASE
      WHEN is_release    THEN 'release'::public.release_status_type
      WHEN is_prerelease THEN 'prerelease'::public.release_status_type
      ELSE                    'commit'::public.release_status_type
    END;

    -- Apply constraints to match the schema from the modified 20260328092344 migration
    ALTER TABLE public.upgrade ALTER COLUMN release_status SET NOT NULL;
    ALTER TABLE public.upgrade ALTER COLUMN release_status SET DEFAULT 'commit';

    -- Drop the old boolean columns
    ALTER TABLE public.upgrade DROP COLUMN is_release;
    ALTER TABLE public.upgrade DROP COLUMN is_prerelease;

  END IF;
END $$;

END;
