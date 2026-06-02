-- Down Migration 20260602070530: restore the verbatim wall-clock reads (current_date / now()).
-- Reverts the app.current_date GUC routing; objects read the real wall clock unconditionally again.
-- The 4 views are restored WITH (security_invoker=on) (pg_get_viewdef omits reloptions; must be explicit).
BEGIN;

CREATE OR REPLACE FUNCTION public.get_statistical_history_periods(p_resolution history_resolution DEFAULT NULL::history_resolution, p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date)
 RETURNS TABLE(resolution history_resolution, year integer, month integer, prev_stop date, curr_start date, curr_stop date)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_start_year date;
  v_stop_year date;
  v_min_date date;
  v_max_date date;
BEGIN
  -- Define default values once
  DECLARE
    v_default_start date := date_trunc('year', current_date - interval '10 years')::date;
    v_default_end date := current_date;
    v_p_valid_to date := p_valid_until - interval '1 day';
  BEGIN
    -- Initialize with parameters or defaults
    v_start_year := CASE 
      WHEN p_valid_from IS NULL OR p_valid_from = '-infinity'::date THEN NULL
      ELSE p_valid_from
    END;
    
    v_stop_year := CASE
      WHEN v_p_valid_to IS NULL OR v_p_valid_to = 'infinity'::date THEN NULL
      ELSE v_p_valid_to
    END;
    
    -- If either bound is NULL, query the database for actual min/max values
    IF v_start_year IS NULL OR v_stop_year IS NULL THEN
      SELECT 
        CASE 
          WHEN min(valid_from) IS NULL OR min(valid_from) = '-infinity'::date THEN v_default_start
          ELSE min(valid_from)
        END,
        CASE 
          WHEN max(valid_to) IS NULL OR max(valid_to) = 'infinity'::date THEN v_default_end
          ELSE max(valid_to)
        END
      INTO v_min_date, v_max_date
      FROM public.statistical_unit;
      
      RAISE DEBUG 'Database date bounds: min=%, max=%', v_min_date, v_max_date;
      
      -- Apply database values where parameters were NULL or infinite
      v_start_year := COALESCE(v_start_year, v_min_date);
      v_stop_year := COALESCE(v_stop_year, v_max_date);
    END IF;
    
    -- Final fallback to defaults if still NULL (empty table case)
    v_start_year := COALESCE(v_start_year, v_default_start);
    v_stop_year := COALESCE(v_stop_year, v_default_end);
    
    -- Ensure the date range is reasonable (not more than 100 years)
    IF v_stop_year::date - v_start_year::date > 36500 THEN -- 100 years * 365 days
      v_start_year := date_trunc('year', v_stop_year - interval '100 years')::date;
    END IF;
  END;
  
  -- Log the calculated date range for debugging
  RAISE DEBUG 'Using date range for periods: v_start_year=%, v_stop_year=%', v_start_year, v_stop_year;

  -- Return periods based on resolution parameter
  IF p_resolution IS NULL OR p_resolution = 'year' THEN
    RETURN QUERY
    SELECT 'year'::public.history_resolution AS resolution
         , EXTRACT(YEAR FROM series.curr_start)::INT AS year
         , NULL::INTEGER AS month
         , (series.curr_start - interval '1 day')::DATE AS prev_stop
         , series.curr_start::DATE
         , (series.curr_start + interval '1 year' - interval '1 day')::DATE AS curr_stop
    FROM generate_series(
        date_trunc('year', v_start_year)::DATE,
        date_trunc('year', v_stop_year)::DATE,
        interval '1 year'
    ) AS series(curr_start);
  END IF;

  IF p_resolution IS NULL OR p_resolution = 'year-month' THEN
    RETURN QUERY
    SELECT 'year-month'::public.history_resolution AS resolution
         , EXTRACT(YEAR FROM series.curr_start)::INT AS year
         , EXTRACT(MONTH FROM series.curr_start)::INT AS month
         , (series.curr_start - interval '1 day')::DATE AS prev_stop
         , series.curr_start::DATE
         , (series.curr_start + interval '1 month' - interval '1 day')::DATE AS curr_stop
    FROM generate_series(
        date_trunc('month', v_start_year)::DATE,
        date_trunc('month', v_stop_year)::DATE,
        interval '1 month'
    ) AS series(curr_start);
  END IF;
END;
$function$;

CREATE OR REPLACE PROCEDURE public.timesegments_years_refresh_concurrent()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_min_year int;
    v_max_year int;
    v_has_all boolean;
