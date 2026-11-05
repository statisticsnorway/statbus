-- Migration 20261104130602 down: back to the dense statistical_history and statistical_history_facet tables.
-- Every definition below is the one the up migration replaced, as \sf and pg_dump -s printed it.
BEGIN;

DELETE FROM worker.pipeline_step_weight WHERE step IN ('derive_statistical_history_facet_delta', 'statistical_history_facet_delta_reduce');
DELETE FROM worker.tasks WHERE command IN ('derive_statistical_history_facet_delta', 'derive_statistical_history_facet_delta_partition', 'statistical_history_facet_delta_reduce');
DELETE FROM worker.command_registry WHERE command IN ('derive_statistical_history_facet_delta', 'derive_statistical_history_facet_delta_partition', 'statistical_history_facet_delta_reduce');
UPDATE worker.pipeline_step_weight SET seq = 2 WHERE step = 'statistical_unit_flush_staging';

DROP FUNCTION public.statistical_history_for(history_resolution, statistical_unit_type, integer);
DROP VIEW public.statistical_history;
DROP VIEW public.statistical_history_facet;
DROP PROCEDURE worker.statistical_history_facet_delta_reduce(jsonb, jsonb);
DROP PROCEDURE worker.derive_statistical_history_facet_delta(jsonb, jsonb);
DROP PROCEDURE worker.derive_statistical_history_facet_delta_partition(jsonb, jsonb);
DROP PROCEDURE worker.statistical_history_facet_delta_apply(boolean);
DROP PROCEDURE worker.statistical_history_facet_delta_remove_units(public.statistical_unit_type, integer[], regclass);
DROP PROCEDURE worker.statistical_history_facet_delta_stage_partition(int4range, boolean, regclass, regclass, bigint);
DROP PROCEDURE worker.statistical_history_facet_delta_contribution_stage(bigint);
DROP PROCEDURE worker.statistical_history_facet_delta_contribution_begin();
DROP PROCEDURE worker.statistical_history_facet_delta_contribution(regclass, smallint);
DROP FUNCTION worker.unit_ids_apply(integer[], integer[], integer[]);
DROP AGGREGATE public.int_array_sum(integer[]);
DROP FUNCTION public.int_array_add(integer[], integer[]);
DROP PROCEDURE public.statistical_history_period_refresh();
DROP TABLE public.statistical_history_period;
DROP TABLE public.statistical_history_facet_stock_delta_staging;
DROP TABLE public.statistical_history_facet_flow_delta_staging;
DROP TABLE public.statistical_history_facet_stock_delta;
DROP TABLE public.statistical_history_facet_flow_delta;
DROP TABLE worker.statistical_history_facet_delta_state;

CREATE TYPE public.statistical_history_type AS (resolution history_resolution, year integer, month integer, unit_type statistical_unit_type, exists_count integer, exists_change integer, exists_added_count integer, exists_removed_count integer, countable_count integer, countable_change integer, countable_added_count integer, countable_removed_count integer, births integer, deaths integer, name_change_count integer, primary_activity_category_change_count integer, secondary_activity_category_change_count integer, sector_change_count integer, legal_form_change_count integer, physical_region_change_count integer, physical_country_change_count integer, physical_address_change_count integer, stats_summary jsonb, hash_partition int4range);
CREATE TYPE public.statistical_history_facet_type AS (resolution history_resolution, year integer, month integer, unit_type statistical_unit_type, primary_activity_category_path ltree, secondary_activity_category_path ltree, sector_path ltree, legal_form_id integer, physical_region_path ltree, physical_country_id integer, unit_size_id integer, status_id integer, exists_count integer, exists_change integer, exists_added_count integer, exists_removed_count integer, countable_count integer, countable_change integer, countable_added_count integer, countable_removed_count integer, births integer, deaths integer, name_change_count integer, primary_activity_category_change_count integer, secondary_activity_category_change_count integer, sector_change_count integer, legal_form_change_count integer, physical_region_change_count integer, physical_country_change_count integer, physical_address_change_count integer, unit_size_change_count integer, status_change_count integer, stats_summary jsonb);

CREATE UNLOGGED TABLE public.statistical_history_facet_partitions (
    hash_slot integer NOT NULL,
    resolution public.history_resolution,
    year integer,
    month integer,
    unit_type public.statistical_unit_type,
    primary_activity_category_path public.ltree,
    secondary_activity_category_path public.ltree,
    sector_path public.ltree,
    legal_form_id integer,
    physical_region_path public.ltree,
    physical_country_id integer,
    unit_size_id integer,
    status_id integer,
    exists_count integer,
    exists_change integer,
    exists_added_count integer,
    exists_removed_count integer,
    countable_count integer,
    countable_change integer,
    countable_added_count integer,
    countable_removed_count integer,
    births integer,
    deaths integer,
    name_change_count integer,
    primary_activity_category_change_count integer,
    secondary_activity_category_change_count integer,
    sector_change_count integer,
    legal_form_change_count integer,
    physical_region_change_count integer,
    physical_country_change_count integer,
    physical_address_change_count integer,
    unit_size_change_count integer,
    status_change_count integer,
    stats_summary jsonb
);

ALTER TABLE public.statistical_history_facet_partitions OWNER TO postgres;

CREATE TABLE public.statistical_history OF public.statistical_history_type (
    CONSTRAINT statistical_history_hash_partition_is_one_slot CHECK (((hash_partition IS NULL) OR (upper(hash_partition) = (lower(hash_partition) + 1))))
);

ALTER TABLE public.statistical_history OWNER TO postgres;

COMMENT ON COLUMN public.statistical_history.hash_partition IS 'NULL marks the period total: the row the application reads. A range marks a partition slot, the partial count for units whose hash_slot falls in that range; worker.statistical_history_reduce sums the slots into the total. The row level security policies show application roles only the totals, so a reader running as the caller (statistical_history_highcharts, PostgREST) gets one row per period. Worker code running as the table owner sees the slots as well.';

COMMENT ON CONSTRAINT statistical_history_hash_partition_is_one_slot ON public.statistical_history IS 'A per-slot row (hash_partition NOT NULL) holds exactly one hash slot [s,s+1); NULL marks the reduced summary row. derive_statistical_history_period relies on this to delete a slot range by range comparison on the partition unique keys.';

CREATE TABLE public.statistical_history_facet OF public.statistical_history_facet_type;

ALTER TABLE public.statistical_history_facet OWNER TO postgres;

ALTER TABLE ONLY public.statistical_history_facet_partitions
    ADD CONSTRAINT statistical_history_facet_par_hash_slot_resolution_year_key UNIQUE NULLS NOT DISTINCT (hash_slot, resolution, year, month, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path, legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id);

CREATE INDEX idx_gist_statistical_history_facet_physical_region_path ON public.statistical_history_facet USING gist (physical_region_path);

CREATE INDEX idx_gist_statistical_history_facet_primary_activity_category_pa ON public.statistical_history_facet USING gist (primary_activity_category_path);

CREATE INDEX idx_gist_statistical_history_facet_secondary_activity_category_ ON public.statistical_history_facet USING gist (secondary_activity_category_path);

CREATE INDEX idx_gist_statistical_history_facet_sector_path ON public.statistical_history_facet USING gist (sector_path);

CREATE INDEX idx_history_resolution ON public.statistical_history USING btree (resolution) WHERE (hash_partition IS NULL);

CREATE INDEX idx_shf_partitions_hash_slot ON public.statistical_history_facet_partitions USING btree (hash_slot);

CREATE INDEX idx_statistical_history_facet_legal_form_id ON public.statistical_history_facet USING btree (legal_form_id);

CREATE INDEX idx_statistical_history_facet_month ON public.statistical_history_facet USING btree (month);

CREATE INDEX idx_statistical_history_facet_physical_country_id ON public.statistical_history_facet USING btree (physical_country_id);

CREATE INDEX idx_statistical_history_facet_physical_region_path ON public.statistical_history_facet USING btree (physical_region_path);

CREATE INDEX idx_statistical_history_facet_primary_activity_category_path ON public.statistical_history_facet USING btree (primary_activity_category_path);

CREATE INDEX idx_statistical_history_facet_secondary_activity_category_path ON public.statistical_history_facet USING btree (secondary_activity_category_path);

CREATE INDEX idx_statistical_history_facet_sector_path ON public.statistical_history_facet USING btree (sector_path);

CREATE INDEX idx_statistical_history_facet_stats_summary ON public.statistical_history_facet USING gin (stats_summary jsonb_path_ops);

CREATE INDEX idx_statistical_history_facet_unit_type ON public.statistical_history_facet USING btree (unit_type);

CREATE INDEX idx_statistical_history_facet_year ON public.statistical_history_facet USING btree (year);

CREATE INDEX idx_statistical_history_hash_partition ON public.statistical_history USING btree (hash_partition) WHERE (hash_partition IS NOT NULL);

CREATE INDEX idx_statistical_history_month ON public.statistical_history USING btree (month) WHERE (hash_partition IS NULL);

CREATE INDEX idx_statistical_history_stats_summary ON public.statistical_history USING gin (stats_summary jsonb_path_ops) WHERE (hash_partition IS NULL);

CREATE INDEX idx_statistical_history_year ON public.statistical_history USING btree (year) WHERE (hash_partition IS NULL);

CREATE UNIQUE INDEX statistical_history_facet_month_key ON public.statistical_history_facet USING btree (resolution, year, month, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path, legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id) NULLS NOT DISTINCT WHERE (resolution = 'year-month'::public.history_resolution);

CREATE UNIQUE INDEX statistical_history_facet_year_key ON public.statistical_history_facet USING btree (year, month, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path, legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id) NULLS NOT DISTINCT WHERE (resolution = 'year'::public.history_resolution);

CREATE UNIQUE INDEX statistical_history_month_key ON public.statistical_history USING btree (resolution, year, month, unit_type) WHERE ((resolution = 'year-month'::public.history_resolution) AND (hash_partition IS NULL));

CREATE UNIQUE INDEX statistical_history_partition_month_key ON public.statistical_history USING btree (hash_partition, resolution, year, month, unit_type) WHERE ((resolution = 'year-month'::public.history_resolution) AND (hash_partition IS NOT NULL));

CREATE UNIQUE INDEX statistical_history_partition_year_key ON public.statistical_history USING btree (hash_partition, resolution, year, unit_type) WHERE ((resolution = 'year'::public.history_resolution) AND (hash_partition IS NOT NULL));

CREATE UNIQUE INDEX statistical_history_year_key ON public.statistical_history USING btree (resolution, year, unit_type) WHERE ((resolution = 'year'::public.history_resolution) AND (hash_partition IS NULL));

ALTER TABLE public.statistical_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY statistical_history_admin_user_manage ON public.statistical_history TO admin_user USING ((hash_partition IS NULL)) WITH CHECK (true);

CREATE POLICY statistical_history_authenticated_read ON public.statistical_history FOR SELECT TO authenticated USING ((hash_partition IS NULL));

ALTER TABLE public.statistical_history_facet ENABLE ROW LEVEL SECURITY;

CREATE POLICY statistical_history_facet_admin_user_manage ON public.statistical_history_facet TO admin_user USING (true) WITH CHECK (true);

CREATE POLICY statistical_history_facet_authenticated_read ON public.statistical_history_facet FOR SELECT TO authenticated USING (true);

CREATE POLICY statistical_history_facet_regular_user_read ON public.statistical_history_facet FOR SELECT TO regular_user USING (true);

CREATE POLICY statistical_history_regular_user_read ON public.statistical_history FOR SELECT TO regular_user USING ((hash_partition IS NULL));

GRANT TRUNCATE ON TABLE public.statistical_history_facet_partitions TO admin_user;

GRANT SELECT ON TABLE public.statistical_history TO authenticated;
GRANT SELECT ON TABLE public.statistical_history TO regular_user;
GRANT ALL ON TABLE public.statistical_history TO admin_user;

GRANT SELECT ON TABLE public.statistical_history_facet TO authenticated;
GRANT SELECT ON TABLE public.statistical_history_facet TO regular_user;
GRANT ALL ON TABLE public.statistical_history_facet TO admin_user;



CREATE OR REPLACE FUNCTION public.statistical_history_def(p_resolution history_resolution, p_year integer, p_month integer, p_hash_partition int4range DEFAULT NULL::int4range)
 RETURNS SETOF statistical_history_type
 LANGUAGE plpgsql
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
DECLARE
    v_curr_start date;
    v_curr_stop date;
    v_prev_start date;
    v_prev_stop date;
BEGIN
    IF p_resolution = 'year'::public.history_resolution THEN
        v_curr_start := make_date(p_year, 1, 1);
        v_curr_stop  := make_date(p_year, 12, 31);
        v_prev_start := make_date(p_year - 1, 1, 1);
        v_prev_stop  := make_date(p_year - 1, 12, 31);
    ELSE -- 'year-month'
        v_curr_start := make_date(p_year, p_month, 1);
        v_curr_stop  := (v_curr_start + interval '1 month') - interval '1 day';
        v_prev_stop  := v_curr_start - interval '1 day';
        v_prev_start := date_trunc('month', v_prev_stop)::date;
    END IF;

    RETURN QUERY
    WITH
    units_in_period AS (
        SELECT *
        FROM public.statistical_unit su
        WHERE public.from_to_overlaps(su.valid_from, su.valid_to, v_prev_start, v_curr_stop)
          -- When computing a partition range, filter by hash_slot within the range.
          -- Use explicit half-open bounds (not <@) so the btree index on
          -- statistical_unit(hash_slot) is used at 2.2M-row scale.
          AND (p_hash_partition IS NULL
               OR (su.hash_slot >= lower(p_hash_partition)
                   AND su.hash_slot <  upper(p_hash_partition)))
    ),
    latest_versions_curr AS (
        SELECT DISTINCT ON (uip.unit_id, uip.unit_type) uip.*
        FROM units_in_period AS uip
        WHERE uip.valid_from <= v_curr_stop AND uip.valid_to >= v_curr_start
        ORDER BY uip.unit_id, uip.unit_type, uip.valid_from DESC, uip.valid_until DESC
    ),
    latest_versions_prev AS (
        SELECT DISTINCT ON (uip.unit_id, uip.unit_type) uip.*
        FROM units_in_period AS uip
        WHERE uip.valid_from <= v_prev_stop
        ORDER BY uip.unit_id, uip.unit_type, uip.valid_from DESC, uip.valid_until DESC
    ),
    stock_at_end_of_curr AS (
        SELECT * FROM latest_versions_curr lvc
        -- STATBUS-460 canonical existence rule (public.unit_existence_from/until).
        WHERE public.unit_existence_from(lvc.valid_from, lvc.birth_date) <= v_curr_stop
          AND v_curr_stop < public.unit_existence_until(lvc.valid_until, lvc.death_date)
    ),
    stock_at_end_of_prev AS (
        SELECT * FROM latest_versions_prev lvp
        -- STATBUS-460 canonical existence rule (public.unit_existence_from/until).
        WHERE public.unit_existence_from(lvp.valid_from, lvp.birth_date) <= v_prev_stop
          AND v_prev_stop < public.unit_existence_until(lvp.valid_until, lvp.death_date)
    ),
    changed_units AS (
        SELECT
            COALESCE(c.unit_id, p.unit_id) AS unit_id,
            COALESCE(c.unit_type, p.unit_type) AS unit_type,
            -- hash_slot is stable per unit (function of unit_type + unit_id),
            -- so c and p (when both present) carry the same value.
            COALESCE(c.hash_slot, p.hash_slot) AS hash_slot,
            c AS curr,
            p AS prev,
            lvc AS last_version_in_curr
        FROM stock_at_end_of_curr c
        FULL JOIN stock_at_end_of_prev p ON c.unit_id = p.unit_id AND c.unit_type = p.unit_type
        LEFT JOIN latest_versions_curr lvc ON lvc.unit_id = COALESCE(p.unit_id, c.unit_id) AND lvc.unit_type = COALESCE(p.unit_type, c.unit_type)
    ),
    stats_by_slot AS (
        SELECT
            lvc.unit_type,
            lvc.hash_slot,
            COALESCE(public.jsonb_stats_merge_agg(lvc.stats_summary), '{}'::jsonb) AS stats_summary
        FROM latest_versions_curr lvc
        WHERE lvc.used_for_counting
        GROUP BY lvc.unit_type, lvc.hash_slot
    ),
    demographics AS (
        SELECT
            p_resolution, p_year, p_month, unit_type, hash_slot,
            count((curr).unit_id)::integer AS exists_count,
            (count((curr).unit_id) - count((prev).unit_id))::integer AS exists_change,
            count((curr).unit_id) FILTER (WHERE (prev).unit_id IS NULL)::integer AS exists_added_count,
            count((prev).unit_id) FILTER (WHERE (curr).unit_id IS NULL)::integer AS exists_removed_count,
            count((curr).unit_id) FILTER (WHERE (curr).used_for_counting)::integer AS countable_count,
            (count((curr).unit_id) FILTER (WHERE (curr).used_for_counting) - count((prev).unit_id) FILTER (WHERE (prev).used_for_counting))::integer AS countable_change,
            count(*) FILTER (WHERE (curr).used_for_counting AND NOT COALESCE((prev).used_for_counting, false))::integer AS countable_added_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND NOT COALESCE((curr).used_for_counting, false))::integer AS countable_removed_count,
            count(*) FILTER (WHERE (last_version_in_curr).used_for_counting AND (last_version_in_curr).birth_date BETWEEN v_curr_start AND v_curr_stop)::integer AS births,
            count(*) FILTER (WHERE (last_version_in_curr).used_for_counting AND (last_version_in_curr).death_date BETWEEN v_curr_start AND v_curr_stop)::integer AS deaths,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).name IS DISTINCT FROM (prev).name)::integer AS name_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).primary_activity_category_path IS DISTINCT FROM (prev).primary_activity_category_path)::integer AS primary_activity_category_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).secondary_activity_category_path IS DISTINCT FROM (prev).secondary_activity_category_path)::integer AS secondary_activity_category_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).sector_path IS DISTINCT FROM (prev).sector_path)::integer AS sector_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).legal_form_id IS DISTINCT FROM (prev).legal_form_id)::integer AS legal_form_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).physical_region_path IS DISTINCT FROM (prev).physical_region_path)::integer AS physical_region_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).physical_country_id IS DISTINCT FROM (prev).physical_country_id)::integer AS physical_country_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND ((curr).physical_address_part1, (curr).physical_address_part2, (curr).physical_address_part3, (curr).physical_postcode, (curr).physical_postplace) IS DISTINCT FROM ((prev).physical_address_part1, (prev).physical_address_part2, (prev).physical_address_part3, (prev).physical_postcode, (prev).physical_postplace))::integer AS physical_address_change_count
        FROM changed_units
        GROUP BY 1, 2, 3, 4, 5
    )
    SELECT
        d.p_resolution AS resolution, d.p_year AS year, d.p_month AS month, d.unit_type,
        d.exists_count, d.exists_change, d.exists_added_count, d.exists_removed_count,
        d.countable_count, d.countable_change, d.countable_added_count, d.countable_removed_count,
        d.births, d.deaths,
        d.name_change_count, d.primary_activity_category_change_count, d.secondary_activity_category_change_count,
        d.sector_change_count, d.legal_form_change_count, d.physical_region_change_count,
        d.physical_country_change_count, d.physical_address_change_count,
        COALESCE(sbs.stats_summary, '{}'::jsonb) AS stats_summary,
        -- Slot-keyed storage: each output row corresponds to exactly one slot.
        -- The hash_partition column stores int4range(hash_slot, hash_slot+1).
        int4range(d.hash_slot, d.hash_slot + 1) AS hash_partition
    FROM demographics d
    LEFT JOIN stats_by_slot sbs ON sbs.unit_type = d.unit_type AND sbs.hash_slot = d.hash_slot;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.statistical_history_facet_def(p_resolution history_resolution, p_year integer, p_month integer, p_hash_partition int4range DEFAULT NULL::int4range)
 RETURNS SETOF statistical_history_facet_partitions
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_curr_start date;
    v_curr_stop date;
    v_prev_start date;
    v_prev_stop date;
