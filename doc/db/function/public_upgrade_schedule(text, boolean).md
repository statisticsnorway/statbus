```sql
CREATE OR REPLACE FUNCTION public.upgrade_schedule(p_commit_sha text, p_recreate boolean DEFAULT false)
 RETURNS TABLE(schedule_result text, upgrade_id integer, landed_state upgrade_state, superseded_count integer)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
$function$
```