BEGIN
    -- Fast MIN/MAX from timesegments (uses index scan on primary key)
    SELECT MIN(EXTRACT(year FROM t.valid_from))::int,
           MAX(EXTRACT(year FROM LEAST(t.valid_until - interval '1 day', now()::date)))::int
    INTO v_min_year, v_max_year
    FROM public.timesegments AS t
    WHERE t.valid_from IS NOT NULL
      AND t.valid_until IS NOT NULL;

    -- If no timesegments exist, ensure the current year is present
    IF v_min_year IS NULL THEN
        v_min_year := EXTRACT(year FROM now())::int;
        v_max_year := v_min_year;
    END IF;

    -- Check if timesegments_years already has exactly the right years.
    -- generate_series(min, max) produces a tiny set (typically 1-10 years),
    -- and timesegments_years is equally small, so the EXCEPT is instant.
    SELECT NOT EXISTS (
        -- Years that should exist but don't
        SELECT gs.year
        FROM generate_series(v_min_year, v_max_year) AS gs(year)
        EXCEPT
        SELECT ty.year FROM public.timesegments_years AS ty
    ) AND NOT EXISTS (
        -- Years that exist but shouldn't
        SELECT ty.year FROM public.timesegments_years AS ty
        WHERE ty.year < v_min_year OR ty.year > v_max_year
    ) INTO v_has_all;

    IF v_has_all THEN
        RETURN;  -- All years match, skip expensive generate_series scan
    END IF;

    -- Fall through to full refresh using the expensive view
    -- Insert missing years (idempotent - safe for concurrent calls)
    INSERT INTO public.timesegments_years (year)
    SELECT DISTINCT year FROM public.timesegments_years_def
    ON CONFLICT (year) DO NOTHING;

    -- Delete obsolete years (safe - multiple deletes have same effect)
    DELETE FROM public.timesegments_years AS t
    WHERE NOT EXISTS (
        SELECT 1 FROM public.timesegments_years_def AS d WHERE d.year = t.year
    );
END;
$procedure$;

CREATE OR REPLACE VIEW public.timesegments_years_def WITH (security_invoker=on) AS
 SELECT DISTINCT year
   FROM ( SELECT generate_series(EXTRACT(year FROM timesegments.valid_from), EXTRACT(year FROM LEAST(timesegments.valid_until - '1 day'::interval, now()::date::timestamp without time zone)), 1::numeric)::integer AS year
           FROM timesegments
          WHERE timesegments.valid_from IS NOT NULL AND timesegments.valid_until IS NOT NULL
        UNION
         SELECT EXTRACT(year FROM now())::integer AS "extract") all_years
  ORDER BY year;;