BEGIN
    IF p_resolution = 'year'::public.history_resolution THEN
        v_curr_start := make_date(p_year, 1, 1);
        v_curr_stop  := make_date(p_year, 12, 31);
        v_prev_start := make_date(p_year - 1, 1, 1);
        v_prev_stop  := make_date(p_year - 1, 12, 31);
    ELSE
        v_curr_start := make_date(p_year, p_month, 1);
        v_curr_stop  := (v_curr_start + interval '1 month') - interval '1 day';
        v_prev_stop  := v_curr_start - interval '1 day';
        v_prev_start := date_trunc('month', v_prev_stop)::date;
    END IF;

    RETURN QUERY
    WITH
    units_in_period AS (
        SELECT *
        FROM public.statistical_unit su
        WHERE daterange(su.valid_from, su.valid_to, '[)') && daterange(v_prev_start, v_curr_stop + 1, '[)')
          -- Partition filter: explicit half-open bounds hit the btree index on
          -- statistical_unit(hash_slot). Mirrors statistical_history_def.
          AND (p_hash_partition IS NULL
               OR (su.hash_slot >= lower(p_hash_partition)
                   AND su.hash_slot <  upper(p_hash_partition)))
    ),
    latest_versions_curr AS (
        SELECT DISTINCT ON (uip.unit_id, uip.unit_type) uip.*
        FROM units_in_period AS uip
        WHERE uip.valid_from <= v_curr_stop AND uip.valid_to >= v_curr_start
        ORDER BY uip.unit_id, uip.unit_type, uip.valid_from DESC, uip.valid_until DESC
    ),
    latest_versions_prev AS (
        SELECT DISTINCT ON (uip.unit_id, uip.unit_type) uip.*
        FROM units_in_period AS uip
        WHERE uip.valid_from <= v_prev_stop
        ORDER BY uip.unit_id, uip.unit_type, uip.valid_from DESC, uip.valid_until DESC
    ),
    stock_at_end_of_curr AS (
        SELECT * FROM latest_versions_curr lvc
        -- STATBUS-460 canonical existence rule (public.unit_existence_from/until).
        WHERE public.unit_existence_from(lvc.valid_from, lvc.birth_date) <= v_curr_stop
          AND v_curr_stop < public.unit_existence_until(lvc.valid_until, lvc.death_date)
    ),
    stock_at_end_of_prev AS (
        SELECT * FROM latest_versions_prev lvp
        -- STATBUS-460 canonical existence rule (public.unit_existence_from/until).
        WHERE public.unit_existence_from(lvp.valid_from, lvp.birth_date) <= v_prev_stop
          AND v_prev_stop < public.unit_existence_until(lvp.valid_until, lvp.death_date)
    ),
    -- PERF: pre-aggregate per-(slot, facet) stats once. MATERIALIZED because
    -- the CTE is referenced once and would otherwise be inlined: with CTE row
    -- estimates of 1-3 the planner joins it by nested loop and re-runs the
    -- jsonb_stats_merge_agg aggregate for every demographics row (STATBUS-543:
    -- 925 of 950 ms for a 256-slot child). hash_slot is a pure function of
    -- (unit_type, unit_id) so every lvc row already has the slot it belongs to.
    stats_by_facet AS MATERIALIZED (
        SELECT
            hash_slot,
            unit_type::text || '|' ||
            COALESCE(primary_activity_category_path::text, '') || '|' ||
            COALESCE(secondary_activity_category_path::text, '') || '|' ||
            COALESCE(sector_path::text, '') || '|' ||
            COALESCE(legal_form_id::text, '') || '|' ||
            COALESCE(physical_region_path::text, '') || '|' ||
            COALESCE(physical_country_id::text, '') || '|' ||
            COALESCE(unit_size_id::text, '') || '|' ||
            COALESCE(status_id::text, '') AS facet_key,
            COALESCE(public.jsonb_stats_merge_agg(stats_summary), '{}'::jsonb) AS stats_summary
        FROM latest_versions_curr
        WHERE used_for_counting
        GROUP BY 1, 2
    ),
    -- PERF: flatten columns instead of storing entire ROW types. Carry hash_slot
    -- forward via COALESCE(c.hash_slot, p.hash_slot) — both are equal for any
    -- matching (unit_id, unit_type) because hash_slot is a pure function.
    changed_units AS (
        SELECT
            COALESCE(c.unit_id, p.unit_id) AS unit_id,
            COALESCE(c.unit_type, p.unit_type) AS unit_type,
            COALESCE(c.hash_slot, p.hash_slot) AS hash_slot,
            c.unit_id AS c_unit_id, c.used_for_counting AS c_used_for_counting,
            c.primary_activity_category_path AS c_pac_path,
            c.secondary_activity_category_path AS c_sac_path,
            c.sector_path AS c_sector_path, c.legal_form_id AS c_legal_form_id,
            c.physical_region_path AS c_region_path, c.physical_country_id AS c_country_id,
            c.physical_address_part1 AS c_addr1, c.physical_address_part2 AS c_addr2,
            c.physical_address_part3 AS c_addr3, c.physical_postcode AS c_postcode,
            c.physical_postplace AS c_postplace,
            c.unit_size_id AS c_size_id, c.status_id AS c_status_id, c.name AS c_name,
            p.unit_id AS p_unit_id, p.used_for_counting AS p_used_for_counting,
            p.primary_activity_category_path AS p_pac_path,
            p.secondary_activity_category_path AS p_sac_path,
            p.sector_path AS p_sector_path, p.legal_form_id AS p_legal_form_id,
            p.physical_region_path AS p_region_path, p.physical_country_id AS p_country_id,
            p.physical_address_part1 AS p_addr1, p.physical_address_part2 AS p_addr2,
            p.physical_address_part3 AS p_addr3, p.physical_postcode AS p_postcode,
            p.physical_postplace AS p_postplace,
            p.unit_size_id AS p_size_id, p.status_id AS p_status_id, p.name AS p_name,
            lvc.birth_date AS lvc_birth_date, lvc.death_date AS lvc_death_date,
            lvc.used_for_counting AS lvc_used_for_counting
        FROM stock_at_end_of_curr c
        FULL JOIN stock_at_end_of_prev p ON c.unit_id = p.unit_id AND c.unit_type = p.unit_type
        LEFT JOIN latest_versions_curr lvc ON lvc.unit_id = COALESCE(p.unit_id, c.unit_id)
                                 AND lvc.unit_type = COALESCE(p.unit_type, c.unit_type)
    ),
    demographics AS (
        SELECT
            hash_slot,
            p_resolution, p_year, p_month,
            unit_type,
            COALESCE(c_pac_path, p_pac_path) AS primary_activity_category_path,
            COALESCE(c_sac_path, p_sac_path) AS secondary_activity_category_path,
            COALESCE(c_sector_path, p_sector_path) AS sector_path,
            COALESCE(c_legal_form_id, p_legal_form_id) AS legal_form_id,
            COALESCE(c_region_path, p_region_path) AS physical_region_path,
            COALESCE(c_country_id, p_country_id) AS physical_country_id,
            COALESCE(c_size_id, p_size_id) AS unit_size_id,
            COALESCE(c_status_id, p_status_id) AS status_id,
            unit_type::text || '|' ||
            COALESCE(COALESCE(c_pac_path, p_pac_path)::text, '') || '|' ||
            COALESCE(COALESCE(c_sac_path, p_sac_path)::text, '') || '|' ||
            COALESCE(COALESCE(c_sector_path, p_sector_path)::text, '') || '|' ||
            COALESCE(COALESCE(c_legal_form_id, p_legal_form_id)::text, '') || '|' ||
            COALESCE(COALESCE(c_region_path, p_region_path)::text, '') || '|' ||
            COALESCE(COALESCE(c_country_id, p_country_id)::text, '') || '|' ||
            COALESCE(COALESCE(c_size_id, p_size_id)::text, '') || '|' ||
            COALESCE(COALESCE(c_status_id, p_status_id)::text, '') AS facet_key,
            count(c_unit_id)::integer AS exists_count,
            (count(c_unit_id) - count(p_unit_id))::integer AS exists_change,
            count(c_unit_id) FILTER (WHERE p_unit_id IS NULL)::integer AS exists_added_count,
            count(p_unit_id) FILTER (WHERE c_unit_id IS NULL)::integer AS exists_removed_count,
            count(c_unit_id) FILTER (WHERE c_used_for_counting)::integer AS countable_count,
            (count(c_unit_id) FILTER (WHERE c_used_for_counting) - count(p_unit_id) FILTER (WHERE p_used_for_counting))::integer AS countable_change,
            count(*) FILTER (WHERE c_used_for_counting AND NOT COALESCE(p_used_for_counting, false))::integer AS countable_added_count,
            count(*) FILTER (WHERE p_used_for_counting AND NOT COALESCE(c_used_for_counting, false))::integer AS countable_removed_count,
            count(*) FILTER (WHERE lvc_used_for_counting AND lvc_birth_date BETWEEN v_curr_start AND v_curr_stop)::integer AS births,
            count(*) FILTER (WHERE lvc_used_for_counting AND lvc_death_date BETWEEN v_curr_start AND v_curr_stop)::integer AS deaths,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_name IS DISTINCT FROM p_name)::integer AS name_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_pac_path IS DISTINCT FROM p_pac_path)::integer AS primary_activity_category_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_sac_path IS DISTINCT FROM p_sac_path)::integer AS secondary_activity_category_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_sector_path IS DISTINCT FROM p_sector_path)::integer AS sector_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_legal_form_id IS DISTINCT FROM p_legal_form_id)::integer AS legal_form_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_region_path IS DISTINCT FROM p_region_path)::integer AS physical_region_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_country_id IS DISTINCT FROM p_country_id)::integer AS physical_country_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND
                (c_addr1, c_addr2, c_addr3, c_postcode, c_postplace) IS DISTINCT FROM
                (p_addr1, p_addr2, p_addr3, p_postcode, p_postplace))::integer AS physical_address_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_size_id IS DISTINCT FROM p_size_id)::integer AS unit_size_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_status_id IS DISTINCT FROM p_status_id)::integer AS status_change_count
        FROM changed_units
        GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14
    )
    SELECT
        d.hash_slot,
        d.p_resolution AS resolution,
        d.p_year AS year,
        d.p_month AS month,
        d.unit_type,
        d.primary_activity_category_path,
        d.secondary_activity_category_path,
        d.sector_path,
        d.legal_form_id,
        d.physical_region_path,
        d.physical_country_id,
        d.unit_size_id,
        d.status_id,
        d.exists_count,
        d.exists_change,
        d.exists_added_count,
        d.exists_removed_count,
        d.countable_count,
        d.countable_change,
        d.countable_added_count,
        d.countable_removed_count,
        d.births,
        d.deaths,
        d.name_change_count,
        d.primary_activity_category_change_count,
        d.secondary_activity_category_change_count,
        d.sector_change_count,
        d.legal_form_change_count,
        d.physical_region_change_count,
        d.physical_country_change_count,
        d.physical_address_change_count,
        d.unit_size_change_count,
        d.status_change_count,
        COALESCE(s.stats_summary, '{}'::jsonb) AS stats_summary
    FROM demographics d
    LEFT JOIN stats_by_facet s ON s.hash_slot = d.hash_slot AND s.facet_key = d.facet_key;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.statistical_history_derive(p_valid_from date DEFAULT '-infinity'::date, p_valid_until date DEFAULT 'infinity'::date)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE DEBUG 'Running statistical_history_derive(p_valid_from=%, p_valid_until=%)', p_valid_from, p_valid_until;

    -- Delete existing records for the affected periods
    DELETE FROM public.statistical_history sh
    USING public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    ) tp
    WHERE sh.year = tp.year
    AND sh.month IS NOT DISTINCT FROM tp.month;

    -- Insert year-resolution rows.
    -- ON CONFLICT DO UPDATE: if a concurrent worker already inserted,
    -- overwrite with the freshest computed data.
    INSERT INTO public.statistical_history
    SELECT h.*
    FROM public.get_statistical_history_periods(
        p_resolution := 'year'::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    ) tp
    CROSS JOIN LATERAL public.statistical_history_def(tp.resolution, tp.year, tp.month) h
    ON CONFLICT (resolution, year, unit_type) WHERE resolution = 'year'::public.history_resolution
    DO UPDATE SET
        exists_count = EXCLUDED.exists_count,
        exists_change = EXCLUDED.exists_change,
        exists_added_count = EXCLUDED.exists_added_count,
        exists_removed_count = EXCLUDED.exists_removed_count,
        countable_count = EXCLUDED.countable_count,
        countable_change = EXCLUDED.countable_change,
        countable_added_count = EXCLUDED.countable_added_count,
        countable_removed_count = EXCLUDED.countable_removed_count,
        births = EXCLUDED.births,
        deaths = EXCLUDED.deaths,
        name_change_count = EXCLUDED.name_change_count,
        primary_activity_category_change_count = EXCLUDED.primary_activity_category_change_count,
        secondary_activity_category_change_count = EXCLUDED.secondary_activity_category_change_count,
        sector_change_count = EXCLUDED.sector_change_count,
        legal_form_change_count = EXCLUDED.legal_form_change_count,
        physical_region_change_count = EXCLUDED.physical_region_change_count,
        physical_country_change_count = EXCLUDED.physical_country_change_count,
        physical_address_change_count = EXCLUDED.physical_address_change_count,
        stats_summary = EXCLUDED.stats_summary;

    -- Insert year-month resolution rows.
    INSERT INTO public.statistical_history
    SELECT h.*
    FROM public.get_statistical_history_periods(
        p_resolution := 'year-month'::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    ) tp
    CROSS JOIN LATERAL public.statistical_history_def(tp.resolution, tp.year, tp.month) h
    ON CONFLICT (resolution, year, month, unit_type) WHERE resolution = 'year-month'::public.history_resolution
    DO UPDATE SET
        exists_count = EXCLUDED.exists_count,
        exists_change = EXCLUDED.exists_change,
        exists_added_count = EXCLUDED.exists_added_count,
        exists_removed_count = EXCLUDED.exists_removed_count,
        countable_count = EXCLUDED.countable_count,
        countable_change = EXCLUDED.countable_change,
        countable_added_count = EXCLUDED.countable_added_count,
        countable_removed_count = EXCLUDED.countable_removed_count,
        births = EXCLUDED.births,
        deaths = EXCLUDED.deaths,
        name_change_count = EXCLUDED.name_change_count,
        primary_activity_category_change_count = EXCLUDED.primary_activity_category_change_count,
        secondary_activity_category_change_count = EXCLUDED.secondary_activity_category_change_count,
        sector_change_count = EXCLUDED.sector_change_count,
        legal_form_change_count = EXCLUDED.legal_form_change_count,
        physical_region_change_count = EXCLUDED.physical_region_change_count,
        physical_country_change_count = EXCLUDED.physical_country_change_count,
        physical_address_change_count = EXCLUDED.physical_address_change_count,
        stats_summary = EXCLUDED.stats_summary;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.statistical_history_facet_derive(p_valid_from date DEFAULT '-infinity'::date, p_valid_until date DEFAULT 'infinity'::date)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE DEBUG 'Running statistical_history_facet_derive(p_valid_from=%, p_valid_until=%)', p_valid_from, p_valid_until;

    -- Clear target rows for the requested temporal scope.
    DELETE FROM public.statistical_history_facet AS shf
    USING public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    ) AS tp
    WHERE shf.resolution = tp.resolution
      AND shf.year = tp.year
      AND shf.month IS NOT DISTINCT FROM tp.month;

    -- Bulk INSERT with cross-slot aggregation. The def function returns
    -- per-slot rows (RETURNS SETOF statistical_history_facet_partitions);
    -- target is keyed by (resolution, year, month, dims_8). GROUP BY the
    -- target's natural key and SUM/jsonb_stats_merge_agg across slots.
    INSERT INTO public.statistical_history_facet (
        resolution, year, month, unit_type,
        primary_activity_category_path, secondary_activity_category_path,
        sector_path, legal_form_id, physical_region_path,
        physical_country_id, unit_size_id, status_id,
        exists_count, exists_change, exists_added_count, exists_removed_count,
        countable_count, countable_change, countable_added_count, countable_removed_count,
        births, deaths,
        name_change_count, primary_activity_category_change_count,
        secondary_activity_category_change_count, sector_change_count,
        legal_form_change_count, physical_region_change_count, physical_country_change_count,
        physical_address_change_count, unit_size_change_count, status_change_count,
        stats_summary
    )
    SELECT
        f.resolution, f.year, f.month, f.unit_type,
        f.primary_activity_category_path, f.secondary_activity_category_path,
        f.sector_path, f.legal_form_id, f.physical_region_path,
        f.physical_country_id, f.unit_size_id, f.status_id,
        SUM(f.exists_count)::integer,
        SUM(f.exists_change)::integer,
        SUM(f.exists_added_count)::integer,
        SUM(f.exists_removed_count)::integer,
        SUM(f.countable_count)::integer,
        SUM(f.countable_change)::integer,
        SUM(f.countable_added_count)::integer,
        SUM(f.countable_removed_count)::integer,
        SUM(f.births)::integer,
        SUM(f.deaths)::integer,
        SUM(f.name_change_count)::integer,
        SUM(f.primary_activity_category_change_count)::integer,
        SUM(f.secondary_activity_category_change_count)::integer,
        SUM(f.sector_change_count)::integer,
        SUM(f.legal_form_change_count)::integer,
        SUM(f.physical_region_change_count)::integer,
        SUM(f.physical_country_change_count)::integer,
        SUM(f.physical_address_change_count)::integer,
        SUM(f.unit_size_change_count)::integer,
        SUM(f.status_change_count)::integer,
        public.jsonb_stats_merge_agg(f.stats_summary)
    FROM public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    ) AS tp
    CROSS JOIN LATERAL public.statistical_history_facet_def(tp.resolution, tp.year, tp.month) AS f
    GROUP BY f.resolution, f.year, f.month, f.unit_type,
             f.primary_activity_category_path, f.secondary_activity_category_path,
             f.sector_path, f.legal_form_id, f.physical_region_path,
             f.physical_country_id, f.unit_size_id, f.status_id;
