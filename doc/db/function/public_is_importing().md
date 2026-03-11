```sql
CREATE OR REPLACE FUNCTION public.is_importing()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  SELECT jsonb_build_object(
    'active', EXISTS (
      SELECT 1 FROM public.import_job
      WHERE state IN ('preparing_data', 'analysing_data', 'processing_data', 'waiting_for_review')
    ),
    'needs_review', EXISTS (
      SELECT 1 FROM public.import_job
      WHERE state = 'waiting_for_review'
    ),
    'jobs', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'id', ij.id,
        'state', ij.state,
        'total_rows', ij.total_rows,
        'imported_rows', ij.imported_rows,
        'analysis_completed_pct', ij.analysis_completed_pct,
        'import_completed_pct', ij.import_completed_pct
      )) FROM public.import_job AS ij
      WHERE ij.state IN ('preparing_data', 'analysing_data', 'processing_data', 'waiting_for_review')),
      '[]'::jsonb
    )
  );
$function$
```