CREATE OR REPLACE VIEW public.relative_period_with_time WITH (security_invoker=on) AS
 WITH base_periods AS (
         SELECT relative_period.id,
            relative_period.code,
            relative_period.name_when_query,
            relative_period.name_when_input,
            relative_period.scope,
            relative_period.enabled,
                CASE relative_period.code
                    WHEN 'today'::relative_period_code THEN CURRENT_DATE::timestamp with time zone
                    WHEN 'year_prev'::relative_period_code THEN date_trunc('year'::text, CURRENT_DATE::timestamp with time zone) - '1 day'::interval
                    WHEN 'year_prev_only'::relative_period_code THEN date_trunc('year'::text, CURRENT_DATE::timestamp with time zone) - '1 day'::interval
                    WHEN 'year_curr'::relative_period_code THEN CURRENT_DATE::timestamp with time zone
                    WHEN 'year_curr_only'::relative_period_code THEN CURRENT_DATE::timestamp with time zone
                    WHEN 'start_of_week_curr'::relative_period_code THEN date_trunc('week'::text, CURRENT_DATE::timestamp with time zone)
                    WHEN 'stop_of_week_prev'::relative_period_code THEN date_trunc('week'::text, CURRENT_DATE::timestamp with time zone) - '1 day'::interval
                    WHEN 'start_of_week_prev'::relative_period_code THEN date_trunc('week'::text, CURRENT_DATE - '7 days'::interval)::timestamp with time zone
                    WHEN 'start_of_month_curr'::relative_period_code THEN date_trunc('month'::text, CURRENT_DATE::timestamp with time zone)
                    WHEN 'stop_of_month_prev'::relative_period_code THEN date_trunc('month'::text, CURRENT_DATE::timestamp with time zone) - '1 day'::interval
                    WHEN 'start_of_month_prev'::relative_period_code THEN date_trunc('month'::text, CURRENT_DATE - '1 mon'::interval)::timestamp with time zone
                    WHEN 'start_of_quarter_curr'::relative_period_code THEN date_trunc('quarter'::text, CURRENT_DATE::timestamp with time zone)
                    WHEN 'stop_of_quarter_prev'::relative_period_code THEN date_trunc('quarter'::text, CURRENT_DATE::timestamp with time zone) - '1 day'::interval
                    WHEN 'start_of_quarter_prev'::relative_period_code THEN date_trunc('quarter'::text, CURRENT_DATE - '3 mons'::interval)::timestamp with time zone
                    WHEN 'start_of_semester_curr'::relative_period_code THEN
                    CASE
                        WHEN EXTRACT(month FROM CURRENT_DATE) <= 6::numeric THEN date_trunc('year'::text, CURRENT_DATE::timestamp with time zone)
                        ELSE date_trunc('year'::text, CURRENT_DATE::timestamp with time zone) + '6 mons'::interval
                    END
                    WHEN 'stop_of_semester_prev'::relative_period_code THEN
                    CASE
                        WHEN EXTRACT(month FROM CURRENT_DATE) <= 6::numeric THEN date_trunc('year'::text, CURRENT_DATE::timestamp with time zone) - '1 day'::interval
                        ELSE date_trunc('year'::text, CURRENT_DATE::timestamp with time zone) + '6 mons'::interval - '1 day'::interval
                    END
                    WHEN 'start_of_semester_prev'::relative_period_code THEN
                    CASE
                        WHEN EXTRACT(month FROM CURRENT_DATE) <= 6::numeric THEN date_trunc('year'::text, CURRENT_DATE::timestamp with time zone) - '6 mons'::interval
                        ELSE date_trunc('year'::text, CURRENT_DATE::timestamp with time zone)
                    END
                    WHEN 'start_of_year_curr'::relative_period_code THEN date_trunc('year'::text, CURRENT_DATE::timestamp with time zone)
                    WHEN 'stop_of_year_prev'::relative_period_code THEN date_trunc('year'::text, CURRENT_DATE::timestamp with time zone) - '1 day'::interval
                    WHEN 'start_of_year_prev'::relative_period_code THEN date_trunc('year'::text, CURRENT_DATE - '1 year'::interval)::timestamp with time zone
                    WHEN 'start_of_quinquennial_curr'::relative_period_code THEN date_trunc('year'::text, CURRENT_DATE - '1 year'::interval * (EXTRACT(year FROM CURRENT_DATE)::integer % 5)::double precision)::timestamp with time zone
                    WHEN 'stop_of_quinquennial_prev'::relative_period_code THEN (date_trunc('year'::text, CURRENT_DATE - '1 year'::interval * (EXTRACT(year FROM CURRENT_DATE)::integer % 5)::double precision) - '1 day'::interval)::timestamp with time zone
                    WHEN 'start_of_quinquennial_prev'::relative_period_code THEN (date_trunc('year'::text, CURRENT_DATE - '1 year'::interval * (EXTRACT(year FROM CURRENT_DATE)::integer % 5)::double precision) - '5 years'::interval)::timestamp with time zone
                    WHEN 'start_of_decade_curr'::relative_period_code THEN date_trunc('year'::text, CURRENT_DATE - '1 year'::interval * (EXTRACT(year FROM CURRENT_DATE)::integer % 10)::double precision)::timestamp with time zone
                    WHEN 'stop_of_decade_prev'::relative_period_code THEN (date_trunc('year'::text, CURRENT_DATE - '1 year'::interval * (EXTRACT(year FROM CURRENT_DATE)::integer % 10)::double precision) - '1 day'::interval)::timestamp with time zone
                    WHEN 'start_of_decade_prev'::relative_period_code THEN (date_trunc('year'::text, CURRENT_DATE - '1 year'::interval * (EXTRACT(year FROM CURRENT_DATE)::integer % 10)::double precision) - '10 years'::interval)::timestamp with time zone
                    ELSE NULL::timestamp with time zone
                END::date AS valid_on,
                CASE relative_period.code
                    WHEN 'today'::relative_period_code THEN CURRENT_DATE
                    WHEN 'year_prev'::relative_period_code THEN date_trunc('year'::text, CURRENT_DATE - '1 year'::interval)::date
                    WHEN 'year_curr'::relative_period_code THEN date_trunc('year'::text, CURRENT_DATE::timestamp with time zone)::date
                    WHEN 'year_prev_only'::relative_period_code THEN date_trunc('year'::text, CURRENT_DATE - '1 year'::interval)::date
                    WHEN 'year_curr_only'::relative_period_code THEN date_trunc('year'::text, CURRENT_DATE::timestamp with time zone)::date
                    ELSE NULL::date
                END AS valid_from,
                CASE relative_period.code
                    WHEN 'today'::relative_period_code THEN 'infinity'::date::timestamp without time zone
                    WHEN 'year_prev'::relative_period_code THEN 'infinity'::date::timestamp without time zone
                    WHEN 'year_curr'::relative_period_code THEN 'infinity'::date::timestamp without time zone
                    WHEN 'year_prev_only'::relative_period_code THEN date_trunc('year'::text, CURRENT_DATE::timestamp with time zone)::date - '1 day'::interval
                    WHEN 'year_curr_only'::relative_period_code THEN date_trunc('year'::text, CURRENT_DATE + '1 year'::interval)::date - '1 day'::interval
                    ELSE NULL::timestamp without time zone
                END::date AS valid_to
           FROM relative_period
        )
 SELECT id,
    code,
    name_when_query,
    name_when_input,
    scope,
    enabled,
    valid_on,
    valid_from,
    valid_to
   FROM base_periods;;

