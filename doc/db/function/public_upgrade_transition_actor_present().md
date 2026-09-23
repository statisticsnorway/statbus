```sql
CREATE OR REPLACE FUNCTION public.upgrade_transition_actor_present()
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
  SELECT auth.uid() IS NOT NULL
      OR NULLIF(current_setting('statbus.actor', true), '') IS NOT NULL;
$function$
```
