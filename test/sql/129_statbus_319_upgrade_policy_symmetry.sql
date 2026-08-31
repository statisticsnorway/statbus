\i test/setup.sql

-- STATBUS-319: policy-symmetry catalog test.
--
-- STATBUS-317 dropped SECURITY DEFINER from public.upgrade_state_log_capture()
-- (the trigger that logs every state transition), because DEFINER made
-- auth.uid() resolve to the trigger's OWNER instead of the caller, silently
-- breaking the 'verified' actor_source. The safety check at the time was
-- done BY HAND for one specific role (admin_user, read from pg_policy) and
-- confirmed symmetric: every role permitted to write public.upgrade also
-- carries a matching write-permitting policy on public.upgrade_state_log,
-- so dropping DEFINER cannot let a writer's UPDATE succeed while the
-- trigger's own INSERT into the log is refused by RLS (which would fail
-- the WHOLE transition, not just the logging).
--
-- This test makes that check a STANDING CATALOG ASSERTION rather than a
-- one-time manual read: a future policy change that grants some role
-- write access to public.upgrade WITHOUT a matching policy on
-- upgrade_state_log must be caught here, immediately and by name — not
-- discovered empirically months later when that role's first real
-- transition silently fails.
--
-- polcmd != 'r' is "anything that is not pure SELECT" — '*' (ALL), 'a'
-- (INSERT), 'w' (UPDATE), 'd' (DELETE) all count as write-permitting; only
-- a read-only policy is excluded from both sides of the comparison.

\echo -- Every role with ANY write-permitting policy on public.upgrade.
SELECT DISTINCT unnest(polroles)::regrole::text AS role_name
FROM pg_policy
WHERE polrelid = 'public.upgrade'::regclass AND polcmd != 'r'
ORDER BY 1;

\echo -- Every role with ANY write-permitting policy on public.upgrade_state_log.
SELECT DISTINCT unnest(polroles)::regrole::text AS role_name
FROM pg_policy
WHERE polrelid = 'public.upgrade_state_log'::regclass AND polcmd != 'r'
ORDER BY 1;

\echo -- THE ASSERTION: the first set must be a subset of the second. A non-empty
\echo -- result here means a real gap -- the exception below names it and the ticket.
DO $$
DECLARE
  v_missing text;
BEGIN
  SELECT string_agg(role_name, ', ' ORDER BY role_name) INTO v_missing
  FROM (
      SELECT DISTINCT unnest(polroles)::regrole::text AS role_name
      FROM pg_policy
      WHERE polrelid = 'public.upgrade'::regclass AND polcmd != 'r'
      EXCEPT
      SELECT DISTINCT unnest(polroles)::regrole::text AS role_name
      FROM pg_policy
      WHERE polrelid = 'public.upgrade_state_log'::regclass AND polcmd != 'r'
  ) missing;

  IF v_missing IS NOT NULL THEN
      RAISE EXCEPTION 'STATBUS-319: role(s) % can write public.upgrade but have no write-permitting policy on public.upgrade_state_log -- the log-capture trigger dropped SECURITY DEFINER (STATBUS-317), so its own INSERT is policy-subject; a writer without a matching log policy would have its UPDATE fail when the trigger''s INSERT is refused, failing the whole transition. Add a write policy for % on upgrade_state_log, or explain why this role''s writes to public.upgrade should never be logged.', v_missing, v_missing;
  END IF;
END $$;

SELECT 'STATBUS-319: policy symmetry holds -- every public.upgrade writer can also write upgrade_state_log' AS result;
