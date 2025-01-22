BEGIN;

DROP AGGREGATE public.jsonb_stats_to_summary_agg(jsonb);
DROP FUNCTION public.jsonb_stats_to_summary(jsonb,jsonb);
DROP FUNCTION public.jsonb_stats_to_summary_round(jsonb);

END;
