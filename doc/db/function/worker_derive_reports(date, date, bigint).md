```sql
CREATE OR REPLACE FUNCTION worker.derive_reports(p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_round_priority_base bigint DEFAULT NULL::bigint)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    PERFORM pg_notify('worker_status',
        json_build_object('type', 'is_deriving_reports', 'status', true)::text);

    CALL admin.adjust_analytics_partition_count();

    PERFORM worker.enqueue_derive_statistical_history(
        p_valid_from => p_valid_from,
        p_valid_until => p_valid_until,
        p_round_priority_base => p_round_priority_base
    );
END;
$function$
```
