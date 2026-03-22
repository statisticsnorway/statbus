```sql
CREATE OR REPLACE FUNCTION public.set_report_partition_seq()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.report_partition_seq := public.report_partition_seq(NEW.unit_type, NEW.unit_id);
    RETURN NEW;
END;
$function$
```
