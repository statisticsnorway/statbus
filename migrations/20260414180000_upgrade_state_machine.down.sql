-- Down migration 20260414180000: upgrade_state_machine
BEGIN;

-- Drop the computed column function first — it depends on the upgrade row type
DROP FUNCTION IF EXISTS public.display_state(public.upgrade);

-- Drop the state CHECK and state column
ALTER TABLE public.upgrade DROP CONSTRAINT IF EXISTS chk_upgrade_state_attributes;
ALTER TABLE public.upgrade DROP COLUMN IF EXISTS state;

-- Restore the old conflated semantics for skipped_at: move any dismissed_at
-- values back into skipped_at so downgraded rows don't lose the
-- acknowledgement marker the pre-state-machine UI relied on.
UPDATE public.upgrade
   SET skipped_at = dismissed_at
 WHERE skipped_at IS NULL
   AND dismissed_at IS NOT NULL;

ALTER TABLE public.upgrade DROP COLUMN IF EXISTS dismissed_at;

DROP TYPE public.upgrade_state;

END;
