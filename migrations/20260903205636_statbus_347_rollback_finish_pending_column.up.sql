-- Migration 20260903205636: statbus_347_rollback_finish_pending_column
--
-- STATBUS-347: the cleanup-only rollback state becomes a constrained column.
--
-- A healthy rollback restores the snapshot, then must still remove its marker
-- and write rolled_back. Between those it records that it is "restored but
-- not finished" so that NO recovery path (install ladder, daemon boot, claim)
-- ever restores the snapshot a second time over writes accepted after the
-- read-only window lifted. Until now that record was a TEXT PREFIX on `error`
-- ("ROLLBACK_FINISH_PENDING: ..."), parsed by Go at every reader. A prefix is a
-- decision the schema cannot see: a row could claim to be cleanup-only without
-- a retained snapshot, and a typo at one reader would silently route a healthy
-- box back through a destructive restore.
--
-- The column makes the invalid shape unwritable: rollback_finish_pending_at may
-- be set ONLY on a `failed` row (chk_upgrade_state_attributes already forces
-- rolled_back_at IS NULL there). Same pattern as chk_upgrade_parked_requires_in_progress.
-- It deliberately does NOT require backup_path: a PreSwap rollback (nothing
-- moved, no snapshot) finishes through the same cleanup-only tail, and the
-- install ladder's restore replay already keys on backup_path IS NOT NULL, so a
-- NULL-backup_path pending row can never be mistaken for a replayable restore.
BEGIN;

ALTER TABLE public.upgrade
    ADD COLUMN rollback_finish_pending_at timestamp with time zone;

COMMENT ON COLUMN public.upgrade.rollback_finish_pending_at IS
  'STATBUS-347: set the instant a rollback''s snapshot restore and service health were confirmed, BEFORE its read-only window and maintenance are lifted. While set, the row is cleanup-only: the marker still needs removing and the row still needs the final rolled_back transition, but the snapshot must NEVER be restored again (writes accepted after the lift would be overwritten). Cleared by the same transaction that writes rolled_back. Only ever set on a failed row; backup_path may be NULL for a PreSwap (nothing-moved) rollback.';

ALTER TABLE public.upgrade
    ADD CONSTRAINT chk_upgrade_rollback_finish_pending_requires_failed CHECK (
        rollback_finish_pending_at IS NULL OR state = 'failed'
    );

-- Forward repair of any row written under the text-prefix contract (a box that
-- upgraded through a rollback between rc.12 and this migration). The prefix
-- rows are exactly the cleanup-only shape; carry them into the column and
-- strip the prefix so `error` is once again only the human cause. Rows that
-- do not match are untouched. The count is reported, never assumed.
DO $$
DECLARE
  _repaired integer;
BEGIN
  UPDATE public.upgrade
     SET rollback_finish_pending_at = COALESCE(rollback_finish_pending_at, clock_timestamp()),
         error = substr(error, length('ROLLBACK_FINISH_PENDING: ') + 1)
   WHERE state = 'failed'
     AND error LIKE 'ROLLBACK_FINISH_PENDING: %';
  GET DIAGNOSTICS _repaired = ROW_COUNT;
  RAISE NOTICE 'STATBUS-347: % legacy ROLLBACK_FINISH_PENDING row(s) carried into rollback_finish_pending_at', _repaired;
END $$;

-- The audit trail must see the transition (STATBUS-154's log fires on state or
-- park changes; this is a third held sub-state and it is just as load-bearing).
ALTER TABLE public.upgrade_state_log
    ADD COLUMN old_rollback_finish_pending_at timestamp with time zone,
    ADD COLUMN new_rollback_finish_pending_at timestamp with time zone;

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
    application_name, query, backend_pid, logged_at, actor, actor_source,
    old_error, old_log_relative_file_path, old_backup_path,
    old_recovery_parked_reason, old_recovery_attempts,
    old_rollback_finish_pending_at, new_rollback_finish_pending_at)
  VALUES (
    NEW.id, OLD.state, NEW.state, OLD.recovery_parked_at, NEW.recovery_parked_at,
    current_setting('application_name', true), current_query(),
    pg_backend_pid(), clock_timestamp(), v_actor, v_actor_source,
    OLD.error, OLD.log_relative_file_path, OLD.backup_path,
    OLD.recovery_parked_reason, OLD.recovery_attempts,
    OLD.rollback_finish_pending_at, NEW.rollback_finish_pending_at);
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS upgrade_state_log_trigger ON public.upgrade;
CREATE TRIGGER upgrade_state_log_trigger
    AFTER UPDATE ON public.upgrade
    FOR EACH ROW
    WHEN (OLD.state IS DISTINCT FROM NEW.state
          OR OLD.recovery_parked_at IS DISTINCT FROM NEW.recovery_parked_at
          OR OLD.rollback_finish_pending_at IS DISTINCT FROM NEW.rollback_finish_pending_at)
    EXECUTE FUNCTION public.upgrade_state_log_capture();

END;
