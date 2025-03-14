BEGIN;

CREATE OR REPLACE FUNCTION public.statistical_unit_refresh_now()
RETURNS TABLE(view_name text, refresh_time_ms numeric) AS $$
DECLARE
    name text;
    start_at TIMESTAMPTZ;
    stop_at TIMESTAMPTZ;
    duration_ms numeric(18,3);
    materialized_views text[] := ARRAY
        [ 'statistical_unit'
        , 'activity_category_used'
        , 'region_used'
        , 'sector_used'
        , 'data_source_used'
        , 'legal_form_used'
        , 'country_used'
        , 'statistical_unit_facet'
        , 'statistical_history'
        , 'statistical_history_facet'
        ];
BEGIN
    FOREACH name IN ARRAY materialized_views LOOP
        SELECT clock_timestamp() INTO start_at;

        EXECUTE format('REFRESH MATERIALIZED VIEW public.%I', name);

        SELECT clock_timestamp() INTO stop_at;
        duration_ms := EXTRACT(EPOCH FROM (stop_at - start_at)) * 1000;

        -- Set the function's returning columns
        view_name := name;
        refresh_time_ms := duration_ms;

        RETURN NEXT;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

SELECT public.statistical_unit_refresh_now();

END;