CREATE OR REPLACE VIEW public.time_context WITH (security_invoker=on) AS
 WITH combined_data AS (
         SELECT 'relative_period'::time_context_type AS type,
            'r_'::text || relative_period_with_time.code::character varying::text AS ident,
                CASE
                    WHEN relative_period_with_time.code = ANY (ARRAY['year_curr'::relative_period_code, 'year_curr_only'::relative_period_code]) THEN format('%s (%s)'::text, relative_period_with_time.name_when_query, EXTRACT(year FROM CURRENT_DATE))::character varying
                    WHEN relative_period_with_time.code = 'year_prev'::relative_period_code THEN format('%s (%s)'::text, relative_period_with_time.name_when_query, EXTRACT(year FROM CURRENT_DATE) - 1::numeric)::character varying
                    ELSE relative_period_with_time.name_when_query
                END AS name_when_query,
                CASE
                    WHEN relative_period_with_time.code = 'year_curr'::relative_period_code THEN format('%s (%s->)'::text, relative_period_with_time.name_when_input, EXTRACT(year FROM CURRENT_DATE))::character varying
                    WHEN relative_period_with_time.code = 'year_prev'::relative_period_code THEN format('%s (%s->)'::text, relative_period_with_time.name_when_input, EXTRACT(year FROM CURRENT_DATE) - 1::numeric)::character varying
                    WHEN relative_period_with_time.code = 'year_curr_only'::relative_period_code THEN format('%s (%s)'::text, relative_period_with_time.name_when_input, EXTRACT(year FROM CURRENT_DATE))::character varying
                    WHEN relative_period_with_time.code = 'year_prev_only'::relative_period_code THEN format('%s (%s)'::text, relative_period_with_time.name_when_input, EXTRACT(year FROM CURRENT_DATE) - 1::numeric)::character varying
                    ELSE relative_period_with_time.name_when_input
                END AS name_when_input,
            relative_period_with_time.scope,
            relative_period_with_time.valid_from,
            relative_period_with_time.valid_to,
            relative_period_with_time.valid_on,
            relative_period_with_time.code,
            NULL::ltree AS path
           FROM relative_period_with_time
          WHERE relative_period_with_time.enabled
        UNION ALL
         SELECT 'tag'::time_context_type AS type,
            't_'::text || tag.path::character varying::text AS ident,
            tag.description AS name_when_query,
            tag.description AS name_when_input,
            'input_and_query'::relative_period_scope AS scope,
            tag.context_valid_from AS valid_from,
            tag.context_valid_to AS valid_to,
            tag.context_valid_on AS valid_on,
            NULL::relative_period_code AS code,
            tag.path
           FROM tag
          WHERE tag.enabled AND tag.path IS NOT NULL AND tag.context_valid_from IS NOT NULL AND tag.context_valid_to IS NOT NULL AND tag.context_valid_on IS NOT NULL
        UNION ALL
         SELECT 'year'::time_context_type AS type,
            'y_'::text || ty.year::text AS ident,
            ty.year::text || ' (Data)'::text AS name_when_query,
            ty.year::text AS name_when_input,
            'input_and_query'::relative_period_scope AS scope,
            make_date(ty.year, 1, 1) AS valid_from,
            make_date(ty.year, 12, 31) AS valid_to,
            make_date(ty.year, 12, 31) AS valid_on,
            NULL::relative_period_code AS code,
            NULL::ltree AS path
           FROM timesegments_years ty
          WHERE ty.year <> ALL (ARRAY[EXTRACT(year FROM CURRENT_DATE)::integer, (EXTRACT(year FROM CURRENT_DATE) - 1::numeric)::integer])
        )
 SELECT type,
    ident,
    name_when_query,
    name_when_input,
    scope,
    valid_from,
    valid_to,
    valid_on,
    code,
    path
   FROM combined_data
  ORDER BY type, (
        CASE
            WHEN type = 'year'::time_context_type THEN EXTRACT(year FROM valid_from)
            ELSE NULL::numeric
        END) DESC, code, path;;

CREATE OR REPLACE VIEW public.power_group_active WITH (security_invoker=on) AS
 SELECT DISTINCT pg.id,
    pg.ident,
    pg.short_name,
    pg.name,
    pg.type_id
   FROM power_group pg
     JOIN legal_relationship lr ON lr.derived_power_group_id = pg.id
  WHERE lr.valid_range @> CURRENT_DATE;;

END;
