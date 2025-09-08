BEGIN;

CREATE TABLE public.statistical_history_facet AS
SELECT * FROM public.statistical_history_facet_def
ORDER BY year, month;

CREATE FUNCTION public.statistical_history_facet_derive(
  valid_after date DEFAULT '-infinity'::date,
  valid_to date DEFAULT 'infinity'::date
)
RETURNS void
LANGUAGE plpgsql
AS $statistical_history_facet_derive$
DECLARE
    v_period RECORD;
    v_unit_type public.statistical_unit_type;
    v_curr_start date;
    v_curr_stop date;
    v_prev_start date;
    v_prev_stop date;
BEGIN
    RAISE DEBUG 'Running statistical_history_facet_derive(valid_after=%, valid_to=%)', valid_after, valid_to;

    CREATE TEMPORARY TABLE temp_periods ON COMMIT DROP AS
    SELECT *
    FROM public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution,
        p_valid_after := statistical_history_facet_derive.valid_after,
        p_valid_to := statistical_history_facet_derive.valid_to
    );

    DELETE FROM public.statistical_history_facet shf
    USING temp_periods tp
    WHERE shf.year = tp.year
      AND shf.resolution = tp.resolution
      AND shf.month IS NOT DISTINCT FROM tp.month;

    FOR v_period IN SELECT * FROM temp_periods LOOP
        IF v_period.resolution = 'year'::public.history_resolution THEN
            v_curr_start := make_date(v_period.year, 1, 1);
            v_curr_stop  := make_date(v_period.year, 12, 31);
            v_prev_start := make_date(v_period.year - 1, 1, 1);
            v_prev_stop  := make_date(v_period.year - 1, 12, 31);
        ELSE
            v_curr_start := make_date(v_period.year, v_period.month, 1);
            v_curr_stop  := (v_curr_start + interval '1 month') - interval '1 day';
            v_prev_stop  := v_curr_start - interval '1 day';
            v_prev_start := date_trunc('month', v_prev_stop)::date;
        END IF;

        RAISE NOTICE 'Processing facets for period: resolution=%, year=%, month=%', v_period.resolution, v_period.year, v_period.month;

        FOREACH v_unit_type IN ARRAY ARRAY['enterprise', 'legal_unit', 'establishment']::public.statistical_unit_type[]
        LOOP
            RAISE NOTICE '  -> Processing unit_type=%', v_unit_type;

            CREATE TEMP TABLE changed_units (
                unit_id INT, unit_type public.statistical_unit_type,
                curr public.statistical_unit, prev public.statistical_unit
            ) ON COMMIT DROP;

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
            )
            INSERT INTO changed_units
            SELECT
                COALESCE(c.unit_id, p.unit_id),
                COALESCE(c.unit_type, p.unit_type),
                c::public.statistical_unit, p::public.statistical_unit
            FROM units_at_end_of_curr c
            FULL JOIN units_at_end_of_prev p ON c.unit_id = p.unit_id AND c.unit_type = p.unit_type;

            INSERT INTO public.statistical_history_facet
            SELECT
                v_period.resolution, v_period.year, v_period.month,
                unit_type,
                (curr).primary_activity_category_path,
                (curr).secondary_activity_category_path,
                (curr).sector_path,
                (curr).legal_form_id,
                (curr).physical_region_path,
                (curr).physical_country_id,
                (curr).unit_size_id,
                (curr).status_id,
                count((curr).unit_id) AS count,
                count((curr).unit_id) FILTER (WHERE (prev).unit_id IS NULL) AS births,
                count((prev).unit_id) FILTER (WHERE (curr).unit_id IS NULL) AS deaths,
                count(*) FILTER (WHERE (curr).name IS DISTINCT FROM (prev).name) AS name_change_count,
                count(*) FILTER (WHERE (curr).primary_activity_category_path IS DISTINCT FROM (prev).primary_activity_category_path) AS primary_activity_category_change_count,
                count(*) FILTER (WHERE (curr).secondary_activity_category_path IS DISTINCT FROM (prev).secondary_activity_category_path) AS secondary_activity_category_change_count,
                count(*) FILTER (WHERE (curr).sector_path IS DISTINCT FROM (prev).sector_path) AS sector_change_count,
                count(*) FILTER (WHERE (curr).legal_form_id IS DISTINCT FROM (prev).legal_form_id) AS legal_form_change_count,
                count(*) FILTER (WHERE (curr).physical_region_path IS DISTINCT FROM (prev).physical_region_path) AS physical_region_change_count,
                count(*) FILTER (WHERE (curr).physical_country_id IS DISTINCT FROM (prev).physical_country_id) AS physical_country_change_count,
                count(*) FILTER (WHERE ((curr).physical_address_part1, (curr).physical_address_part2, (curr).physical_address_part3, (curr).physical_postcode, (curr).physical_postplace) IS DISTINCT FROM ((prev).physical_address_part1, (prev).physical_address_part2, (prev).physical_address_part3, (prev).physical_postcode, (prev).physical_postplace)) AS physical_address_change_count,
                count(*) FILTER (WHERE (curr).unit_size_id IS DISTINCT FROM (prev).unit_size_id) AS unit_size_change_count,
                count(*) FILTER (WHERE (curr).status_id IS DISTINCT FROM (prev).status_id) AS status_change_count,
                '{}'::jsonb AS stats_summary
            FROM changed_units
            GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12;

            DROP TABLE changed_units;
        END LOOP;
    END LOOP;
END;
$statistical_history_facet_derive$;

END;