END;
$function$

;



CREATE OR REPLACE PROCEDURE worker.derive_statistical_history(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_task_id bigint;
    v_period record;
    v_dirty_hash_slots integer[];
    v_child_count integer := 0;
    v_partition_count_target integer;
    v_hash_partition_size integer;
    v_hash_partition int4range;
BEGIN
    v_partition_count_target := public.get_partition_count_target();
    v_hash_partition_size := GREATEST(1, 16384 / v_partition_count_target);

    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    SELECT array_agg(dirty_hash_slot ORDER BY dirty_hash_slot) INTO v_dirty_hash_slots
    FROM public.statistical_unit_facet_dirty_hash_slots;

    -- Full rebuild when the request covers all time, valid_from = -infinity
    -- and valid_until = infinity (STATBUS-538, see
    -- worker.enqueue_derive_statistical_unit_all), or when no per-slot rows
    -- exist yet (fresh install). A full rebuild drops every per-slot row
    -- first, so slots and periods without units do not survive the reduce.
    IF v_valid_from = '-infinity'::date AND v_valid_until = 'infinity'::date THEN
        DELETE FROM public.statistical_history WHERE hash_partition IS NOT NULL;
        v_dirty_hash_slots := NULL;
    ELSIF NOT EXISTS (SELECT 1 FROM public.statistical_history WHERE hash_partition IS NOT NULL LIMIT 1) THEN
        v_dirty_hash_slots := NULL;
    END IF;

    FOR v_period IN
        SELECT resolution, year, month
        FROM public.get_statistical_history_periods(
            p_resolution => null::public.history_resolution,
            p_valid_from => v_valid_from,
            p_valid_until => v_valid_until
        )
    LOOP
        IF v_dirty_hash_slots IS NOT NULL THEN
            -- Dirty branch: one child per partition range (16384 /
            -- partition_count_target slots, the same ranges as the full
            -- rebuild) that holds a dirty slot. The child rebuilds every slot
            -- of its range, so task count is bounded by the partition setting,
            -- not by the number of changed slots (STATBUS-543).
            FOR v_hash_partition IN
                SELECT DISTINCT int4range(
                    (d.slot / v_hash_partition_size) * v_hash_partition_size,
                    LEAST((d.slot / v_hash_partition_size) * v_hash_partition_size + v_hash_partition_size, 16384)
                )
                FROM unnest(v_dirty_hash_slots) AS d(slot)
                ORDER BY 1
            LOOP
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_history_period',
                    p_payload => jsonb_build_object(
                        'command', 'derive_statistical_history_period',
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'hash_partition', v_hash_partition::text
                    ),
                    p_parent_id => v_task_id
                );
                v_child_count := v_child_count + 1;
            END LOOP;
        ELSE
            -- Full-rebuild branch: data-driven DISTINCT ranges, derived from
            -- the actual set of slots occupied in statistical_unit.
            FOR v_hash_partition IN
                SELECT DISTINCT int4range(
                    (su.hash_slot / v_hash_partition_size) * v_hash_partition_size,
                    LEAST((su.hash_slot / v_hash_partition_size) * v_hash_partition_size + v_hash_partition_size, 16384)
                )
                FROM public.statistical_unit AS su
                ORDER BY 1
            LOOP
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_history_period',
                    p_payload => jsonb_build_object(
                        'command', 'derive_statistical_history_period',
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'hash_partition', v_hash_partition::text
                    ),
                    p_parent_id => v_task_id
                );
                v_child_count := v_child_count + 1;
            END LOOP;
        END IF;
    END LOOP;

    p_info := jsonb_build_object('child_count', v_child_count);
END;
$procedure$

;

CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_period(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_resolution public.history_resolution := (payload->>'resolution')::public.history_resolution;
    v_year integer := (payload->>'year')::integer;
    v_month integer := (payload->>'month')::integer;
    v_hash_partition int4range := NULLIF(payload->>'hash_partition', '')::int4range;
    v_row_count bigint;
BEGIN
    RAISE DEBUG 'Processing statistical_history for resolution=%, year=%, month=%, hash_partition=%',
                 v_resolution, v_year, v_month, v_hash_partition;

    IF v_hash_partition IS NOT NULL THEN
        -- Stored per-slot rows hold singleton ranges [s,s+1). Ranges sort by
        -- lower bound, so comparing the column with the singleton ranges of
        -- the spawn's first and past-the-end slots selects exactly the rows
        -- whose slot lies in the spawn's range, and lets the partition unique
        -- keys (hash_partition, resolution, year[, month], unit_type) bound
        -- the scan. month is matched by equality, or IS NULL for the year
        -- resolution, so the month key can use it (STATBUS-543: the former
        -- lower(hash_partition) and month IS NOT DISTINCT FROM filters
        -- scanned the whole table for every year-month child).
        DELETE FROM public.statistical_history
         WHERE resolution = v_resolution
           AND year = v_year
           AND ((v_month IS NULL AND month IS NULL) OR month = v_month)
           AND hash_partition >= int4range(lower(v_hash_partition), lower(v_hash_partition) + 1)
           AND hash_partition <  int4range(upper(v_hash_partition), upper(v_hash_partition) + 1);

        INSERT INTO public.statistical_history
        SELECT h.*
        FROM public.statistical_history_def(v_resolution, v_year, v_month, v_hash_partition) AS h;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;
    ELSE
        -- Manual escape hatch: full-period rebuild. The DELETE drops the
        -- `hash_partition IS NULL` filter (vs rc.42), wiping every row for
        -- the period — both the NULL summary and any per-slot rows. The
        -- INSERT then writes fresh per-slot rows from def(...). Reduce
        -- rebuilds the NULL summary on its next run.
        DELETE FROM public.statistical_history
         WHERE resolution = v_resolution
           AND year = v_year
           AND month IS NOT DISTINCT FROM v_month;

        INSERT INTO public.statistical_history
        SELECT h.*
        FROM public.statistical_history_def(v_resolution, v_year, v_month) AS h;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;
    END IF;

    RAISE DEBUG 'Completed statistical_history for resolution=%, year=%, month=%, hash_partition=%',
                 v_resolution, v_year, v_month, v_hash_partition;

    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$procedure$

;

CREATE OR REPLACE PROCEDURE worker.statistical_history_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_row_count bigint;
BEGIN
    DELETE FROM public.statistical_history WHERE hash_partition IS NULL;

    INSERT INTO public.statistical_history (
        resolution, year, month, unit_type,
        exists_count, exists_change, exists_added_count, exists_removed_count,
        countable_count, countable_change, countable_added_count, countable_removed_count,
        births, deaths,
        name_change_count, primary_activity_category_change_count,
        secondary_activity_category_change_count, sector_change_count,
        legal_form_change_count, physical_region_change_count,
        physical_country_change_count, physical_address_change_count,
        stats_summary,
        hash_partition
    )
    SELECT
        resolution, year, month, unit_type,
        SUM(exists_count)::integer, SUM(exists_change)::integer,
        SUM(exists_added_count)::integer, SUM(exists_removed_count)::integer,
        SUM(countable_count)::integer, SUM(countable_change)::integer,
        SUM(countable_added_count)::integer, SUM(countable_removed_count)::integer,
        SUM(births)::integer, SUM(deaths)::integer,
        SUM(name_change_count)::integer, SUM(primary_activity_category_change_count)::integer,
        SUM(secondary_activity_category_change_count)::integer, SUM(sector_change_count)::integer,
        SUM(legal_form_change_count)::integer, SUM(physical_region_change_count)::integer,
        SUM(physical_country_change_count)::integer, SUM(physical_address_change_count)::integer,
        jsonb_stats_merge_agg(stats_summary),
        NULL
    FROM public.statistical_history
    WHERE hash_partition IS NOT NULL
    GROUP BY resolution, year, month, unit_type;
    GET DIAGNOSTICS v_row_count := ROW_COUNT;

    p_info := jsonb_build_object('rows_reduced', v_row_count);
END;
$procedure$

;

CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := COALESCE((payload->>'valid_from')::date, '-infinity'::date);
    v_valid_until date := COALESCE((payload->>'valid_until')::date, 'infinity'::date);
    v_task_id bigint;
    v_period record;
    v_dirty_hash_slots integer[];
    v_child_count integer := 0;
    v_partition_count_target integer;
    v_hash_partition_size integer;
    v_hash_partition int4range;
BEGIN
    v_partition_count_target := public.get_partition_count_target();
    v_hash_partition_size := GREATEST(1, 16384 / v_partition_count_target);

    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    SELECT array_agg(dirty_hash_slot ORDER BY dirty_hash_slot) INTO v_dirty_hash_slots
    FROM public.statistical_unit_facet_dirty_hash_slots;

    -- Full rebuild when the request covers all time, valid_from = -infinity
    -- and valid_until = infinity (STATBUS-538, see
    -- worker.enqueue_derive_statistical_unit_all), or when the per-slot cache
    -- is empty (fresh install). A full rebuild drops the whole cache first,
    -- so slots and periods without units do not survive into the reduce.
    IF (payload->>'valid_from')::date = '-infinity'::date
       AND (payload->>'valid_until')::date = 'infinity'::date THEN
        DELETE FROM public.statistical_history_facet_partitions;
        v_dirty_hash_slots := NULL;
    ELSIF NOT EXISTS (SELECT 1 FROM public.statistical_history_facet_partitions LIMIT 1) THEN
        v_dirty_hash_slots := NULL;
    END IF;

    FOR v_period IN
        SELECT resolution, year, month
        FROM public.get_statistical_history_periods(
            p_resolution => null::public.history_resolution,
            p_valid_from => v_valid_from,
            p_valid_until => v_valid_until
        )
    LOOP
        IF v_dirty_hash_slots IS NOT NULL THEN
            -- One child per partition range holding a dirty slot, the same
            -- ranges as the full rebuild (STATBUS-543).
            FOR v_hash_partition IN
                SELECT DISTINCT int4range(
                    (d.slot / v_hash_partition_size) * v_hash_partition_size,
                    LEAST((d.slot / v_hash_partition_size) * v_hash_partition_size + v_hash_partition_size, 16384)
                )
                FROM unnest(v_dirty_hash_slots) AS d(slot)
                ORDER BY 1
            LOOP
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_history_facet_period',
                    p_payload => jsonb_build_object(
                        'command', 'derive_statistical_history_facet_period',
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'hash_partition', v_hash_partition::text
                    ),
                    p_parent_id => v_task_id
                );
                v_child_count := v_child_count + 1;
            END LOOP;
        ELSE
            FOR v_hash_partition IN
                SELECT DISTINCT int4range(
                    (su.hash_slot / v_hash_partition_size) * v_hash_partition_size,
                    LEAST((su.hash_slot / v_hash_partition_size) * v_hash_partition_size + v_hash_partition_size, 16384)
                )
                FROM public.statistical_unit AS su
                ORDER BY 1
            LOOP
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_history_facet_period',
                    p_payload => jsonb_build_object(
                        'command', 'derive_statistical_history_facet_period',
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'hash_partition', v_hash_partition::text
                    ),
                    p_parent_id => v_task_id
                );
                v_child_count := v_child_count + 1;
            END LOOP;
        END IF;
    END LOOP;

    p_info := jsonb_build_object('child_count', v_child_count);
END;
$procedure$

;

CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet_period(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_resolution public.history_resolution := (payload->>'resolution')::public.history_resolution;
    v_year integer := (payload->>'year')::integer;
    v_month integer := (payload->>'month')::integer;
    v_hash_partition int4range := (payload->>'hash_partition')::int4range;
    v_row_count bigint;
BEGIN
    DELETE FROM public.statistical_history_facet_partitions
     WHERE resolution = v_resolution
       AND year = v_year
       AND month IS NOT DISTINCT FROM v_month
       AND hash_slot >= lower(v_hash_partition)
       AND hash_slot <  upper(v_hash_partition);

    INSERT INTO public.statistical_history_facet_partitions
    SELECT * FROM public.statistical_history_facet_def(
        v_resolution, v_year, v_month, v_hash_partition
    );

    GET DIAGNOSTICS v_row_count := ROW_COUNT;
    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$procedure$

;

CREATE OR REPLACE PROCEDURE worker.statistical_history_facet_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_dirty_hash_slots int[];
    v_row_count bigint;
BEGIN
    -- Read dirty hash slots for diagnostic logging only.
    SELECT array_agg(dp.dirty_hash_slot)
      INTO v_dirty_hash_slots
      FROM public.statistical_unit_facet_dirty_hash_slots AS dp;

    MERGE INTO public.statistical_history_facet AS target
    USING (
        SELECT
            resolution, year, month, unit_type,
            primary_activity_category_path, secondary_activity_category_path,
            sector_path, legal_form_id, physical_region_path,
            physical_country_id, unit_size_id, status_id,
            SUM(exists_count)::integer AS exists_count,
            SUM(exists_change)::integer AS exists_change,
            SUM(exists_added_count)::integer AS exists_added_count,
            SUM(exists_removed_count)::integer AS exists_removed_count,
            SUM(countable_count)::integer AS countable_count,
            SUM(countable_change)::integer AS countable_change,
            SUM(countable_added_count)::integer AS countable_added_count,
            SUM(countable_removed_count)::integer AS countable_removed_count,
            SUM(births)::integer AS births,
            SUM(deaths)::integer AS deaths,
            SUM(name_change_count)::integer AS name_change_count,
            SUM(primary_activity_category_change_count)::integer AS primary_activity_category_change_count,
            SUM(secondary_activity_category_change_count)::integer AS secondary_activity_category_change_count,
            SUM(sector_change_count)::integer AS sector_change_count,
            SUM(legal_form_change_count)::integer AS legal_form_change_count,
            SUM(physical_region_change_count)::integer AS physical_region_change_count,
            SUM(physical_country_change_count)::integer AS physical_country_change_count,
            SUM(physical_address_change_count)::integer AS physical_address_change_count,
            SUM(unit_size_change_count)::integer AS unit_size_change_count,
            SUM(status_change_count)::integer AS status_change_count,
            jsonb_stats_merge_agg(stats_summary) AS stats_summary
        FROM public.statistical_history_facet_partitions
        GROUP BY resolution, year, month, unit_type,
                 primary_activity_category_path, secondary_activity_category_path,
                 sector_path, legal_form_id, physical_region_path,
                 physical_country_id, unit_size_id, status_id
    ) AS source
       ON target.resolution = source.resolution
      AND target.year = source.year
      AND COALESCE(target.month, -1) = COALESCE(source.month, -1)
      AND target.unit_type = source.unit_type
      AND COALESCE(target.primary_activity_category_path::text, '') = COALESCE(source.primary_activity_category_path::text, '')
      AND COALESCE(target.secondary_activity_category_path::text, '') = COALESCE(source.secondary_activity_category_path::text, '')
      AND COALESCE(target.sector_path::text, '') = COALESCE(source.sector_path::text, '')
      AND COALESCE(target.legal_form_id, -1) = COALESCE(source.legal_form_id, -1)
      AND COALESCE(target.physical_region_path::text, '') = COALESCE(source.physical_region_path::text, '')
      AND COALESCE(target.physical_country_id, -1) = COALESCE(source.physical_country_id, -1)
      AND COALESCE(target.unit_size_id, -1) = COALESCE(source.unit_size_id, -1)
      AND COALESCE(target.status_id, -1) = COALESCE(source.status_id, -1)
    WHEN MATCHED AND (
            target.exists_count <> source.exists_count
         OR target.stats_summary IS DISTINCT FROM source.stats_summary)
        THEN UPDATE SET
            exists_count = source.exists_count,
            exists_change = source.exists_change,
            exists_added_count = source.exists_added_count,
            exists_removed_count = source.exists_removed_count,
            countable_count = source.countable_count,
            countable_change = source.countable_change,
            countable_added_count = source.countable_added_count,
            countable_removed_count = source.countable_removed_count,
            births = source.births,
            deaths = source.deaths,
            name_change_count = source.name_change_count,
            primary_activity_category_change_count = source.primary_activity_category_change_count,
            secondary_activity_category_change_count = source.secondary_activity_category_change_count,
            sector_change_count = source.sector_change_count,
            legal_form_change_count = source.legal_form_change_count,
            physical_region_change_count = source.physical_region_change_count,
            physical_country_change_count = source.physical_country_change_count,
            physical_address_change_count = source.physical_address_change_count,
            unit_size_change_count = source.unit_size_change_count,
            status_change_count = source.status_change_count,
            stats_summary = source.stats_summary
    WHEN NOT MATCHED BY TARGET
        THEN INSERT (
            resolution, year, month, unit_type,
            primary_activity_category_path, secondary_activity_category_path,
            sector_path, legal_form_id, physical_region_path,
            physical_country_id, unit_size_id, status_id,
            exists_count, exists_change, exists_added_count, exists_removed_count,
            countable_count, countable_change, countable_added_count, countable_removed_count,
            births, deaths,
            name_change_count, primary_activity_category_change_count,
            secondary_activity_category_change_count, sector_change_count,
            legal_form_change_count, physical_region_change_count,
            physical_country_change_count, physical_address_change_count,
            unit_size_change_count, status_change_count,
            stats_summary)
        VALUES (
            source.resolution, source.year, source.month, source.unit_type,
            source.primary_activity_category_path, source.secondary_activity_category_path,
            source.sector_path, source.legal_form_id, source.physical_region_path,
            source.physical_country_id, source.unit_size_id, source.status_id,
            source.exists_count, source.exists_change, source.exists_added_count, source.exists_removed_count,
            source.countable_count, source.countable_change, source.countable_added_count, source.countable_removed_count,
            source.births, source.deaths,
            source.name_change_count, source.primary_activity_category_change_count,
            source.secondary_activity_category_change_count, source.sector_change_count,
            source.legal_form_change_count, source.physical_region_change_count,
            source.physical_country_change_count, source.physical_address_change_count,
            source.unit_size_change_count, source.status_change_count,
            source.stats_summary)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
    GET DIAGNOSTICS v_row_count := ROW_COUNT;

    p_info := jsonb_build_object(
        'mode', 'global',
        'dirty_hash_slots', to_jsonb(v_dirty_hash_slots),
        'rows_merged', v_row_count);

    -- Clean up dirty partitions at the very end, after all consumers have read them.
    -- (statistical_unit_facet_reduce ran earlier in the pipeline and read dirty_hash_slots
    -- for diagnostic logging; truncating here is safe because no later step needs it.)
    TRUNCATE public.statistical_unit_facet_dirty_hash_slots;

    PERFORM pg_notify('worker_status',
        json_build_object('type', 'is_deriving_reports', 'status', false)::text);
END;
$procedure$

;

CREATE OR REPLACE FUNCTION worker.enqueue_derive_statistical_history_facet_period(p_resolution history_resolution, p_year integer, p_month integer DEFAULT NULL::integer)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
BEGIN
  v_payload := jsonb_build_object(
    'command', 'derive_statistical_history_facet_period',
    'resolution', p_resolution::text,
    'year', p_year,
    'month', p_month  -- NULL for year resolution
  );

  INSERT INTO worker.tasks AS t (command, payload)
  VALUES ('derive_statistical_history_facet_period', v_payload)
  ON CONFLICT (command, (payload->>'resolution'), (payload->>'year'), (payload->>'month'))
  WHERE command = 'derive_statistical_history_facet_period' AND state = 'pending'::worker.task_state
  DO NOTHING
  RETURNING id INTO v_task_id;
  
  RETURN v_task_id;
END;
$function$

;

CREATE OR REPLACE PROCEDURE worker.command_collect_changes(IN p_payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_row RECORD;
    v_est_ids int4multirange := '{}'::int4multirange;
    v_lu_ids int4multirange := '{}'::int4multirange;
    v_ent_ids int4multirange := '{}'::int4multirange;
    v_pg_ids int4multirange := '{}'::int4multirange;
    v_valid_range datemultirange := '{}'::datemultirange;
    v_valid_from DATE;
    v_valid_until DATE;
    v_task_id BIGINT;
    v_phase1_id BIGINT;
    v_phase2_id BIGINT;
    v_payload JSONB;
    v_direct_mode BOOLEAN;
    v_all_units BOOLEAN;
BEGIN
    v_direct_mode :=
        p_payload ? 'establishment_id_ranges'
        OR p_payload ? 'legal_unit_id_ranges'
        OR p_payload ? 'enterprise_id_ranges'
        OR p_payload ? 'power_group_id_ranges';

    -- STATBUS-538: "everything" is one convention, carried through unchanged
    -- so every step decides from its own arguments: NULL for all four
    -- *_id_ranges means all units (worker.derive_statistical_unit's full
    -- branch), and valid_from = -infinity, valid_until = infinity means all
    -- time (the report derives then rebuild their whole per-slot cache).
    -- worker.enqueue_derive_statistical_unit_all() schedules exactly this.
    v_all_units := v_direct_mode
        AND NULLIF(p_payload->>'establishment_id_ranges', '') IS NULL
        AND NULLIF(p_payload->>'legal_unit_id_ranges', '') IS NULL
        AND NULLIF(p_payload->>'enterprise_id_ranges', '') IS NULL
        AND NULLIF(p_payload->>'power_group_id_ranges', '') IS NULL;

    IF v_all_units THEN
        -- All units: ids stay NULL, time defaults to all time. The full
        -- derive covers every logged change, so the log is drained too.
        v_est_ids := NULL;
        v_lu_ids := NULL;
        v_ent_ids := NULL;
        v_pg_ids := NULL;
        v_valid_range := COALESCE(
            NULLIF(p_payload->>'valid_ranges', '')::datemultirange,
            '{[-infinity,infinity)}'::datemultirange
        );
        DELETE FROM worker.base_change_log;
        UPDATE worker.base_change_log_has_pending SET has_pending = FALSE;
    ELSIF v_direct_mode THEN
        -- Caller supplied explicit ranges. A NULL / JSON-null value for a
        -- given key means "all ids of that kind" — synthesise from base
        -- tables, because worker.derive_statistical_unit reads a NULL kind
        -- next to explicit kinds as none.
        v_est_ids := COALESCE(
            NULLIF(p_payload->>'establishment_id_ranges', '')::int4multirange,
            COALESCE(
                (SELECT range_agg(int4range(id, id, '[]'))::int4multirange FROM public.establishment),
                '{}'::int4multirange
            )
        );
        v_lu_ids := COALESCE(
            NULLIF(p_payload->>'legal_unit_id_ranges', '')::int4multirange,
            COALESCE(
                (SELECT range_agg(int4range(id, id, '[]'))::int4multirange FROM public.legal_unit),
                '{}'::int4multirange
            )
        );
        v_ent_ids := COALESCE(
            NULLIF(p_payload->>'enterprise_id_ranges', '')::int4multirange,
            COALESCE(
                (SELECT range_agg(int4range(id, id, '[]'))::int4multirange FROM public.enterprise),
                '{}'::int4multirange
            )
        );
        v_pg_ids := COALESCE(
            NULLIF(p_payload->>'power_group_id_ranges', '')::int4multirange,
            COALESCE(
                (SELECT range_agg(int4range(id, id, '[]'))::int4multirange FROM public.power_group),
                '{}'::int4multirange
            )
        );
        v_valid_range := COALESCE(
            NULLIF(p_payload->>'valid_ranges', '')::datemultirange,
            '{}'::datemultirange
        );
        UPDATE worker.base_change_log_has_pending SET has_pending = FALSE;
    ELSE
        -- Drain-log mode: unchanged from 20260319124229.
        FOR v_row IN DELETE FROM worker.base_change_log RETURNING * LOOP
            v_est_ids := v_est_ids + v_row.establishment_ids;
            v_lu_ids := v_lu_ids + v_row.legal_unit_ids;
            v_ent_ids := v_ent_ids + v_row.enterprise_ids;
            v_pg_ids := v_pg_ids + v_row.power_group_ids;
            v_valid_range := v_valid_range + v_row.valid_ranges;
        END LOOP;

        UPDATE worker.base_change_log_has_pending SET has_pending = FALSE;
    END IF;

    IF v_all_units
       OR v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange
       OR v_ent_ids != '{}'::int4multirange
       OR v_pg_ids != '{}'::int4multirange THEN

        -- Get own task_id for spawning children
        SELECT id INTO v_task_id
        FROM worker.tasks
        WHERE state = 'processing' AND worker_pid = pg_backend_pid()
        ORDER BY id DESC LIMIT 1;

        IF v_all_units THEN
            p_info := jsonb_build_object(
                'affected_establishment_count', (SELECT count(*) FROM public.establishment),
                'affected_legal_unit_count', (SELECT count(*) FROM public.legal_unit),
                'affected_enterprise_count', (SELECT count(*) FROM public.enterprise),
                'affected_power_group_count', (SELECT count(*) FROM public.power_group)
            );
        ELSE
            p_info := jsonb_build_object(
                'affected_establishment_count', (SELECT COALESCE(sum(upper(r) - lower(r)), 0) FROM unnest(v_est_ids) AS r),
                'affected_legal_unit_count', (SELECT COALESCE(sum(upper(r) - lower(r)), 0) FROM unnest(v_lu_ids) AS r),
                'affected_enterprise_count', (SELECT COALESCE(sum(upper(r) - lower(r)), 0) FROM unnest(v_ent_ids) AS r),
                'affected_power_group_count', (SELECT COALESCE(sum(upper(r) - lower(r)), 0) FROM unnest(v_pg_ids) AS r)
            );
        END IF;

        IF v_valid_range = '{}'::datemultirange THEN
            SELECT COALESCE(range_agg(vr)::datemultirange, '{}'::datemultirange)
            INTO v_valid_range
            FROM (
                SELECT valid_range AS vr FROM public.establishment AS est WHERE v_est_ids @> est.id
                UNION ALL
                SELECT valid_range AS vr FROM public.legal_unit AS lu WHERE v_lu_ids @> lu.id
            ) AS units;
        END IF;

        v_valid_from := lower(v_valid_range);
        v_valid_until := upper(v_valid_range);

        v_payload := jsonb_build_object(
            'valid_from', v_valid_from,
            'valid_until', v_valid_until
        );

        v_phase1_id := worker.spawn(
            p_command => 'derive_units_phase',
            p_payload => v_payload,
            p_parent_id => v_task_id,
            p_child_mode => 'serial'
        );

        PERFORM worker.spawn(
            p_command => 'derive_statistical_unit',
            p_payload => jsonb_build_object(
                'establishment_id_ranges', v_est_ids::text,
                'legal_unit_id_ranges', v_lu_ids::text,
                'enterprise_id_ranges', v_ent_ids::text,
                'power_group_id_ranges', v_pg_ids::text,
                'valid_from', v_valid_from,
                'valid_until', v_valid_until
            ),
            p_parent_id => v_phase1_id,
            p_child_mode => 'serial'
        );

        PERFORM worker.spawn(
            p_command => 'statistical_unit_flush_staging',
            p_payload => v_payload,
            p_parent_id => v_phase1_id,
            p_child_mode => 'serial'
        );

        -- BLOCK D: derive_used_tables runs AFTER statistical_unit_flush_staging
        -- has published activity/region/sector/… paths to public.statistical_unit.
        -- Previously these were invoked inline from worker.derive_statistical_unit,
        -- which ran before the flush — the views filtering on *_path IS NOT NULL
        -- returned 0 rows and *_used stayed empty on first-import cycles.
        PERFORM worker.spawn(
            p_command => 'derive_used_tables',
            p_payload => v_payload,
            p_parent_id => v_phase1_id,
            p_child_mode => 'serial'
        );

        v_phase2_id := worker.spawn(
            p_command => 'derive_reports_phase',
            p_payload => v_payload,
            p_parent_id => v_task_id,
            p_child_mode => 'serial'
        );

        PERFORM worker.spawn(
            p_command => 'derive_statistical_history',
            p_payload => v_payload,
            p_parent_id => v_phase2_id,
            p_child_mode => 'serial'
        );

        PERFORM worker.spawn(
            p_command => 'statistical_history_reduce',
            p_payload => v_payload,
            p_parent_id => v_phase2_id,
            p_child_mode => 'serial'
        );

        PERFORM worker.spawn(
            p_command => 'derive_statistical_unit_facet',
            p_payload => v_payload,
            p_parent_id => v_phase2_id,
            p_child_mode => 'serial'
        );

        PERFORM worker.spawn(
            p_command => 'statistical_unit_facet_reduce',
            p_payload => v_payload,
            p_parent_id => v_phase2_id,
            p_child_mode => 'serial'
        );

        PERFORM worker.spawn(
            p_command => 'derive_statistical_history_facet',
            p_payload => v_payload,
            p_parent_id => v_phase2_id,
            p_child_mode => 'serial'
        );

        PERFORM worker.spawn(
            p_command => 'statistical_history_facet_reduce',
            p_payload => v_payload,
            p_parent_id => v_phase2_id,
            p_child_mode => 'serial'
        );
    ELSE
        p_info := jsonb_build_object(
            'affected_establishment_count', 0,
            'affected_legal_unit_count', 0,
            'affected_enterprise_count', 0,
            'affected_power_group_count', 0
        );
        PERFORM pg_notify('worker_status',
            json_build_object('type', 'is_deriving_statistical_units', 'status', false)::text);
    END IF;
END;
$procedure$

;

CREATE OR REPLACE FUNCTION worker.derive_statistical_unit(p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange, p_power_group_id_ranges int4multirange DEFAULT NULL::int4multirange, p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_task_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_batch RECORD;
    v_establishment_ids INT[];
    v_legal_unit_ids INT[];
    v_enterprise_ids INT[];
    v_power_group_ids INT[];
    v_batch_count INT := 0;
    v_is_full_refresh BOOLEAN;
    v_orphan_enterprise_ids INT[];
    v_orphan_legal_unit_ids INT[];
    v_orphan_establishment_ids INT[];
    v_orphan_power_group_ids INT[];
    v_enterprise_count INT := 0;
    v_legal_unit_count INT := 0;
    v_establishment_count INT := 0;
    v_power_group_count INT := 0;
    v_pg_batch_size INT;
BEGIN
    v_is_full_refresh := (p_establishment_id_ranges IS NULL
                         AND p_legal_unit_id_ranges IS NULL
                         AND p_enterprise_id_ranges IS NULL
                         AND p_power_group_id_ranges IS NULL);

    IF v_is_full_refresh THEN
        FOR v_batch IN SELECT * FROM public.get_temporally_closed_change_sets(p_target_change_set_size => 1000)
        LOOP
            v_enterprise_count := v_enterprise_count + COALESCE(array_length(v_batch.enterprise_ids, 1), 0);
            v_legal_unit_count := v_legal_unit_count + COALESCE(array_length(v_batch.legal_unit_ids, 1), 0);
            v_establishment_count := v_establishment_count + COALESCE(array_length(v_batch.establishment_ids, 1), 0);

            PERFORM worker.spawn(
                p_command => 'statistical_unit_refresh_batch',
                p_payload => jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch.change_set_seq,
                    'enterprise_ids', v_batch.enterprise_ids,
                    'legal_unit_ids', v_batch.legal_unit_ids,
                    'establishment_ids', v_batch.establishment_ids,
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id => p_task_id
            );
            v_batch_count := v_batch_count + 1;
        END LOOP;

        v_power_group_ids := ARRAY(SELECT id FROM public.power_group ORDER BY id);
        v_power_group_count := COALESCE(array_length(v_power_group_ids, 1), 0);
        IF v_power_group_count > 0 THEN
            v_pg_batch_size := GREATEST(1, ceil(v_power_group_count::numeric / 64));
            FOR v_batch IN
                SELECT array_agg(pg_id ORDER BY pg_id) AS pg_ids
                FROM (SELECT pg_id, ((row_number() OVER (ORDER BY pg_id)) - 1) / v_pg_batch_size AS batch_idx
                      FROM unnest(v_power_group_ids) AS pg_id) AS t
                GROUP BY batch_idx ORDER BY batch_idx
            LOOP
                PERFORM worker.spawn(
                    p_command => 'statistical_unit_refresh_batch',
                    p_payload => jsonb_build_object(
                        'command', 'statistical_unit_refresh_batch',
                        'batch_seq', v_batch_count + 1,
                        'power_group_ids', v_batch.pg_ids,
                        'valid_from', p_valid_from,
                        'valid_until', p_valid_until
                    ),
                    p_parent_id => p_task_id
                );
                v_batch_count := v_batch_count + 1;
            END LOOP;
        END IF;
    ELSE
        v_establishment_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_establishment_id_ranges, '{}'::int4multirange)) AS t(r));
        v_legal_unit_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange)) AS t(r));
        v_enterprise_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_enterprise_id_ranges, '{}'::int4multirange)) AS t(r));
        v_power_group_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_power_group_id_ranges, '{}'::int4multirange)) AS t(r));

        IF COALESCE(array_length(v_enterprise_ids, 1), 0) > 0 THEN
            v_orphan_enterprise_ids := ARRAY(SELECT id FROM unnest(v_enterprise_ids) AS id EXCEPT SELECT e.id FROM public.enterprise AS e WHERE e.id = ANY(v_enterprise_ids));
            IF COALESCE(array_length(v_orphan_enterprise_ids, 1), 0) > 0 THEN
                DELETE FROM public.timepoints WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timeline_enterprise WHERE enterprise_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                INSERT INTO public.statistical_unit_facet_dirty_hash_slots (dirty_hash_slot)
                SELECT DISTINCT public.hash_slot('enterprise', id)
                FROM unnest(v_orphan_enterprise_ids) AS id
                ON CONFLICT DO NOTHING;
            END IF;
        END IF;
        IF COALESCE(array_length(v_legal_unit_ids, 1), 0) > 0 THEN
            v_orphan_legal_unit_ids := ARRAY(SELECT id FROM unnest(v_legal_unit_ids) AS id EXCEPT SELECT lu.id FROM public.legal_unit AS lu WHERE lu.id = ANY(v_legal_unit_ids));
            IF COALESCE(array_length(v_orphan_legal_unit_ids, 1), 0) > 0 THEN
                DELETE FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timeline_legal_unit WHERE legal_unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                INSERT INTO public.statistical_unit_facet_dirty_hash_slots (dirty_hash_slot)
                SELECT DISTINCT public.hash_slot('legal_unit', id)
                FROM unnest(v_orphan_legal_unit_ids) AS id
                ON CONFLICT DO NOTHING;
            END IF;
        END IF;
        IF COALESCE(array_length(v_establishment_ids, 1), 0) > 0 THEN
            v_orphan_establishment_ids := ARRAY(SELECT id FROM unnest(v_establishment_ids) AS id EXCEPT SELECT es.id FROM public.establishment AS es WHERE es.id = ANY(v_establishment_ids));
            IF COALESCE(array_length(v_orphan_establishment_ids, 1), 0) > 0 THEN
                DELETE FROM public.timepoints WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timeline_establishment WHERE establishment_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                INSERT INTO public.statistical_unit_facet_dirty_hash_slots (dirty_hash_slot)
                SELECT DISTINCT public.hash_slot('establishment', id)
                FROM unnest(v_orphan_establishment_ids) AS id
                ON CONFLICT DO NOTHING;
            END IF;
        END IF;
        IF COALESCE(array_length(v_power_group_ids, 1), 0) > 0 THEN
            v_orphan_power_group_ids := ARRAY(SELECT id FROM unnest(v_power_group_ids) AS id EXCEPT SELECT pg.id FROM public.power_group AS pg WHERE pg.id = ANY(v_power_group_ids));
            IF COALESCE(array_length(v_orphan_power_group_ids, 1), 0) > 0 THEN
                DELETE FROM public.timepoints WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.timeline_power_group WHERE power_group_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
                INSERT INTO public.statistical_unit_facet_dirty_hash_slots (dirty_hash_slot)
                SELECT DISTINCT public.hash_slot('power_group', id)
                FROM unnest(v_orphan_power_group_ids) AS id
                ON CONFLICT DO NOTHING;
            END IF;
        END IF;

        IF p_establishment_id_ranges IS NOT NULL
           OR p_legal_unit_id_ranges IS NOT NULL
           OR p_enterprise_id_ranges IS NOT NULL THEN
            IF to_regclass('pg_temp._change_sets') IS NOT NULL THEN DROP TABLE _change_sets; END IF;
            CREATE TEMP TABLE _change_sets ON COMMIT DROP AS
            SELECT * FROM public.get_temporally_closed_change_sets(
                p_target_change_set_size => 1000,
                p_establishment_id_ranges => NULLIF(p_establishment_id_ranges, '{}'::int4multirange),
                p_legal_unit_id_ranges => NULLIF(p_legal_unit_id_ranges, '{}'::int4multirange),
                p_enterprise_id_ranges => NULLIF(p_enterprise_id_ranges, '{}'::int4multirange)
            );
            INSERT INTO public.statistical_unit_facet_dirty_hash_slots (dirty_hash_slot)
            SELECT DISTINCT public.hash_slot(t.unit_type, t.unit_id)
            FROM (
                SELECT 'enterprise'::text AS unit_type, unnest(b.enterprise_ids) AS unit_id FROM _change_sets AS b
                UNION ALL SELECT 'legal_unit', unnest(b.legal_unit_ids) FROM _change_sets AS b
                UNION ALL SELECT 'establishment', unnest(b.establishment_ids) FROM _change_sets AS b
            ) AS t WHERE t.unit_id IS NOT NULL
            ON CONFLICT DO NOTHING;

            <<effective_counts>>
            DECLARE
                v_all_batch_est_ranges int4multirange;
                v_all_batch_lu_ranges int4multirange;
                v_all_batch_en_ranges int4multirange;
                v_propagated_lu int4multirange;
                v_propagated_en int4multirange;
                v_eff_est int4multirange;
                v_eff_lu int4multirange;
                v_eff_en int4multirange;
            BEGIN
                v_all_batch_est_ranges := (SELECT range_agg(int4range(id, id, '[]'))
                    FROM (SELECT unnest(establishment_ids) AS id FROM _change_sets) AS t);
                v_all_batch_lu_ranges := (SELECT range_agg(int4range(id, id, '[]'))
                    FROM (SELECT unnest(legal_unit_ids) AS id FROM _change_sets) AS t);
                v_all_batch_en_ranges := (SELECT range_agg(int4range(id, id, '[]'))
                    FROM (SELECT unnest(enterprise_ids) AS id FROM _change_sets) AS t);

                v_eff_est := NULLIF(
                    COALESCE(v_all_batch_est_ranges, '{}'::int4multirange)
                    * COALESCE(p_establishment_id_ranges, '{}'::int4multirange),
                    '{}'::int4multirange);

                SELECT range_agg(int4range(es.legal_unit_id, es.legal_unit_id, '[]'))
                  INTO v_propagated_lu
                  FROM public.establishment AS es
                 WHERE es.id <@ COALESCE(p_establishment_id_ranges, '{}'::int4multirange)
                   AND es.legal_unit_id IS NOT NULL;
                v_eff_lu := NULLIF(
                    COALESCE(v_all_batch_lu_ranges, '{}'::int4multirange)
                    * (COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange)
                     + COALESCE(v_propagated_lu, '{}'::int4multirange)),
                    '{}'::int4multirange);

                SELECT range_agg(int4range(lu.enterprise_id, lu.enterprise_id, '[]'))
                  INTO v_propagated_en
                  FROM public.legal_unit AS lu
                 WHERE lu.id <@ COALESCE(v_eff_lu, '{}'::int4multirange)
                   AND lu.enterprise_id IS NOT NULL;
                v_eff_en := NULLIF(
                    COALESCE(v_all_batch_en_ranges, '{}'::int4multirange)
                    * (COALESCE(p_enterprise_id_ranges, '{}'::int4multirange)
                     + COALESCE(v_propagated_en, '{}'::int4multirange)),
                    '{}'::int4multirange);

                v_establishment_count := COALESCE((SELECT count(*) FROM unnest(COALESCE(v_eff_est, '{}'::int4multirange)) AS r, generate_series(lower(r), upper(r)-1))::INT, 0);
                v_legal_unit_count := COALESCE((SELECT count(*) FROM unnest(COALESCE(v_eff_lu, '{}'::int4multirange)) AS r, generate_series(lower(r), upper(r)-1))::INT, 0);
                v_enterprise_count := COALESCE((SELECT count(*) FROM unnest(COALESCE(v_eff_en, '{}'::int4multirange)) AS r, generate_series(lower(r), upper(r)-1))::INT, 0);
            END effective_counts;

            FOR v_batch IN SELECT * FROM _change_sets LOOP
                PERFORM worker.spawn(
                    p_command => 'statistical_unit_refresh_batch',
                    p_payload => jsonb_build_object(
                        'command', 'statistical_unit_refresh_batch',
                        'batch_seq', v_batch.change_set_seq,
                        'enterprise_ids', v_batch.enterprise_ids,
                        'legal_unit_ids', v_batch.legal_unit_ids,
                        'establishment_ids', v_batch.establishment_ids,
                        'valid_from', p_valid_from,
                        'valid_until', p_valid_until,
                        'changed_establishment_id_ranges', p_establishment_id_ranges::text,
                        'changed_legal_unit_id_ranges', p_legal_unit_id_ranges::text,
                        'changed_enterprise_id_ranges', p_enterprise_id_ranges::text
                    ),
                    p_parent_id => p_task_id
                );
                v_batch_count := v_batch_count + 1;
            END LOOP;
        END IF;

        IF COALESCE(array_length(v_power_group_ids, 1), 0) > 0 THEN
            v_power_group_count := array_length(v_power_group_ids, 1);
            INSERT INTO public.statistical_unit_facet_dirty_hash_slots (dirty_hash_slot)
            SELECT DISTINCT public.hash_slot('power_group', pg_id)
            FROM unnest(v_power_group_ids) AS pg_id
            ON CONFLICT DO NOTHING;

            v_pg_batch_size := GREATEST(1, ceil(v_power_group_count::numeric / 64));
            FOR v_batch IN
                SELECT array_agg(pg_id ORDER BY pg_id) AS pg_ids
                FROM (SELECT pg_id, ((row_number() OVER (ORDER BY pg_id)) - 1) / v_pg_batch_size AS batch_idx
                      FROM unnest(v_power_group_ids) AS pg_id) AS t
                GROUP BY batch_idx ORDER BY batch_idx
            LOOP
                PERFORM worker.spawn(
                    p_command => 'statistical_unit_refresh_batch',
                    p_payload => jsonb_build_object(
                        'command', 'statistical_unit_refresh_batch',
                        'batch_seq', v_batch_count + 1,
                        'power_group_ids', v_batch.pg_ids,
                        'valid_from', p_valid_from,
                        'valid_until', p_valid_until
                    ),
                    p_parent_id => p_task_id
                );
                v_batch_count := v_batch_count + 1;
            END LOOP;
        END IF;
    END IF;

    RAISE DEBUG 'derive_statistical_unit: Spawned % batch children with parent_id %, counts: es=%, lu=%, en=%, pg=%',
        v_batch_count, p_task_id, v_establishment_count, v_legal_unit_count, v_enterprise_count, v_power_group_count;

    -- BLOCK B: *_used_derive() calls removed. See worker.derive_used_tables
    -- (spawned as a serial child of derive_units_phase AFTER flush_staging).

    RETURN jsonb_build_object(
        'effective_establishment_count', v_establishment_count,
        'effective_legal_unit_count', v_legal_unit_count,
        'effective_enterprise_count', v_enterprise_count,
        'effective_power_group_count', v_power_group_count,
        'batch_count', v_batch_count
    );
