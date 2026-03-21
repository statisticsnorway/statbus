```sql
CREATE OR REPLACE FUNCTION public.is_deriving_statistical_units()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    SELECT jsonb_build_object(
        'active', EXISTS (
            SELECT 1 FROM worker.tasks
            WHERE command IN ('collect_changes', 'derive_units_phase', 'derive_statistical_unit', 'statistical_unit_refresh_batch', 'statistical_unit_flush_staging')
              AND state IN ('pending', 'processing', 'waiting')
        ),
        'step', (
            SELECT t.command FROM worker.tasks AS t
            WHERE t.command IN ('collect_changes', 'derive_units_phase', 'derive_statistical_unit', 'statistical_unit_refresh_batch', 'statistical_unit_flush_staging')
              AND (t.state IN ('processing', 'waiting') OR (t.command = 'collect_changes' AND t.state = 'pending'))
            ORDER BY t.id DESC LIMIT 1
        ),
        'total', COALESCE((
            SELECT count(*) FROM worker.tasks AS t
            WHERE t.command = 'statistical_unit_refresh_batch'
              AND EXISTS (
                  SELECT 1 FROM worker.tasks AS p
                  WHERE p.id = t.parent_id
                    AND p.command = 'derive_statistical_unit'
                    AND p.state IN ('processing', 'waiting')
              )
        ), 0),
        'completed', COALESCE((
            SELECT count(*) FROM worker.tasks AS t
            WHERE t.state IN ('completed', 'failed')
              AND t.command = 'statistical_unit_refresh_batch'
              AND EXISTS (
                  SELECT 1 FROM worker.tasks AS p
                  WHERE p.id = t.parent_id
                    AND p.command = 'derive_statistical_unit'
                    AND p.state IN ('processing', 'waiting')
              )
        ), 0),
        'effective_establishment_count', (
            SELECT (t.info->>'effective_establishment_count')::int
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('processing', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        ),
        'effective_legal_unit_count', (
            SELECT (t.info->>'effective_legal_unit_count')::int
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('processing', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        ),
        'effective_enterprise_count', (
            SELECT (t.info->>'effective_enterprise_count')::int
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('processing', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        ),
        'effective_power_group_count', (
            SELECT (t.info->>'effective_power_group_count')::int
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('processing', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        )
    );
$function$
```
