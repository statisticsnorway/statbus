```sql
CREATE OR REPLACE FUNCTION admin.propagate_partition_count_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'admin', 'pg_temp'
AS $function$
BEGIN
    IF NEW.analytics_partition_count IS DISTINCT FROM OLD.analytics_partition_count THEN
        RAISE LOG 'propagate_partition_count_change: % → % partitions',
            OLD.analytics_partition_count, NEW.analytics_partition_count;

        -- Recompute all partition assignments
        UPDATE public.statistical_unit
        SET report_partition_seq = public.report_partition_seq(
            unit_type, unit_id, NEW.analytics_partition_count
        );

        -- Clear derived partition data (force full refresh)
        TRUNCATE public.statistical_unit_facet_staging;
        TRUNCATE public.statistical_history_facet_partitions;
        DELETE FROM public.statistical_history WHERE partition_seq IS NOT NULL;
        TRUNCATE public.statistical_unit_facet_dirty_partitions;
    END IF;
    RETURN NEW;
END;
$function$
```