END;
$function$

;

CREATE OR REPLACE FUNCTION admin.apply_rls_to_all_tables()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- To list all tables in public schema, run in psql:
    -- SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;
    --
    -- ########### add_rls_regular_user_can_read ###########
    PERFORM admin.add_rls_regular_user_can_read('public.activity_category'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.region'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.sector'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.legal_form'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.activity_category_standard'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.settings'::regclass);
    -- We don't need to apply the standard RLS function to activity_category_access
    -- as it has custom policies that only allow admin_user to modify it
    -- PERFORM admin.add_rls_regular_user_can_read('public.activity_category_access'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.country'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.data_source'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.tag'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.relative_period'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.unit_size'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.power_group_type'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.legal_reorg_type'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.legal_rel_type'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.foreign_participation'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.status'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.external_ident_type'::regclass);

    PERFORM admin.add_rls_regular_user_can_read('public.person_role'::regclass);
    -- We don't need to apply the standard RLS function to region_access
    -- as it has custom policies that only allow admin_user to modify it
    -- PERFORM admin.add_rls_regular_user_can_read('public.region_access'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.stat_definition'::regclass);
    -- Is updated by the statbus worker, using authorized functions.
    PERFORM admin.add_rls_regular_user_can_read('public.timepoints'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.timesegments'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.timesegments_years'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.timeline_establishment'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.timeline_legal_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.timeline_enterprise'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.statistical_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.activity_category_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.region_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.sector_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.data_source_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.legal_form_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.country_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.statistical_unit_facet'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.statistical_history'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.statistical_history_facet'::regclass);
    --
    -- ########### add_rls_regular_user_can_edit ###########
    PERFORM admin.add_rls_regular_user_can_edit('public.image'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.establishment'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.legal_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.enterprise'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.power_group'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.power_root'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.external_ident'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.activity'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.contact'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.unit_notes'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.tag_for_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.stat_for_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.person_for_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.person'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.location'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.legal_relationship'::regclass);
    --
END;
$function$

;

CREATE OR REPLACE FUNCTION public.reset(confirmed boolean, scope reset_scope)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    result JSONB := '{}'::JSONB;
    changed JSONB;
    _activity_count bigint;
    _location_count bigint;
    _contact_count bigint;
    _person_for_unit_count bigint;
    _person_count bigint;
    _tag_for_unit_count bigint;
    _stat_for_unit_count bigint;
    _external_ident_count bigint;
    _legal_relationship_count bigint;
    _power_root_count bigint;
    _establishment_count bigint;
    _legal_unit_count bigint;
    _enterprise_count bigint;
    _power_group_count bigint;
    _image_count bigint;
    _unit_notes_count bigint;
BEGIN
    IF NOT confirmed THEN
        RAISE EXCEPTION 'Action not confirmed.';
    END IF;

    -- ================================================================
    -- Scope: 'units' (and all broader scopes)
    -- ================================================================

    CASE WHEN scope IN ('units', 'data', 'getting-started', 'all') THEN
        SELECT COUNT(*) FROM public.activity INTO _activity_count;
        SELECT COUNT(*) FROM public.location INTO _location_count;
        SELECT COUNT(*) FROM public.contact INTO _contact_count;
        SELECT COUNT(*) FROM public.person_for_unit INTO _person_for_unit_count;
        SELECT COUNT(*) FROM public.person INTO _person_count;
        SELECT COUNT(*) FROM public.tag_for_unit INTO _tag_for_unit_count;
        SELECT COUNT(*) FROM public.stat_for_unit INTO _stat_for_unit_count;
        SELECT COUNT(*) FROM public.external_ident INTO _external_ident_count;
        SELECT COUNT(*) FROM public.legal_relationship INTO _legal_relationship_count;
        SELECT COUNT(*) FROM public.power_root INTO _power_root_count;
        SELECT COUNT(*) FROM public.establishment INTO _establishment_count;
        SELECT COUNT(*) FROM public.legal_unit INTO _legal_unit_count;
        SELECT COUNT(*) FROM public.enterprise INTO _enterprise_count;
        SELECT COUNT(*) FROM public.power_group INTO _power_group_count;
        SELECT COUNT(*) FROM public.image INTO _image_count;
        SELECT COUNT(*) FROM public.unit_notes INTO _unit_notes_count;

        TRUNCATE
            public.activity,
            public.location,
            public.contact,
            public.stat_for_unit,
            public.external_ident,
            public.person_for_unit,
            public.person,
            public.tag_for_unit,
            public.unit_notes,
            public.legal_relationship,
            public.power_root,
            public.establishment,
            public.legal_unit,
            public.enterprise,
            public.power_group,
            public.image,
            public.timeline_establishment,
            public.timeline_legal_unit,
            public.timeline_enterprise,
            public.timeline_power_group,
            public.timepoints,
            public.timesegments,
            public.timesegments_years,
            public.statistical_unit,
            public.statistical_unit_facet,
            public.statistical_unit_facet_staging,
            public.statistical_unit_facet_dirty_hash_slots,
            public.statistical_history,
            public.statistical_history_facet,
            public.statistical_history_facet_partitions;

        result := result
            || jsonb_build_object('activity', jsonb_build_object('deleted_count', _activity_count))
            || jsonb_build_object('location', jsonb_build_object('deleted_count', _location_count))
            || jsonb_build_object('contact', jsonb_build_object('deleted_count', _contact_count))
            || jsonb_build_object('person_for_unit', jsonb_build_object('deleted_count', _person_for_unit_count))
            || jsonb_build_object('person', jsonb_build_object('deleted_count', _person_count))
            || jsonb_build_object('tag_for_unit', jsonb_build_object('deleted_count', _tag_for_unit_count))
            || jsonb_build_object('stat_for_unit', jsonb_build_object('deleted_count', _stat_for_unit_count))
            || jsonb_build_object('external_ident', jsonb_build_object('deleted_count', _external_ident_count))
            || jsonb_build_object('legal_relationship', jsonb_build_object('deleted_count', _legal_relationship_count))
            || jsonb_build_object('power_root', jsonb_build_object('deleted_count', _power_root_count))
            || jsonb_build_object('establishment', jsonb_build_object('deleted_count', _establishment_count))
            || jsonb_build_object('legal_unit', jsonb_build_object('deleted_count', _legal_unit_count))
            || jsonb_build_object('enterprise', jsonb_build_object('deleted_count', _enterprise_count))
            || jsonb_build_object('power_group', jsonb_build_object('deleted_count', _power_group_count))
            || jsonb_build_object('image', jsonb_build_object('deleted_count', _image_count))
            || jsonb_build_object('unit_notes', jsonb_build_object('deleted_count', _unit_notes_count));
    ELSE END CASE;

    -- ================================================================
    -- Scope: 'data' (adds import cleanup)
    -- ================================================================

    CASE WHEN scope IN ('data', 'getting-started', 'all') THEN
        WITH deleted_import_job AS (
            DELETE FROM public.import_job WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'import_job', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_import_job)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    -- ================================================================
    -- Scope: 'getting-started' (adds config/reference cleanup)
    -- ================================================================

    CASE WHEN scope IN ('getting-started', 'all') THEN
        -- Transient: delete custom definitions before data_source due to RESTRICT FK. See doc/data-model.md
        WITH deleted_import_definition AS (
            DELETE FROM public.import_definition WHERE custom RETURNING *
        )
        SELECT jsonb_build_object(
            'import_definition', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_import_definition)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_region AS (
            DELETE FROM public.region WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'region', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_region)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_settings AS (
            DELETE FROM public.settings WHERE only_one_setting = TRUE RETURNING *
        )
        SELECT jsonb_build_object(
            'settings', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_settings)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_rv AS (
            DELETE FROM public.region_version WHERE custom RETURNING *
        ), changed_rv AS (
            UPDATE public.region_version SET enabled = TRUE
             WHERE NOT custom AND NOT enabled RETURNING *
        )
        SELECT jsonb_build_object('region_version', jsonb_build_object(
            'deleted_count', (SELECT COUNT(*) FROM deleted_rv),
            'changed_count', (SELECT COUNT(*) FROM changed_rv)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH activity_category_to_delete AS (
            SELECT to_delete.id AS id_to_delete
                 , replacement.id AS replacement_id
            FROM public.activity_category AS to_delete
            LEFT JOIN public.activity_category AS replacement
              ON to_delete.path = replacement.path
             AND to_delete.standard_id = replacement.standard_id
             AND NOT replacement.custom
            WHERE to_delete.custom
              AND to_delete.enabled
            ORDER BY to_delete.path
        ), updated_child AS (
            UPDATE public.activity_category AS child
               SET parent_id = to_delete.replacement_id
              FROM activity_category_to_delete AS to_delete
               WHERE to_delete.replacement_id IS NOT NULL
                 AND NOT child.custom
                 AND parent_id = to_delete.id_to_delete
            RETURNING *
        ), deleted_activity_category AS (
            DELETE FROM public.activity_category
             WHERE id in (SELECT id_to_delete FROM activity_category_to_delete)
            RETURNING *
        )
        SELECT jsonb_build_object(
            'deleted_count', (SELECT COUNT(*) FROM deleted_activity_category),
            'changed_children_count', (SELECT COUNT(*) FROM updated_child)
        ) INTO changed;

        WITH changed_activity_category AS (
            UPDATE public.activity_category
            SET enabled = TRUE
            WHERE NOT custom
              AND NOT enabled
            RETURNING *
        )
        SELECT changed || jsonb_build_object(
            'changed_count', (SELECT COUNT(*) FROM changed_activity_category)
        ) INTO changed;
        SELECT jsonb_build_object('activity_category', changed) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_sector AS (
            DELETE FROM public.sector WHERE custom RETURNING *
        ), changed_sector AS (
            UPDATE public.sector
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'sector', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_sector),
                'changed_count', (SELECT COUNT(*) FROM changed_sector)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_legal_form AS (
            DELETE FROM public.legal_form WHERE custom RETURNING *
        ), changed_legal_form AS (
            UPDATE public.legal_form
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'legal_form', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_legal_form),
                'changed_count', (SELECT COUNT(*) FROM changed_legal_form)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_unit_size AS (
            DELETE FROM public.unit_size WHERE custom RETURNING *
        ), changed_unit_size AS (
            UPDATE public.unit_size
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'unit_size', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_unit_size),
                'changed_count', (SELECT COUNT(*) FROM changed_unit_size)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_data_source AS (
            DELETE FROM public.data_source WHERE custom RETURNING *
        ), changed_data_source AS (
            UPDATE public.data_source
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'data_source', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_data_source),
                'changed_count', (SELECT COUNT(*) FROM changed_data_source)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_status AS (
            DELETE FROM public.status WHERE custom RETURNING *
        ), changed_status AS (
            UPDATE public.status
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'status', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_status),
                'changed_count', (SELECT COUNT(*) FROM changed_status)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_foreign_participation AS (
            DELETE FROM public.foreign_participation WHERE custom RETURNING *
        ), changed_foreign_participation AS (
            UPDATE public.foreign_participation
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'foreign_participation', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_foreign_participation),
                'changed_count', (SELECT COUNT(*) FROM changed_foreign_participation)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_legal_reorg_type AS (
            DELETE FROM public.legal_reorg_type WHERE custom RETURNING *
        ), changed_legal_reorg_type AS (
            UPDATE public.legal_reorg_type
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'legal_reorg_type', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_legal_reorg_type),
                'changed_count', (SELECT COUNT(*) FROM changed_legal_reorg_type)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_power_group_type AS (
            DELETE FROM public.power_group_type WHERE custom RETURNING *
        ), changed_power_group_type AS (
            UPDATE public.power_group_type
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'power_group_type', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_power_group_type),
                'changed_count', (SELECT COUNT(*) FROM changed_power_group_type)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'all') THEN
        WITH deleted_legal_rel_type AS (
            DELETE FROM public.legal_rel_type WHERE custom RETURNING *
        ), changed_legal_rel_type AS (
            UPDATE public.legal_rel_type
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'legal_rel_type', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_legal_rel_type),
                'changed_count', (SELECT COUNT(*) FROM changed_legal_rel_type)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    -- ================================================================
    -- Scope: 'all' (adds configuration reset)
    -- ================================================================

    CASE WHEN scope IN ('all') THEN
        WITH deleted_tag AS (
            DELETE FROM public.tag WHERE custom RETURNING *
        ), changed_tag AS (
            UPDATE public.tag
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'tag', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_tag),
                'changed_count', (SELECT COUNT(*) FROM changed_tag)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('all') THEN
        WITH deleted_stat_definition AS (
            DELETE FROM public.stat_definition WHERE true RETURNING *
        )
        SELECT jsonb_build_object(
            'stat_definition', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_stat_definition WHERE code NOT IN ('employees','turnover'))
            )
        ) INTO changed;
        result := result || changed;

        INSERT INTO public.stat_definition(code, type, frequency, name, description, priority, enabled)
        VALUES
            ('employees', 'int', 'yearly', 'Employees', 'The number of people receiving an official salary with government reporting.', 1, true),
            ('turnover', 'float', 'yearly', 'Turnover', 'The amount (Local Currency)', 2, true);
    ELSE END CASE;

    CASE WHEN scope IN ('all') THEN
        WITH deleted_external_ident_type AS (
            DELETE FROM public.external_ident_type WHERE true RETURNING *
        )
        SELECT jsonb_build_object(
            'external_ident_type', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_external_ident_type WHERE code NOT IN ('stat_ident','tax_ident','person_ident'))
            )
        ) INTO changed;
        result := result || changed;

        -- Fix 2: Include person_ident in baseline entries
        INSERT INTO public.external_ident_type(code, name, priority, description, enabled)
        VALUES
            ('tax_ident', 'Tax Identifier', 1, 'Stable and country unique identifier used for tax reporting.', true),
            ('stat_ident', 'Statistical Identifier', 2, 'Stable identifier generated by Statbus', true),
            ('person_ident', 'Person Identifier', 10, 'Personal identification number (national ID, passport, etc.)', true);
    ELSE END CASE;

    -- activity_category_standard is system seed data (isic_v4, nace_v2.1) and must
    -- never be deleted by reset(). Custom activity_categories are already handled
    -- by the 'getting-started' scope block above.

    RETURN result;
END;
$function$

;

COMMENT ON FUNCTION public.statistical_history_def(public.history_resolution, integer, integer, int4range) IS 'Demographics and stats of statistical units for one history period, per hash slot, optionally limited to the units whose hash_slot lies in p_hash_partition. Planned for each call''s own values (plan_cache_mode = force_custom_plan): the number of units a call covers depends on the partition range and the period, and a generic plan that cannot see them chose nested-loop joins that grow quadratically with the units (STATBUS-555).';

INSERT INTO worker.command_registry (command, handler_procedure, description, queue) VALUES
    ('derive_statistical_history', 'worker.derive_statistical_history', 'Derive statistical history aggregations', 'analytics'),
    ('derive_statistical_history_period', 'worker.derive_statistical_history_period', 'Derive statistical history for a single period (resolution/year/month)', 'analytics'),
    ('statistical_history_reduce', 'worker.statistical_history_reduce', 'Aggregate partition entries into root entries for statistical_history', 'analytics'),
    ('derive_statistical_history_facet', 'worker.derive_statistical_history_facet', 'Derive statistical history facets', 'analytics'),
    ('derive_statistical_history_facet_period', 'worker.derive_statistical_history_facet_period', 'Derive statistical history facets for a single period (resolution/year/month)', 'analytics'),
    ('statistical_history_facet_reduce', 'worker.statistical_history_facet_reduce', 'Aggregate partition entries into root entries for statistical_history_facet', 'analytics');
INSERT INTO worker.pipeline_step_weight (step, weight, seq, phase) VALUES
    ('derive_statistical_history', 2, 4, 'is_deriving_reports'),
    ('statistical_history_reduce', 1, 5, 'is_deriving_reports'),
    ('derive_statistical_history_facet', 84, 8, 'is_deriving_reports'),
    ('statistical_history_facet_reduce', 9, 9, 'is_deriving_reports');

-- admin.adjust_partition_count_target as before, with its thresholds inline.
CREATE OR REPLACE PROCEDURE admin.adjust_partition_count_target()
 LANGUAGE plpgsql
 SET search_path TO 'admin', 'public', 'pg_temp'
AS $procedure$
DECLARE
    v_unit_count bigint;
    v_desired    integer;
BEGIN
    SELECT count(*) INTO v_unit_count FROM public.statistical_unit;
    -- Thresholds tuned for 16384-slot space; keep target small for tiny
    -- datasets, scale up as unit count grows. See proposal §7.
    v_desired := CASE
        WHEN v_unit_count <=      100 THEN     4
        WHEN v_unit_count <=   10000 THEN    16
        WHEN v_unit_count <=  100000 THEN    64
        WHEN v_unit_count <= 1000000 THEN   128
        WHEN v_unit_count <= 5000000 THEN   256
        ELSE                                 512
    END;
    UPDATE public.settings
       SET partition_count_target = v_desired
     WHERE partition_count_target IS DISTINCT FROM v_desired;
END;
$procedure$
;

DROP FUNCTION public.partition_count_target_for(bigint);

-- statistical_history_drilldown as before (params materialised).
CREATE OR REPLACE FUNCTION public.statistical_history_drilldown(unit_type statistical_unit_type DEFAULT 'enterprise'::statistical_unit_type, resolution history_resolution DEFAULT 'year'::history_resolution, year integer DEFAULT NULL::integer, region_path ltree DEFAULT NULL::ltree, activity_category_path ltree DEFAULT NULL::ltree, sector_path ltree DEFAULT NULL::ltree, status_id integer DEFAULT NULL::integer, legal_form_id integer DEFAULT NULL::integer, country_id integer DEFAULT NULL::integer, year_min integer DEFAULT NULL::integer, year_max integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    -- Use a params intermediary to avoid conflicts
    -- between columns and parameters, leading to tautologies. i.e. 'sh.resolution = resolution' is always true.
    WITH params AS (
        SELECT
            unit_type AS param_unit_type,
            resolution AS param_resolution,
            year AS param_year,
            region_path AS param_region_path,
            activity_category_path AS param_activity_category_path,
            sector_path AS param_sector_path,
            legal_form_id AS param_legal_form_id,
            status_id AS param_status_id,
            country_id AS param_country_id
    ), settings_activity_category_standard AS (
        SELECT activity_category_standard_id AS id FROM public.settings
    ),
    available_history AS (
        SELECT sh.*
        FROM public.statistical_history_facet AS sh
           , params
        WHERE (param_unit_type IS NULL OR sh.unit_type = param_unit_type)
          AND (param_resolution IS NULL OR sh.resolution = param_resolution)
          AND (param_year IS NULL OR sh.year = param_year)
          AND (
              param_region_path IS NULL
              OR sh.physical_region_path IS NOT NULL AND sh.physical_region_path OPERATOR(public.<@) param_region_path
              )
          AND (
              param_activity_category_path IS NULL
              OR sh.primary_activity_category_path IS NOT NULL AND sh.primary_activity_category_path OPERATOR(public.<@) param_activity_category_path
              )
          AND (
              param_sector_path IS NULL
              OR sh.sector_path IS NOT NULL AND sh.sector_path OPERATOR(public.<@) param_sector_path
              )
          AND (
              param_legal_form_id IS NULL
              OR sh.legal_form_id IS NOT NULL AND sh.legal_form_id = param_legal_form_id
              )
          AND (
              param_status_id IS NULL
              OR sh.status_id IS NOT NULL AND sh.status_id = param_status_id
              )
          AND (
              param_country_id IS NULL
              OR sh.physical_country_id IS NOT NULL AND sh.physical_country_id = param_country_id
              )
          AND (
              statistical_history_drilldown.year_min IS NULL
              OR sh.year IS NOT NULL AND sh.year >= statistical_history_drilldown.year_min
              )
          AND (
              statistical_history_drilldown.year_max IS NULL
              OR sh.year IS NOT NULL AND sh.year <= statistical_history_drilldown.year_max
              )
    ), available_history_stats AS (
        SELECT
            ah.year, ah.month
            -- Sum up all the demographic and change counts across the filtered facets
            , COALESCE(SUM(ah.exists_count), 0)::integer AS exists_count
            , COALESCE(SUM(ah.exists_change), 0)::integer AS exists_change
            , COALESCE(SUM(ah.exists_added_count), 0)::integer AS exists_added_count
            , COALESCE(SUM(ah.exists_removed_count), 0)::integer AS exists_removed_count
            , COALESCE(SUM(ah.countable_count), 0)::integer AS countable_count
            , COALESCE(SUM(ah.countable_change), 0)::integer AS countable_change
            , COALESCE(SUM(ah.countable_added_count), 0)::integer AS countable_added_count
            , COALESCE(SUM(ah.countable_removed_count), 0)::integer AS countable_removed_count
            , COALESCE(SUM(ah.births), 0)::integer AS births
            , COALESCE(SUM(ah.deaths), 0)::integer AS deaths
            , COALESCE(SUM(ah.name_change_count), 0)::integer AS name_change_count
            , COALESCE(SUM(ah.primary_activity_category_change_count), 0)::integer AS primary_activity_category_change_count
            , COALESCE(SUM(ah.secondary_activity_category_change_count), 0)::integer AS secondary_activity_category_change_count
            , COALESCE(SUM(ah.sector_change_count), 0)::integer AS sector_change_count
            , COALESCE(SUM(ah.legal_form_change_count), 0)::integer AS legal_form_change_count
            , COALESCE(SUM(ah.physical_region_change_count), 0)::integer AS physical_region_change_count
            , COALESCE(SUM(ah.physical_country_change_count), 0)::integer AS physical_country_change_count
            , COALESCE(SUM(ah.physical_address_change_count), 0)::integer AS physical_address_change_count
            , COALESCE(SUM(ah.unit_size_change_count), 0)::integer AS unit_size_change_count
            , COALESCE(SUM(ah.status_change_count), 0)::integer AS status_change_count
            , COALESCE(public.jsonb_stats_merge_agg(ah.stats_summary), '{}'::jsonb) AS stats_summary
        FROM available_history AS ah
        GROUP BY ah.year, ah.month
        ORDER BY year ASC, month ASC NULLS FIRST
    ),
    breadcrumb_region AS (
        SELECT r.path
             , r.label
             , r.code
             , r.name
        FROM public.region AS r
        WHERE
            (   region_path IS NOT NULL
            AND r.path OPERATOR(public.@>) (region_path)
            )
        ORDER BY path
    ),
    available_region AS (
        SELECT r.path
             , r.label
             , r.code
             , r.name
        FROM public.region AS r
        WHERE
            (
                (region_path IS NULL AND r.path OPERATOR(public.~) '*{1}'::public.lquery)
            OR
                (region_path IS NOT NULL AND r.path OPERATOR(public.~) (region_path::text || '.*{1}')::public.lquery)
            )
        ORDER BY r.path
    ), aggregated_region_counts AS (
        SELECT ar.path
             , ar.label
             , ar.code
             , ar.name
             , COALESCE(SUM(sh.countable_count), 0) AS count
             , COALESCE(bool_or(true) FILTER (WHERE sh.physical_region_path OPERATOR(public.<>) ar.path), false) AS has_children
        FROM available_region AS ar
        LEFT JOIN available_history AS sh ON sh.physical_region_path OPERATOR(public.<@) ar.path
        GROUP BY ar.path
               , ar.label
               , ar.code
               , ar.name
    ),
    breadcrumb_activity_category AS (
        SELECT ac.path
             , ac.label
             , ac.code
             , ac.name
        FROM
            public.activity_category AS ac
        WHERE ac.enabled
           AND ac.standard_id = (SELECT id FROM settings_activity_category_standard)
           AND
            (     activity_category_path IS NOT NULL
              AND ac.path OPERATOR(public.@>) activity_category_path
            )
        ORDER BY path
    ),
    available_activity_category AS (
        SELECT ac.path
             , ac.label
             , ac.code
             , ac.name
        FROM
            public.activity_category AS ac
        WHERE ac.enabled
           AND ac.standard_id = (SELECT id FROM settings_activity_category_standard)
           AND
            (
                (activity_category_path IS NULL AND ac.path OPERATOR(public.~) '*{1}'::public.lquery)
            OR
                (activity_category_path IS NOT NULL AND ac.path OPERATOR(public.~) (activity_category_path::text || '.*{1}')::public.lquery)
            )
        ORDER BY ac.path
    ),
    aggregated_activity_counts AS (
        SELECT aac.path
             , aac.label
             , aac.code
             , aac.name
             , COALESCE(SUM(sh.countable_count), 0) AS count
             , COALESCE(bool_or(true) FILTER (WHERE sh.primary_activity_category_path OPERATOR(public.<>) aac.path), false) AS has_children
        FROM
            available_activity_category AS aac
        LEFT JOIN available_history AS sh ON sh.primary_activity_category_path OPERATOR(public.<@) aac.path
        GROUP BY aac.path
               , aac.label
               , aac.code
               , aac.name
        ORDER BY aac.path
    ),
    breadcrumb_sector AS (
        SELECT s.path
             , s.label
             , s.code
             , s.name
        FROM public.sector AS s
        WHERE
            (   sector_path IS NOT NULL
            AND s.path OPERATOR(public.@>) (sector_path)
            )
        ORDER BY s.path
    ),
    available_sector AS (
        SELECT "as".path
             , "as".label
             , "as".code
             , "as".name
        FROM public.sector AS "as"
        WHERE
            (
                (sector_path IS NULL AND "as".path OPERATOR(public.~) '*{1}'::public.lquery)
            OR
                (sector_path IS NOT NULL AND "as".path OPERATOR(public.~) (sector_path::text || '.*{1}')::public.lquery)
            )
        ORDER BY "as".path
    ), aggregated_sector_counts AS (
        SELECT "as".path
             , "as".label
             , "as".code
             , "as".name
             , COALESCE(SUM(sh.countable_count), 0) AS count
             , COALESCE(bool_or(true) FILTER (WHERE sh.sector_path OPERATOR(public.<>) "as".path), false) AS has_children
        FROM available_sector AS "as"
        LEFT JOIN available_history AS sh ON sh.sector_path OPERATOR(public.<@) "as".path
        GROUP BY "as".path
               , "as".label
               , "as".code
               , "as".name
       ORDER BY "as".path
    ),
    breadcrumb_legal_form AS (
        SELECT lf.id
             , lf.code
             , lf.name
        FROM public.legal_form AS lf
        WHERE
            (   legal_form_id IS NOT NULL
            AND lf.id = legal_form_id
            )
        ORDER BY lf.code
    ),
    available_legal_form AS (
        SELECT lf.id
             , lf.code
             , lf.name
        FROM public.legal_form AS lf
        -- Every sector is available, unless one is selected.
        WHERE legal_form_id IS NULL
        ORDER BY lf.code
    ), aggregated_legal_form_counts AS (
        SELECT lf.id
             , lf.code
             , lf.name
             , COALESCE(SUM(sh.countable_count), 0) AS count
             , false AS has_children
        FROM available_legal_form AS lf
        LEFT JOIN available_history AS sh ON sh.legal_form_id = lf.id
        GROUP BY lf.id
               , lf.code
               , lf.name
        ORDER BY lf.code
    ),
    breadcrumb_status AS (
        SELECT s.id
             , s.code
             , s.name
        FROM public.status AS s
        WHERE
            (   status_id IS NOT NULL
            AND s.id = status_id
            )
        ORDER BY s.code
    ),
    available_status AS (
        SELECT s.id
             , s.code
             , s.name
        FROM public.status AS s
        -- Every status is available, unless one is selected.
        WHERE status_id IS NULL
        ORDER BY s.code
    ), aggregated_status_counts AS (
        SELECT s.id
             , s.code
             , s.name
             , COALESCE(SUM(sh.countable_count), 0) AS count
             , false AS has_children
        FROM available_status AS s
        LEFT JOIN available_history AS sh ON sh.status_id = s.id
        GROUP BY s.id
               , s.code
               , s.name
        ORDER BY s.code
    ),
    breadcrumb_physical_country AS (
        SELECT pc.id
             , pc.iso_2
             , pc.name
        FROM public.country AS pc
        WHERE
            (   country_id IS NOT NULL
            AND pc.id = country_id
            )
        ORDER BY pc.iso_2
    ),
    available_physical_country AS (
        SELECT pc.id
             , pc.iso_2
             , pc.name
        FROM public.country AS pc
        -- Every country is available, unless one is selected.
        WHERE country_id IS NULL
        ORDER BY pc.iso_2
    ), aggregated_physical_country_counts AS (
        SELECT pc.id
             , pc.iso_2
             , pc.name
             , COALESCE(SUM(sh.countable_count), 0) AS count
             , false AS has_children
        FROM available_physical_country AS pc
        LEFT JOIN available_history AS sh ON sh.physical_country_id = pc.id
        GROUP BY pc.id
               , pc.iso_2
               , pc.name
        ORDER BY pc.iso_2
    )
    SELECT
        jsonb_build_object(
          'unit_type', unit_type,
          'stats', (SELECT jsonb_agg(to_jsonb(source.*)) FROM available_history_stats AS source),
          'breadcrumb',jsonb_build_object(
            'region', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_region AS source),
            'activity_category', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_activity_category AS source),
            'sector', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_sector AS source),
            'legal_form', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_legal_form AS source),
            'status', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_status AS source),
            'country', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_physical_country AS source)
          ),
          'available',jsonb_build_object(
            'region', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_region_counts AS source WHERE count > 0),
            'activity_category', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_activity_counts AS source WHERE count > 0),
            'sector', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_sector_counts AS source WHERE count > 0),
            'legal_form', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_legal_form_counts AS source WHERE count > 0),
            'status', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_status_counts AS source WHERE count > 0),
            'country', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_physical_country_counts AS source WHERE count > 0)
          ),
          'filter',jsonb_build_object(
            'type',param_resolution,
            'year',param_year,
            'unit_type',param_unit_type,
            'region_path',param_region_path,
            'activity_category_path',param_activity_category_path,
            'sector_path',param_sector_path,
            'legal_form_id',param_legal_form_id,
            'status_id',param_status_id,
            'country_id',param_country_id
          )
        )
    FROM params;
