BEGIN;

SET client_min_messages TO debug1;

CREATE TABLE public.statistical_history AS
SELECT * FROM public.statistical_history_def
ORDER BY year, month;

CREATE UNIQUE INDEX "statistical_history_month_key"
    ON public.statistical_history
    ( resolution
    , year
    , month
    , unit_type
    ) WHERE resolution = 'year-month'::public.history_resolution;
CREATE UNIQUE INDEX "statistical_history_year_key"
    ON public.statistical_history
    ( resolution
    , year
    , unit_type
    ) WHERE resolution = 'year'::public.history_resolution;

CREATE INDEX idx_history_resolution ON public.statistical_history (resolution);
CREATE INDEX idx_statistical_history_year ON public.statistical_history (year);
CREATE INDEX idx_statistical_history_month ON public.statistical_history (month);
CREATE INDEX idx_statistical_history_births ON public.statistical_history (births);
CREATE INDEX idx_statistical_history_deaths ON public.statistical_history (deaths);
CREATE INDEX idx_statistical_history_count ON public.statistical_history (count);
CREATE INDEX idx_statistical_history_stats_summary ON public.statistical_history USING GIN (stats_summary jsonb_path_ops);

CREATE FUNCTION public.statistical_history_derive(
  valid_after date DEFAULT '-infinity'::date,
  valid_to date DEFAULT 'infinity'::date
)
RETURNS void
LANGUAGE plpgsql
AS $statistical_history_derive$
DECLARE
    v_period RECORD;
    v_unit_type public.statistical_unit_type;
    v_curr_start date;
    v_curr_stop date;
    v_prev_start date;
    v_prev_stop date;
