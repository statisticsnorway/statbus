```sql
CREATE OR REPLACE FUNCTION public.is_deriving_reports()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    SELECT jsonb_build_object(
        'active', EXISTS (
            SELECT 1 FROM worker.tasks
            WHERE command IN ('derive_reports_phase', 'derive_reports', 'derive_statistical_history', 'derive_statistical_history_period',
                            'statistical_history_reduce', 'derive_statistical_unit_facet',
                            'derive_statistical_unit_facet_partition', 'statistical_unit_facet_reduce',
                            'derive_statistical_history_facet', 'derive_statistical_history_facet_period',
                            'statistical_history_facet_reduce')
              AND state IN ('pending', 'processing', 'waiting')
        ),
        'step', (
            SELECT t.command FROM worker.tasks AS t
            WHERE t.command IN ('derive_reports_phase', 'derive_reports', 'derive_statistical_history',
                               'statistical_history_reduce', 'derive_statistical_unit_facet',
                               'statistical_unit_facet_reduce', 'derive_statistical_history_facet',
                               'statistical_history_facet_reduce')
              AND t.state IN ('processing', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        ),
        'total', COALESCE((
            SELECT count(*) FROM worker.tasks AS t
            WHERE EXISTS (
                  SELECT 1 FROM worker.tasks AS p
                  WHERE p.id = t.parent_id
                    AND p.state IN ('processing', 'waiting')
                    AND p.command IN ('derive_statistical_history', 'derive_statistical_unit_facet',
                                    'derive_statistical_history_facet')
              )
        ), 0),
        'completed', COALESCE((
            SELECT count(*) FROM worker.tasks AS t
            WHERE t.state IN ('completed', 'failed')
              AND EXISTS (
                  SELECT 1 FROM worker.tasks AS p
                  WHERE p.id = t.parent_id
                    AND p.state IN ('processing', 'waiting')
                    AND p.command IN ('derive_statistical_history', 'derive_statistical_unit_facet',
                                    'derive_statistical_history_facet')
              )
        ), 0),
        'effective_establishment_count', (
            SELECT (t.info->>'effective_establishment_count')::int
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('completed', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        ),
        'effective_legal_unit_count', (
            SELECT (t.info->>'effective_legal_unit_count')::int
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('completed', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        ),
        'effective_enterprise_count', (
            SELECT (t.info->>'effective_enterprise_count')::int
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('completed', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        ),
        'effective_power_group_count', (
            SELECT (t.info->>'effective_power_group_count')::int
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('completed', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        )
    );
$function$
```
