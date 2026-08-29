-- Migration 20260829201426: record WHO made an upgrade state transition
-- (STATBUS-317), on the LOG, not on public.upgrade itself.
--
-- WHY THE LOG, NOT NEW COLUMNS ON public.upgrade: the log already records
-- every transition with application_name/query/backend_pid
-- (public.upgrade_state_log_capture(), migration adding upgrade_state_log).
-- Only human identity was missing from a mechanism that already exists.
-- Adding actor/actor_source to public.upgrade itself would only ever hold
-- the LATEST transition's actor, discarding who made every earlier one --
-- exactly the history a log exists to keep.
--
-- PRECEDENCE, recorded as BOTH a value and how it is known (architect
-- design):
--   1. auth.uid() resolves to a real auth.user row -> actor = that user's
--      email, actor_source = 'verified'. This is the authenticated-session
--      case (e.g. a future admin-UI action through PostgREST with a JWT).
--   2. Else the session GUC statbus.actor, if set and non-empty ->
--      actor_source = 'self-reported'. This is the CLI's case: an operator
--      typed --operator, or answered an interactive prompt, and the CLI set
--      the GUC before writing.
--   3. Else actor = NULL, actor_source = 'absent'. The honest answer when
--      neither identity source fired -- e.g. CI's non-interactive
--      `./sb upgrade apply <sha>` over sshdo, or the daemon's own automatic
--      transitions (nothing human authored those at all).
--
-- NO MAGIC 'upgrade-service' VALUE: application_name already distinguishes
-- the service's own writes from a human's -- it has since the log table's
-- own creation -- so inventing a second, narrower identity concept for the
-- same distinction would be two mechanisms answering one question.
--
-- NO BACKFILL. Historical rows' actor is genuinely unknown -- there is no
-- source to derive it from after the fact, and the columns did not exist
-- when those rows were written. They get NULL/NULL (actor AND
-- actor_source), which is DIFFERENT from a future row's 'absent':
-- 'absent' means the trigger ran, checked both sources, and found neither;
-- NULL actor_source means the trigger that could check didn't exist yet.
-- Recorded here explicitly so a later reader does not mistake NULL
-- actor_source for an oversight and "fix" it with a backfill that would
-- manufacture certainty the fleet's history does not have.

BEGIN;

CREATE TYPE public.upgrade_actor_source AS ENUM ('verified', 'self-reported', 'absent');

ALTER TABLE public.upgrade_state_log
    ADD COLUMN actor text,
    ADD COLUMN actor_source public.upgrade_actor_source;

-- STATBUS-317: DROPPED SECURITY DEFINER (the pre-existing trigger had it;
-- this migration removes it — a deliberate, tested correction, not an
-- oversight). Empirically caught, not reasoned out in advance: a
-- SECURITY DEFINER function's current_user becomes the FUNCTION OWNER for
-- the duration of the call (Postgres's own documented behavior), so
-- auth.uid() (which reads current_user) called from INSIDE this trigger
-- would resolve the OWNER's identity, never the caller's — every
-- 'verified' row would silently log as 'absent' instead, the exact "looks
-- built, records nothing" failure shape the architect's GUC trap warned
-- about, just via a different mechanism. Confirmed safe to drop: every
-- role that can reach this trigger (by having UPDATE on public.upgrade at
-- all) already holds a DIRECT grant on upgrade_state_log too (admin_user:
-- INSERT/SELECT/UPDATE/DELETE; postgres: superuser) — checked via
-- information_schema.role_table_grants, not assumed — so nothing was ever
-- using the DEFINER escalation for privilege-bypass purposes on this
-- specific trigger.
CREATE OR REPLACE FUNCTION public.upgrade_state_log_capture()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid integer;
  v_actor text;
  v_actor_source public.upgrade_actor_source;
BEGIN
  -- STATBUS-317: precedence order, recorded as value + how it is known.
  v_uid := auth.uid();
  IF v_uid IS NOT NULL THEN
    SELECT email INTO v_actor FROM auth."user" WHERE id = v_uid;
    v_actor_source := 'verified';
  ELSE
    -- STATBUS-317 TRAP #2 (architect): set_config(..., true) is
    -- transaction-local. A caller that writes in autocommit (two separate
    -- statements, no explicit BEGIN) would have this setting evaporate
    -- before this trigger ever fires, and every row would silently record
    -- 'absent' -- a feature that appears built and records nothing. The
    -- CLI side of this contract (cli/internal/upgrade) wraps SET-then-write
    -- in one transaction; this trigger just reads whatever survived.
    v_actor := NULLIF(current_setting('statbus.actor', true), '');
    IF v_actor IS NOT NULL THEN
      v_actor_source := 'self-reported';
    ELSE
      v_actor_source := 'absent';
    END IF;
  END IF;

  INSERT INTO public.upgrade_state_log (
    upgrade_id, old_state, new_state, old_parked_at, new_parked_at,
    application_name, query, backend_pid, logged_at, actor, actor_source)
  VALUES (
    NEW.id, OLD.state, NEW.state, OLD.recovery_parked_at, NEW.recovery_parked_at,
    current_setting('application_name', true), current_query(),
    pg_backend_pid(), clock_timestamp(), v_actor, v_actor_source);
  RETURN NEW;
END;
$function$;

COMMIT;