$function$
;

-- statistical_history_highcharts as before (it read the statistical_history table).
CREATE OR REPLACE FUNCTION public.statistical_history_highcharts(p_resolution history_resolution, p_unit_type statistical_unit_type, p_year integer DEFAULT NULL::integer, p_series_codes text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    result            jsonb;
    v_filtered_codes  text[];
    v_static_codes    text[] := ARRAY[]::text[];
    v_merged_summary  jsonb;
    -- Schema-derived completion catalog. Built once per call from
    -- `public.stat_definition` × `jsonb_stats_to_agg(jsonb_stats_agg(code, stat(synthetic)))`.
    -- Drives HINT enumeration in the partial-path / bogus-leaf / typo branches;
    -- independent of whether any `statistical_history` rows exist.
    v_catalog_summary jsonb  := '{}'::jsonb;
    v_sd              record;
    v_req_code        text;
    v_path            text[];
    v_node            jsonb;
    v_msgs            text[] := ARRAY[]::text[];
    v_hints           text[] := ARRAY[]::text[];
BEGIN
    -- Static catalog: 18 historical-change codes plus a single bootstrap entry for the
    -- top-level 'stats_summary' partial. The bootstrap is advertised in `available_series`
    -- so callers can discover that more paths exist beyond the static set; it is itself
    -- never emitted as a series (resolution treats it as a partial and raises an error).
    IF to_regclass('pg_temp.series_definition') IS NOT NULL THEN DROP TABLE series_definition; END IF;
    CREATE TEMP TABLE series_definition(priority int, is_default boolean, code text PRIMARY KEY, name text) ON COMMIT DROP;
    INSERT INTO series_definition(priority, is_default, code, name)
    VALUES
        (10,  true,  'countable_count',                          'Unit Count'),
        (11,  false, 'countable_change',                         'Unit Count Change'),
        (12,  false, 'countable_added_count',                    'Units Added (Countable)'),
        (13,  false, 'countable_removed_count',                  'Units Removed (Countable)'),
        (14,  false, 'exists_count',                             'Existing Units'),
        (15,  false, 'exists_change',                            'Existing Units Change'),
        (16,  false, 'exists_added_count',                       'Units Added (Existence)'),
        (17,  false, 'exists_removed_count',                     'Units Removed (Existence)'),
        (20,  true , 'births',                                   'Births'),
        (30,  true , 'deaths',                                   'Deaths'),
        (40,  false, 'name_change_count',                        'Name Changes'),
        (50,  true , 'primary_activity_category_change_count',   'Primary Activity Changes'),
        (60,  false, 'secondary_activity_category_change_count', 'Secondary Activity Changes'),
        (70,  false, 'sector_change_count',                      'Sector Changes'),
        (80,  false, 'legal_form_change_count',                  'Legal Form Changes'),
        (90,  true , 'physical_region_change_count',             'Region Changes'),
        (100, false, 'physical_country_change_count',            'Country Changes'),
        (110, false, 'physical_address_change_count',            'Physical Address Changes'),
        (200, false, 'stats_summary',                            'Statistics Summary');

    -- Holds (code, jsonb_path) for every requested stats path that resolved to a numeric leaf.
    -- IDENTITY column preserves the caller-supplied order in the response.
    IF to_regclass('pg_temp.stats_path_buffer') IS NOT NULL THEN DROP TABLE stats_path_buffer; END IF;
    CREATE TEMP TABLE stats_path_buffer(
        ord        int GENERATED ALWAYS AS IDENTITY,
        code       text PRIMARY KEY,
        jsonb_path text[]
    ) ON COMMIT DROP;

    -- Compute the merged stats_summary once. Used for ACCEPTANCE (jsonb_typeof check) and
    -- for the actual numeric data extraction in the `series` payload.
    SELECT COALESCE(public.jsonb_stats_merge_agg(sh.stats_summary), '{}'::jsonb)
    INTO v_merged_summary
    FROM public.statistical_history sh
    WHERE sh.resolution = p_resolution
      AND sh.unit_type  = p_unit_type
      AND (p_year IS NULL OR sh.year = p_year);

    -- Build v_catalog_summary from schema. One synthetic-value pass per enabled stat
    -- yields the canonical leaf-bearing shape that `jsonb_stats_merge_agg` would
    -- produce over real data. Per-call cost is negligible (stat_definition is tiny).
    -- Polymorphism note: `stat()` is anyelement — a single CASE expression with
    -- different-typed branches won't compile. PL/pgSQL IF/ELSIF per type sidesteps it.
    FOR v_sd IN SELECT sd.code, sd.type::text AS type_text
                FROM public.stat_definition AS sd
                WHERE sd.enabled
                ORDER BY sd.code
    LOOP
        IF v_sd.type_text = 'int' THEN
            v_catalog_summary := v_catalog_summary || jsonb_build_object(
                v_sd.code,
                (public.jsonb_stats_to_agg(public.jsonb_stats_agg(v_sd.code, public.stat(0))) -> v_sd.code)
            );
        ELSIF v_sd.type_text = 'float' THEN
            v_catalog_summary := v_catalog_summary || jsonb_build_object(
                v_sd.code,
                (public.jsonb_stats_to_agg(public.jsonb_stats_agg(v_sd.code, public.stat(0.0::float8))) -> v_sd.code)
            );
        ELSIF v_sd.type_text = 'string' THEN
            v_catalog_summary := v_catalog_summary || jsonb_build_object(
                v_sd.code,
                (public.jsonb_stats_to_agg(public.jsonb_stats_agg(v_sd.code, public.stat(''::text))) -> v_sd.code)
            );
        ELSIF v_sd.type_text = 'bool' THEN
            v_catalog_summary := v_catalog_summary || jsonb_build_object(
                v_sd.code,
                (public.jsonb_stats_to_agg(public.jsonb_stats_agg(v_sd.code, public.stat(false))) -> v_sd.code)
            );
        ELSE
            -- New stat_type added to the enum without updating this function — fail loudly
            -- (catalog would be silently incomplete; HINTs would drop the unknown type).
            RAISE EXCEPTION 'statistical_history_highcharts: unhandled stat_type %', v_sd.type_text;
        END IF;
    END LOOP;

    -- Resolve each requested code in caller-supplied order.
    IF p_series_codes IS NOT NULL AND cardinality(p_series_codes) > 0 THEN
        FOREACH v_req_code IN ARRAY p_series_codes LOOP
            -- §A: collapse trailing dots and repeated internal dot runs so
            -- 'stats_summary.' → 'stats_summary' (top-level partial),
            -- 'stats_summary..turnover' → 'stats_summary.turnover' (no empty segment in v_path).
            v_req_code := regexp_replace(v_req_code, '\.+$', '');
            v_req_code := regexp_replace(v_req_code, '\.{2,}', '.', 'g');

            IF EXISTS (SELECT 1 FROM series_definition sd WHERE sd.code = v_req_code AND sd.code <> 'stats_summary') THEN
                -- Static code: extracted from a fixed column of public.statistical_history.
                v_static_codes := v_static_codes || v_req_code;

            ELSIF v_req_code = 'stats_summary' OR v_req_code LIKE 'stats_summary.%' THEN
                v_path := CASE
                    WHEN v_req_code = 'stats_summary'
                        THEN ARRAY[]::text[]
                    ELSE string_to_array(substr(v_req_code, length('stats_summary.') + 1), '.')
                END;

                IF 'type' = ANY(v_path) THEN
                    -- Bookkeeping segments are not addressable.
                    v_msgs := v_msgs || format('Unknown series code "%s"', v_req_code);
                    CONTINUE;
                END IF;

                -- Resolve the path shape from real data first; fall back to the
                -- schema-derived catalog when the filter slice is empty. This unifies
                -- the user-visible vocabulary across empty- and present-data cases:
                -- `stats_summary.employees` on year=9999 must say "Incomplete series
                -- code" (not "Unknown") just as it does on a year with data, since
                -- the path IS structurally valid. Data lookup in the `stats_pairs`
                -- CTE below still reads `b.stats_summary` from real rows — only the
                -- shape/acceptance check shifts to catalog when data is absent.
                v_node := COALESCE(v_merged_summary #> v_path, v_catalog_summary #> v_path);

                CASE jsonb_typeof(v_node)
                    WHEN 'number' THEN
                        INSERT INTO stats_path_buffer(code, jsonb_path) VALUES (v_req_code, v_path)
                        ON CONFLICT (code) DO NOTHING;  -- caller may pass a duplicate; first wins
                    WHEN 'null' THEN
                        -- Catalog (and real data) emit JSON null for statistics
                        -- undefined on the sample: stddev / variance /
                        -- coefficient_of_variation_pct when count<2 or variance=0.
                        -- The path is a STRUCTURALLY VALID leaf; the value is
                        -- legitimately null. Accept the leaf; the extraction CTE
                        -- below converts jsonb 'null' → SQL NULL so the data
                        -- pair `[ts, null]` flows through to Highcharts as a gap.
                        -- Single arm covers both catalog-null (empty slice) and
                        -- data-null (populated slice with single-sample row).
                        INSERT INTO stats_path_buffer(code, jsonb_path) VALUES (v_req_code, v_path)
                        ON CONFLICT (code) DO NOTHING;
                    WHEN 'object' THEN
                        v_msgs := v_msgs || format('Incomplete series code "%s"', v_req_code);
                        -- HINT enumerates valid sub-keys from the SCHEMA-DERIVED catalog
                        -- (independent of whether real data is populated). COALESCE retained
                        -- as defensive fallback for paths catalog can't enumerate.
                        v_hints := v_hints || COALESCE(
                            (SELECT 'Try one of: ' || string_agg(format('%s.%s', v_req_code, k), ', ' ORDER BY k)
                               FROM jsonb_object_keys(v_catalog_summary #> v_path) AS k
                              WHERE k <> 'type'),
                            format('No completions available under "%s"', v_req_code)
                        );
                    ELSE
                        -- §B: real data has nothing at this path. Try to give a useful HINT
                        -- from the catalog: if v_path[1] is a known stat, list its leaves;
                        -- otherwise list valid top-level stats. Plan calls this the
                        -- "bogus leaf" enhancement; extended to cardinality >= 1 so the
                        -- empty-data `stats_summary.<known_stat>` case also gets help.
                        v_msgs := v_msgs || format('Unknown series code "%s"', v_req_code);
                        IF cardinality(v_path) >= 1 AND jsonb_typeof(v_catalog_summary -> v_path[1]) = 'object' THEN
                            v_hints := v_hints || (
                                SELECT 'Try one of: ' || string_agg(format('stats_summary.%s.%s', v_path[1], k), ', ' ORDER BY k)
                                  FROM jsonb_object_keys(v_catalog_summary -> v_path[1]) AS k
                                 WHERE k <> 'type'
                            );
                        ELSIF cardinality(v_path) >= 1 AND v_catalog_summary <> '{}'::jsonb THEN
                            v_hints := v_hints || (
                                SELECT 'Try one of: ' || string_agg('stats_summary.' || k, ', ' ORDER BY k)
                                  FROM jsonb_object_keys(v_catalog_summary) AS k
                            );
                        END IF;
                END CASE;

            ELSE
                -- §C: caller passed a code that's neither a known static series nor a
                -- `stats_summary[.…]` path — likely a typo (`jsonb_stats`, `tunover`, …).
                -- Suggest the full set of valid top-level codes: static catalog (minus the
                -- bootstrap 'stats_summary' partial) UNION `stats_summary.<stat>` from catalog.
                v_msgs := v_msgs || format('Unknown series code "%s"', v_req_code);
                v_hints := v_hints || (
                    SELECT 'Try one of: ' || string_agg(code, ', ' ORDER BY code) FROM (
                        SELECT code FROM series_definition WHERE code <> 'stats_summary'
                        UNION ALL
                        SELECT 'stats_summary.' || k FROM jsonb_object_keys(v_catalog_summary) AS k
                    ) AS t
                );
            END IF;
        END LOOP;

        IF cardinality(v_msgs) > 0 THEN
            DECLARE
                v_hint_text text := NULLIF(array_to_string(v_hints, E'\n'), '');
            BEGIN
                -- USING HINT = NULL is rejected by PG; emit a HINT-less RAISE in that case.
                IF v_hint_text IS NOT NULL THEN
                    RAISE EXCEPTION '%', array_to_string(v_msgs, '; ') USING HINT = v_hint_text;
                ELSE
                    RAISE EXCEPTION '%', array_to_string(v_msgs, '; ');
                END IF;
            END;
        END IF;
    END IF;

    -- Default-on selection: when caller passed nothing, fall back to is_default static codes.
    IF p_series_codes IS NULL OR cardinality(p_series_codes) = 0 THEN
        v_static_codes := COALESCE((SELECT array_agg(code ORDER BY priority) FROM series_definition WHERE is_default), ARRAY[]::text[]);
    END IF;

    v_filtered_codes := v_static_codes
                     || COALESCE((SELECT array_agg(code ORDER BY ord) FROM stats_path_buffer), ARRAY[]::text[]);

    WITH base AS (
        -- Highcharts expects UTC milliseconds since epoch.
        SELECT
            extract(epoch FROM
                CASE p_resolution
                    WHEN 'year'       THEN make_timestamp(year, 1, 1, 0, 0, 0)
                    WHEN 'year-month' THEN make_timestamp(year, month, 1, 0, 0, 0)
                END
            )::bigint * 1000 AS ts_epoch_ms,
            exists_count, exists_change, exists_added_count, exists_removed_count,
            countable_count, countable_change, countable_added_count, countable_removed_count,
            births, deaths, name_change_count,
            primary_activity_category_change_count, secondary_activity_category_change_count,
            sector_change_count, legal_form_change_count, physical_region_change_count,
            physical_country_change_count, physical_address_change_count,
            stats_summary
        FROM public.statistical_history
        WHERE resolution = p_resolution
          AND unit_type  = p_unit_type
          AND (p_year IS NULL OR year = p_year)
    ),
    static_pairs AS (
                  SELECT 'countable_count'                          AS code, jsonb_build_array(ts_epoch_ms, countable_count)                          AS pair, ts_epoch_ms FROM base WHERE 'countable_count'                          = ANY(v_static_codes)
        UNION ALL SELECT 'countable_change',                                 jsonb_build_array(ts_epoch_ms, countable_change),                                 ts_epoch_ms FROM base WHERE 'countable_change'                         = ANY(v_static_codes)
        UNION ALL SELECT 'countable_added_count',                            jsonb_build_array(ts_epoch_ms, countable_added_count),                            ts_epoch_ms FROM base WHERE 'countable_added_count'                    = ANY(v_static_codes)
        UNION ALL SELECT 'countable_removed_count',                          jsonb_build_array(ts_epoch_ms, countable_removed_count),                          ts_epoch_ms FROM base WHERE 'countable_removed_count'                  = ANY(v_static_codes)
        UNION ALL SELECT 'exists_count',                                     jsonb_build_array(ts_epoch_ms, exists_count),                                     ts_epoch_ms FROM base WHERE 'exists_count'                             = ANY(v_static_codes)
        UNION ALL SELECT 'exists_change',                                    jsonb_build_array(ts_epoch_ms, exists_change),                                    ts_epoch_ms FROM base WHERE 'exists_change'                            = ANY(v_static_codes)
        UNION ALL SELECT 'exists_added_count',                               jsonb_build_array(ts_epoch_ms, exists_added_count),                               ts_epoch_ms FROM base WHERE 'exists_added_count'                       = ANY(v_static_codes)
        UNION ALL SELECT 'exists_removed_count',                             jsonb_build_array(ts_epoch_ms, exists_removed_count),                             ts_epoch_ms FROM base WHERE 'exists_removed_count'                     = ANY(v_static_codes)
        UNION ALL SELECT 'births',                                           jsonb_build_array(ts_epoch_ms, births),                                           ts_epoch_ms FROM base WHERE 'births'                                   = ANY(v_static_codes)
        UNION ALL SELECT 'deaths',                                           jsonb_build_array(ts_epoch_ms, deaths),                                           ts_epoch_ms FROM base WHERE 'deaths'                                   = ANY(v_static_codes)
        UNION ALL SELECT 'name_change_count',                                jsonb_build_array(ts_epoch_ms, name_change_count),                                ts_epoch_ms FROM base WHERE 'name_change_count'                        = ANY(v_static_codes)
        UNION ALL SELECT 'primary_activity_category_change_count',           jsonb_build_array(ts_epoch_ms, primary_activity_category_change_count),           ts_epoch_ms FROM base WHERE 'primary_activity_category_change_count'   = ANY(v_static_codes)
        UNION ALL SELECT 'secondary_activity_category_change_count',         jsonb_build_array(ts_epoch_ms, secondary_activity_category_change_count),         ts_epoch_ms FROM base WHERE 'secondary_activity_category_change_count' = ANY(v_static_codes)
        UNION ALL SELECT 'sector_change_count',                              jsonb_build_array(ts_epoch_ms, sector_change_count),                              ts_epoch_ms FROM base WHERE 'sector_change_count'                      = ANY(v_static_codes)
        UNION ALL SELECT 'legal_form_change_count',                          jsonb_build_array(ts_epoch_ms, legal_form_change_count),                          ts_epoch_ms FROM base WHERE 'legal_form_change_count'                  = ANY(v_static_codes)
        UNION ALL SELECT 'physical_region_change_count',                     jsonb_build_array(ts_epoch_ms, physical_region_change_count),                     ts_epoch_ms FROM base WHERE 'physical_region_change_count'             = ANY(v_static_codes)
        UNION ALL SELECT 'physical_country_change_count',                    jsonb_build_array(ts_epoch_ms, physical_country_change_count),                    ts_epoch_ms FROM base WHERE 'physical_country_change_count'            = ANY(v_static_codes)
        UNION ALL SELECT 'physical_address_change_count',                    jsonb_build_array(ts_epoch_ms, physical_address_change_count),                    ts_epoch_ms FROM base WHERE 'physical_address_change_count'            = ANY(v_static_codes)
    ),
    stats_pairs AS (
        -- Extract requested stat-path leaves from real rows. The `nullif(..., 'null')`
        -- guard converts jsonb 'null' (statistics undefined on the sample — stddev /
        -- variance / coefficient_of_variation_pct when count<2 or variance=0) into
        -- SQL NULL so the cast to numeric succeeds. SQL-NULL paths (missing key in
        -- the row's jsonb) already give NULL through `(NULL::jsonb)::text`; nullif
        -- is a no-op on those. The acceptance CASE above only routes 'number' and
        -- 'null' leaves into stats_path_buffer, so the literal 4-char text 'null'
        -- here can only come from jsonb 'null' — not from a JSON string "null"
        -- whose ::text would render as '"null"' (with quotes).
        SELECT
            spb.code,
            jsonb_build_array(b.ts_epoch_ms, nullif((b.stats_summary #> spb.jsonb_path)::text, 'null')::numeric) AS pair,
            b.ts_epoch_ms
        FROM base AS b CROSS JOIN stats_path_buffer AS spb
    ),
    series_data_map AS (
        SELECT code, jsonb_agg(pair ORDER BY ts_epoch_ms) AS data
        FROM (
                      SELECT code, pair, ts_epoch_ms FROM static_pairs
            UNION ALL SELECT code, pair, ts_epoch_ms FROM stats_pairs
        ) AS u
        GROUP BY code
    ),
    -- Friendly stat-leaf labels per plan §2c: stat_definition.name (or initcap fallback)
    -- for the stat code, then a single space, then the last segment with _-to-space and
    -- only the first letter uppercased. The 'counts' indirection is implicitly skipped
    -- because we only render seg1 + segN.
    stats_names AS (
        SELECT
            spb.ord,
            spb.code,
            COALESCE(sdf.name, initcap(replace(spb.jsonb_path[1], '_', ' ')))
            || ' '
            || (
                SELECT upper(substr(s, 1, 1)) || substr(s, 2)
                FROM (SELECT replace(spb.jsonb_path[cardinality(spb.jsonb_path)], '_', ' ') AS s) AS x
            ) AS name
        FROM stats_path_buffer AS spb
        LEFT JOIN public.stat_definition AS sdf ON sdf.enabled AND sdf.code = spb.jsonb_path[1]
    )
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'resolution',       p_resolution,
        'unit_type',        p_unit_type,
        'year',             p_year,
        -- available_series is a discoverability hint: only include it when the caller
        -- gave no codes (i.e. they're in "what can I ask for?" mode). Once they specify
        -- a series_codes array they've decided what they want and the field is noise.
        'available_series', CASE
            WHEN p_series_codes IS NULL OR cardinality(p_series_codes) = 0 THEN
                (
                    SELECT jsonb_agg(jsonb_build_object('code', code, 'name', name, 'priority', priority) ORDER BY priority)
                    FROM series_definition
                    WHERE code <> ALL(v_filtered_codes)
                )
            ELSE NULL  -- jsonb_strip_nulls drops the key
        END,
        'filtered_series',  to_jsonb(v_filtered_codes),
        'series', (
            SELECT jsonb_agg(entry ORDER BY ord)
            FROM (
                -- Static codes preserve their priority ordering.
                SELECT sd.priority AS ord,
                       jsonb_build_object('code', sd.code, 'name', sd.name,
                                          'data', COALESCE(sdm.data, '[]'::jsonb)) AS entry
                FROM series_definition AS sd
                LEFT JOIN series_data_map AS sdm ON sdm.code = sd.code
                WHERE sd.code = ANY(v_static_codes)
                UNION ALL
                -- Stats codes appended after the static block, in caller-supplied order.
                SELECT 1000 + sn.ord AS ord,
                       jsonb_build_object('code', sn.code, 'name', sn.name,
                                          'data', COALESCE(sdm.data, '[]'::jsonb)) AS entry
                FROM stats_names AS sn
                LEFT JOIN series_data_map AS sdm ON sdm.code = sn.code
            ) AS ordered
        )
    )) INTO result;

    RETURN result;
END;
$function$;

-- worker.statistical_unit_flush_staging as before (it marked no history generation).
CREATE OR REPLACE PROCEDURE worker.statistical_unit_flush_staging(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_staging_count bigint;
BEGIN
    -- Clean up obsolete years
    DELETE FROM public.timesegments_years AS ty
    WHERE NOT EXISTS (
        SELECT 1 FROM public.timesegments AS t
        WHERE t.valid_from >= make_date(ty.year, 1, 1)
          AND t.valid_from < make_date(ty.year + 1, 1, 1)
        LIMIT 1
    );

    -- Auto-tune partition count target based on current data size
    CALL admin.adjust_partition_count_target();

    SELECT count(*) INTO v_staging_count FROM public.statistical_unit_staging;
    CALL public.statistical_unit_flush_staging();
    PERFORM pg_notify('worker_status',
        json_build_object('type', 'is_deriving_statistical_units', 'status', false)::text);
    p_info := jsonb_build_object('rows_flushed', v_staging_count);
END;
$procedure$;

-- Rebuild the dense tables after the downgrade commits; no-op on an empty database.
SELECT worker.enqueue_derive_statistical_unit_all();

END;
