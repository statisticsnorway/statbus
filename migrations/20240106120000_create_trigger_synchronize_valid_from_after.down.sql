BEGIN;

-- Drop the trigger function created in the corresponding up migration.
-- Note: If any triggers were created using this function, they would need to be
-- dropped separately in their respective down migrations or here if they were
-- created in the same up migration. This up migration only creates the function.
DROP FUNCTION IF EXISTS public.synchronize_valid_from_after();

COMMIT;
