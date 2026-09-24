```sql
CREATE OR REPLACE FUNCTION public.upgrade_guard_operator_transitions()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  _actor_present boolean := public.upgrade_transition_actor_present();
BEGIN
  IF OLD.state = 'in_progress'
     AND OLD.recovery_parked_at IS NULL
     AND NEW.state = 'dismissed' THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'cannot dismiss a live unparked in_progress upgrade';
  END IF;

  IF OLD.state IS DISTINCT FROM NEW.state
     AND NEW.state = 'dismissed'
     AND OLD.state NOT IN ('available', 'scheduled', 'failed', 'rolled_back')
     AND NOT (OLD.state = 'in_progress' AND OLD.recovery_parked_at IS NOT NULL) THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = format('cannot dismiss upgrade from state %s', OLD.state);
  END IF;

  IF OLD.state = 'dismissed' AND NEW.state IS DISTINCT FROM 'dismissed'
     AND NOT _actor_present THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'operator actor required to leave upgrade state dismissed';
  END IF;

  RETURN NEW;
END;
$function$
```
