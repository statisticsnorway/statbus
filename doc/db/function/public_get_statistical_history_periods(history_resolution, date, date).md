```sql
CREATE OR REPLACE FUNCTION public.get_statistical_history_periods(p_resolution history_resolution DEFAULT NULL::history_resolution, p_valid_after date DEFAULT NULL::date, p_valid_to date DEFAULT NULL::date)
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
  BEGIN
    -- Initialize with parameters or defaults
    v_start_year := CASE 
      WHEN p_valid_after IS NULL OR p_valid_after = '-infinity'::date THEN NULL
      ELSE p_valid_after
    END;
    
    v_stop_year := CASE
      WHEN p_valid_to IS NULL OR p_valid_to = 'infinity'::date THEN NULL
      ELSE p_valid_to
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
$function$
```