BEGIN
    -- Use a staging table for performance and to minimize lock duration.
    CREATE TEMP TABLE statistical_history_new (LIKE public.statistical_history) ON COMMIT DROP;

    -- Loop through each period (year and year-month) and calculate history individually.
    FOR v_period IN
        SELECT *
        FROM public.get_statistical_history_periods(
            p_resolution := null::public.history_resolution,
            p_valid_after := statistical_history_derive.valid_after,
            p_valid_to := statistical_history_derive.valid_to
        )
    LOOP
        -- Manually calculate the date ranges for the current and previous periods.
        IF v_period.resolution = 'year'::public.history_resolution THEN
            v_curr_start := make_date(v_period.year, 1, 1);
            v_curr_stop  := make_date(v_period.year, 12, 31);
            v_prev_start := make_date(v_period.year - 1, 1, 1);
            v_prev_stop  := make_date(v_period.year - 1, 12, 31);
        ELSE -- 'year-month'
            v_curr_start := make_date(v_period.year, v_period.month, 1);
            v_curr_stop  := (v_curr_start + interval '1 month') - interval '1 day';
            v_prev_stop  := v_curr_start - interval '1 day';
            v_prev_start := date_trunc('month', v_prev_stop)::date;
        END IF;

        FOREACH v_unit_type IN ARRAY ARRAY['enterprise', 'legal_unit', 'establishment']::public.statistical_unit_type[]
        LOOP
            INSERT INTO statistical_history_new
            WITH
            units_in_period AS (
                SELECT *
                FROM public.statistical_unit su
                WHERE su.unit_type = v_unit_type
                  AND su.include_unit_in_reports
                  AND (
                      (su.valid_from <= v_curr_stop AND su.valid_to >= v_curr_start) OR
                      (su.valid_from <= v_prev_stop AND su.valid_to >= v_prev_start)
                  )
            ),
            latest_versions_curr AS (
                SELECT DISTINCT ON (unit_id) *
                FROM units_in_period
                WHERE valid_from <= v_curr_stop
                ORDER BY unit_id, valid_from DESC, valid_to DESC
            ),
            units_at_end_of_curr AS (
                SELECT * FROM latest_versions_curr
                WHERE valid_to >= v_curr_stop
                  AND COALESCE(birth_date, valid_from) <= v_curr_stop
                  AND (death_date IS NULL OR death_date > v_curr_stop)
            ),
            latest_versions_prev AS (
                SELECT DISTINCT ON (unit_id) *
                FROM units_in_period
                WHERE valid_from <= v_prev_stop
                ORDER BY unit_id, valid_from DESC, valid_to DESC
            ),
            units_at_end_of_prev AS (
                SELECT * FROM latest_versions_prev
                WHERE valid_to >= v_prev_stop
                  AND COALESCE(birth_date, valid_from) <= v_prev_stop
                  AND (death_date IS NULL OR death_date > v_prev_stop)
            ),
            metrics AS (
                SELECT
                    (SELECT count(*) FROM units_at_end_of_curr) AS count,
                    (SELECT count(*) FROM units_at_end_of_curr curr WHERE NOT EXISTS (SELECT 1 FROM units_at_end_of_prev prev WHERE prev.unit_id = curr.unit_id)) AS births,
                    (SELECT count(*) FROM units_at_end_of_prev prev WHERE NOT EXISTS (SELECT 1 FROM units_at_end_of_curr curr WHERE curr.unit_id = prev.unit_id)) AS deaths,
                    (SELECT count(*) FROM units_at_end_of_curr c JOIN units_at_end_of_prev p ON c.unit_id = p.unit_id WHERE c.name IS DISTINCT FROM p.name) AS name_change_count,
                    (SELECT count(*) FROM units_at_end_of_curr c JOIN units_at_end_of_prev p ON c.unit_id = p.unit_id WHERE c.primary_activity_category_path IS DISTINCT FROM p.primary_activity_category_path) AS primary_activity_category_change_count,
                    (SELECT count(*) FROM units_at_end_of_curr c JOIN units_at_end_of_prev p ON c.unit_id = p.unit_id WHERE c.secondary_activity_category_path IS DISTINCT FROM p.secondary_activity_category_path) AS secondary_activity_category_change_count,
                    (SELECT count(*) FROM units_at_end_of_curr c JOIN units_at_end_of_prev p ON c.unit_id = p.unit_id WHERE c.sector_path IS DISTINCT FROM p.sector_path) AS sector_change_count,
                    (SELECT count(*) FROM units_at_end_of_curr c JOIN units_at_end_of_prev p ON c.unit_id = p.unit_id WHERE c.legal_form_id IS DISTINCT FROM p.legal_form_id) AS legal_form_change_count,
                    (SELECT count(*) FROM units_at_end_of_curr c JOIN units_at_end_of_prev p ON c.unit_id = p.unit_id WHERE c.physical_region_path IS DISTINCT FROM p.physical_region_path) AS physical_region_change_count,
                    (SELECT count(*) FROM units_at_end_of_curr c JOIN units_at_end_of_prev p ON c.unit_id = p.unit_id WHERE c.physical_country_id IS DISTINCT FROM p.physical_country_id) AS physical_country_change_count,
                    (SELECT count(*) FROM units_at_end_of_curr c JOIN units_at_end_of_prev p ON c.unit_id = p.unit_id WHERE (c.physical_address_part1, c.physical_address_part2, c.physical_address_part3, c.physical_postcode, c.physical_postplace) IS DISTINCT FROM (p.physical_address_part1, p.physical_address_part2, p.physical_address_part3, p.physical_postcode, p.physical_postplace)) AS physical_address_change_count,
                    '{}'::jsonb AS stats_summary
            )
            SELECT
                v_period.resolution, v_period.year, v_period.month, v_unit_type,
                m.count, m.births, m.deaths, m.name_change_count, m.primary_activity_category_change_count,
                m.secondary_activity_category_change_count, m.sector_change_count, m.legal_form_change_count,
                m.physical_region_change_count, m.physical_country_change_count, m.physical_address_change_count,
                m.stats_summary
            FROM metrics m;
        END LOOP;
    END LOOP;

    -- Atomically swap the data.
    DELETE FROM public.statistical_history;
    INSERT INTO public.statistical_history SELECT * FROM statistical_history_new;
END;
$statistical_history_derive$;

END;
