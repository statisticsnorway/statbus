BEGIN;

ALTER TABLE public.upgrade
ADD COLUMN claim_token uuid;

CREATE FUNCTION public.upgrade_transition_actor_present()
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public, auth, pg_temp
AS $upgrade_transition_actor_present$
  SELECT auth.uid() IS NOT NULL
      OR NULLIF(current_setting('statbus.actor', true), '') IS NOT NULL;
$upgrade_transition_actor_present$;

CREATE FUNCTION public.upgrade_guard_operator_transitions()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, auth, pg_temp
AS $upgrade_guard_operator_transitions$
DECLARE
  _actor_present boolean := public.upgrade_transition_actor_present();
  _leaves_park boolean := OLD.state = 'in_progress'
      AND OLD.recovery_parked_at IS NOT NULL
      AND (NEW.state IS DISTINCT FROM 'in_progress'
           OR NEW.recovery_parked_at IS NULL);
BEGIN
  IF OLD.state = 'in_progress'
     AND OLD.recovery_parked_at IS NULL
     AND NEW.state = 'dismissed' THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'cannot dismiss a live unparked in_progress upgrade';
  END IF;

  IF NEW.state = 'dismissed'
     AND OLD.state NOT IN ('available', 'scheduled', 'failed', 'rolled_back')
     AND NOT (OLD.state = 'in_progress' AND OLD.recovery_parked_at IS NOT NULL) THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = format('cannot dismiss upgrade from state %s', OLD.state);
  END IF;

  IF ((OLD.state = 'dismissed' AND NEW.state IS DISTINCT FROM 'dismissed')
      OR (OLD.state = 'failed' AND NEW.state IS DISTINCT FROM 'failed')
      OR _leaves_park)
     AND NOT _actor_present THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = format('operator actor required to leave upgrade state %s',
                       CASE WHEN _leaves_park THEN 'parked' ELSE OLD.state::text END);
  END IF;

  RETURN NEW;
END;
$upgrade_guard_operator_transitions$;

CREATE TRIGGER upgrade_guard_operator_transitions_trigger
BEFORE UPDATE ON public.upgrade
FOR EACH ROW
EXECUTE FUNCTION public.upgrade_guard_operator_transitions();

CREATE OR REPLACE PROCEDURE public.upgrade_supersede_older(IN p_commit_sha text, INOUT p_superseded integer DEFAULT 0)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $upgrade_supersede_older$
DECLARE
    _committed  timestamptz;
    _status     public.release_status_type;
    _version_key integer[];
BEGIN
    SELECT committed_at, release_status, public.upgrade_version_key(commit_version)
      INTO _committed, _status, _version_key
      FROM public.upgrade
     WHERE commit_sha = p_commit_sha
     LIMIT 1;

    IF NOT FOUND THEN
        RAISE NOTICE 'upgrade_supersede_older: no row for commit_sha=%', p_commit_sha;
        RETURN;
    END IF;

    WITH superseded AS (
        UPDATE public.upgrade AS u SET
            state = 'superseded',
            superseded_at = COALESCE(u.superseded_at, now())
         WHERE u.state IN ('available', 'scheduled', 'failed', 'rolled_back')
           AND (u.state <> 'failed' OR public.upgrade_transition_actor_present())
           AND u.commit_sha != p_commit_sha
           AND (
               u.release_status < _status
               OR (
                   u.release_status = _status
                   AND CASE
                       WHEN _version_key IS NOT NULL
                        AND public.upgrade_version_key(u.commit_version) IS NOT NULL
                       THEN (public.upgrade_version_key(u.commit_version), u.committed_at)
                          < (_version_key, _committed)
                       ELSE u.committed_at < _committed
                   END
               )
           )
        RETURNING u.id
    )
    SELECT count(*) INTO p_superseded FROM superseded;

    IF p_superseded > 0 THEN
        RAISE NOTICE 'upgrade_supersede_older: superseded % row(s) older than % (status=%)',
            p_superseded, p_commit_sha, _status;
    END IF;
END;
$upgrade_supersede_older$;

CREATE OR REPLACE FUNCTION public.upgrade_schedule(p_commit_sha text, p_recreate boolean DEFAULT false)
 RETURNS TABLE(schedule_result text, upgrade_id integer, landed_state upgrade_state, superseded_count integer)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
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

    IF (v_target.state IN ('dismissed', 'failed')
        OR (v_target.state = 'in_progress' AND v_target.recovery_parked_at IS NOT NULL))
       AND NOT public.upgrade_transition_actor_present() THEN
        RAISE EXCEPTION USING
          ERRCODE = '42501',
          MESSAGE = format('operator actor required to schedule upgrade from state %s',
                           CASE
                             WHEN v_target.state = 'in_progress' THEN 'parked'
                             ELSE v_target.state::text
                           END);
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
               recovery_parked_reason = NULL,
               claim_token = NULL
         WHERE u.id = v_target.id
           AND (u.state <> 'in_progress' OR u.recovery_parked_at IS NOT NULL)
        RETURNING u.state INTO v_landed_state;

        IF v_landed_state = 'superseded' THEN
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

COMMIT;
