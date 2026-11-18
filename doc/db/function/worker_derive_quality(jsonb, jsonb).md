```sql
CREATE OR REPLACE PROCEDURE worker.derive_quality(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
BEGIN
    PERFORM public.quality_establishment_activity_differs_derive();

    p_info := jsonb_build_object('checks', jsonb_build_array(
        'quality_establishment_activity_differs'
    ));
END;
$procedure$
```
