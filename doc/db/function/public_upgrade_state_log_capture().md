```sql
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
$function$
```
