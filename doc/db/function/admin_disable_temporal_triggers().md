```sql
CREATE OR REPLACE PROCEDURE admin.disable_temporal_triggers()
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'admin', 'pg_temp'
AS $procedure$
BEGIN
    CALL sql_saga.disable_temporal_triggers(
        'public.legal_unit'::regclass, 'public.establishment'::regclass, 'public.activity'::regclass, 'public.location'::regclass,
        'public.contact'::regclass, 'public.stat_for_unit'::regclass, 'public.person_for_unit'::regclass
    );
END;
$procedure$
```
