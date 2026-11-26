```sql
CREATE OR REPLACE PROCEDURE worker.derive_quality(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
BEGIN
    PERFORM public.quality_finding_derive();

    p_info := (
        SELECT jsonb_build_object('findings', jsonb_object_agg(f.rule, f.findings))
        FROM (SELECT qf.rule, count(*) AS findings FROM public.quality_finding AS qf GROUP BY qf.rule) AS f
    );
END;
$procedure$
```
