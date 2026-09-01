-- Migration 20260901212308: statbus_333_upgrade_schedule_one_door
BEGIN;

ALTER TABLE public.upgrade_state_log
    ADD COLUMN old_error text,
    ADD COLUMN old_log_relative_file_path text,
    ADD COLUMN old_backup_path text,
    ADD COLUMN old_recovery_parked_reason text,
    ADD COLUMN old_recovery_attempts integer;

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
    old_recovery_parked_reason, old_recovery_attempts)
  VALUES (
    NEW.id, OLD.state, NEW.state, OLD.recovery_parked_at, NEW.recovery_parked_at,
    current_setting('application_name', true), current_query(),
    pg_backend_pid(), clock_timestamp(), v_actor, v_actor_source,
    OLD.error, OLD.log_relative_file_path, OLD.backup_path,
    OLD.recovery_parked_reason, OLD.recovery_attempts);
  RETURN NEW;
END;
$function$
;

CREATE FUNCTION public.upgrade_schedule(
    p_commit_sha text,
    p_recreate boolean DEFAULT false
)
RETURNS TABLE (
    schedule_result text,
    upgrade_id integer,
    landed_state public.upgrade_state,
    superseded_count integer
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $upgrade_schedule$
DECLARE
    v_target public.upgrade%ROWTYPE;
    v_landed_state public.upgrade_state;
    v_superseded_count integer := 0;
BEGIN
    SELECT u.*
      INTO v_target
      FROM public.upgrade AS u
     WHERE u.commit_sha = p_commit_sha
       FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY
        SELECT 'unregistered'::text, NULL::integer, NULL::public.upgrade_state, 0;
        RETURN;
    END IF;

    IF v_target.state = 'in_progress' AND v_target.recovery_parked_at IS NULL THEN
        RETURN QUERY
        SELECT 'in_progress'::text, v_target.id, v_target.state, 0;
        RETURN;
    END IF;

    IF v_target.state = 'failed' AND v_target.backup_path IS NOT NULL THEN
        RETURN QUERY
        SELECT 'restore_reattempt_required'::text, v_target.id, v_target.state, 0;
        RETURN;
    END IF;

    IF v_target.state = 'scheduled' THEN
        CALL public.upgrade_supersede_older(p_commit_sha, v_superseded_count);
        RETURN QUERY
        SELECT 'already_scheduled'::text, v_target.id, v_target.state, v_superseded_count;
        RETURN;
    END IF;

    BEGIN
        CALL public.upgrade_supersede_older(p_commit_sha, v_superseded_count);

        UPDATE public.upgrade AS u
           SET state = 'scheduled',
               recreate = p_recreate,
               scheduled_at = now(),
               started_at = NULL,
               completed_at = NULL,
               error = NULL,
               rolled_back_at = NULL,
               skipped_at = NULL,
               dismissed_at = NULL,
               superseded_at = NULL,
               log_relative_file_path = NULL,
               backup_path = NULL,
               recovery_attempts = 0,
               recovery_parked_at = NULL,
               recovery_parked_reason = NULL
         WHERE u.id = v_target.id
           AND (u.state <> 'in_progress' OR u.recovery_parked_at IS NOT NULL)
        RETURNING u.state INTO v_landed_state;

        IF v_landed_state = 'superseded' THEN
            -- tmp/statbus-333-superseded-evidence-repro.sql proved that keeping
            -- this same-state landing would clear retry evidence without adding
            -- a state-log row. Let the existing trigger remain the sole
            -- obsolescence oracle, then use this sentinel to roll back both the
            -- target reset and the older-candidate supersedes.
            RAISE EXCEPTION USING
                ERRCODE = 'P3333',
                MESSAGE = 'upgrade_schedule candidate is obsolete';
        ELSIF v_landed_state <> 'scheduled' THEN
            RAISE EXCEPTION 'upgrade_schedule landed in unexpected state: %', v_landed_state;
        END IF;
    EXCEPTION
        WHEN SQLSTATE 'P3333' THEN
            RETURN QUERY
            SELECT 'superseded'::text, v_target.id, v_target.state, 0;
            RETURN;
    END;

    RETURN QUERY
    SELECT 'scheduled'::text, v_target.id, v_landed_state, v_superseded_count;
END;
$upgrade_schedule$;

-- sql_saga_health_checks treats every GRANT/REVOKE as affecting a managed
-- temporal object and rejects unrelated existing ACL shapes. Use the established
-- privilege-statement guard from migration 20260223185108.
ALTER EVENT TRIGGER sql_saga_health_checks DISABLE;
REVOKE EXECUTE ON FUNCTION public.upgrade_schedule(text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upgrade_schedule(text, boolean) TO admin_user;
ALTER EVENT TRIGGER sql_saga_health_checks ENABLE;

COMMENT ON COLUMN public.upgrade_state_log.old_error IS
    'Error text from the upgrade row before this state or park transition.';
COMMENT ON COLUMN public.upgrade_state_log.old_log_relative_file_path IS
    'Upgrade log basename from the upgrade row before this state or park transition.';
COMMENT ON COLUMN public.upgrade_state_log.old_backup_path IS
    'Backup path recorded on the upgrade row before this state or park transition. Historical metadata only; backup contents may later change.';
COMMENT ON COLUMN public.upgrade_state_log.old_recovery_parked_reason IS
    'Recovery park reason from the upgrade row before this state or park transition.';
COMMENT ON COLUMN public.upgrade_state_log.old_recovery_attempts IS
    'Recovery attempt count from the upgrade row before this state or park transition.';

COMMENT ON FUNCTION public.upgrade_schedule(text, boolean) IS
    'The one scheduling door for UI, CLI, and service callers. Returns exactly one result: scheduled, superseded, already_scheduled, in_progress, restore_reattempt_required, or unregistered. Locks the commit row, supersedes eligible older candidates before reset, preserves retry evidence through upgrade_state_log, and rolls an obsolete superseded landing back as a no-mutation refusal.';

END;
