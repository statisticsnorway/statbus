```sql
CREATE OR REPLACE FUNCTION worker.derive_reports(p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_round_priority_base bigint DEFAULT NULL::bigint)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Auto-scale partition count based on data volume
  CALL admin.adjust_analytics_partition_count();

  -- Instead of running all phases in one transaction, enqueue the first phase.
  -- Each phase will enqueue the next one when it completes.
  PERFORM worker.enqueue_derive_statistical_history(
    p_valid_from => p_valid_from,
    p_valid_until => p_valid_until,
    p_round_priority_base := p_round_priority_base
  );
END;
$function$
```
