BEGIN;

DROP AGGREGATE public.jsonb_stats_summary_merge_agg(jsonb);
DROP FUNCTION public.jsonb_stats_summary_merge(jsonb,jsonb);

END;
