```sql
CREATE OR REPLACE PROCEDURE public.quality_check_catalogue_cleanup()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    -- A deleted variable's checks went with it (ON DELETE CASCADE); a variable that is no longer
    -- summed loses its checks here.
    DELETE FROM public.quality_check_catalogue AS qc
    USING public.stat_definition AS sd
    WHERE qc.stat_definition_id = sd.id
      AND sd.type NOT IN ('int', 'float');
END;
$procedure$
```
