-- Migration 20261104130602: history reports from sparse delta tables (STATBUS-558)
--
-- statistical_history and statistical_history_facet held one row per cell per period, rebuilt per
-- period and hash slot (3.5 GB plus a 21 GB per-slot cache on Norway). They become views with the same
-- columns over two sparse delta tables that hold only changes:
--   public.statistical_history_facet_stock_delta  per (cell, month): entries and exits of units, and their stats
--   public.statistical_history_facet_flow_delta   per (cell, period): the change counts between period ends
-- A period's stock is the sum of the deltas up to its end.
--
-- The deltas are maintained in the derive pipeline before statistical_unit_flush_staging: at that point
-- statistical_unit_staging holds the refreshed units' new versions and statistical_unit their old ones,
-- so one child per hash range (concurrent) stages new minus old, and the reduce adds the staged rows in.
-- A full derive rebuilds the tables with the same children. unit_ids on every delta row lists the units
-- that contribute to it, so tests can state exactly which units make up a cell.
BEGIN;

-- ===================================================================== remove the dense model
DELETE FROM worker.pipeline_step_weight
 WHERE step IN ('derive_statistical_history', 'statistical_history_reduce',
                'derive_statistical_history_facet', 'statistical_history_facet_reduce');
DELETE FROM worker.tasks
 WHERE command IN ('derive_statistical_history', 'derive_statistical_history_period', 'statistical_history_reduce',
                   'derive_statistical_history_facet', 'derive_statistical_history_facet_period',
                   'statistical_history_facet_reduce');
DELETE FROM worker.command_registry
 WHERE command IN ('derive_statistical_history', 'derive_statistical_history_period', 'statistical_history_reduce',
                   'derive_statistical_history_facet', 'derive_statistical_history_facet_period',
                   'statistical_history_facet_reduce');

DROP PROCEDURE worker.derive_statistical_history(jsonb, jsonb);
DROP PROCEDURE worker.derive_statistical_history_period(jsonb, jsonb);
DROP PROCEDURE worker.statistical_history_reduce(jsonb, jsonb);
DROP PROCEDURE worker.derive_statistical_history_facet(jsonb, jsonb);
DROP PROCEDURE worker.derive_statistical_history_facet_period(jsonb, jsonb);
DROP PROCEDURE worker.statistical_history_facet_reduce(jsonb, jsonb);
DROP FUNCTION worker.enqueue_derive_statistical_history_facet_period(public.history_resolution, integer, integer);
DROP FUNCTION public.statistical_history_derive(date, date);
DROP FUNCTION public.statistical_history_facet_derive(date, date);
DROP FUNCTION public.statistical_history_def(public.history_resolution, integer, integer, int4range);
DROP FUNCTION public.statistical_history_facet_def(public.history_resolution, integer, integer, int4range);
DROP TABLE public.statistical_history;
DROP TABLE public.statistical_history_facet;
DROP TABLE public.statistical_history_facet_partitions;
DROP TYPE public.statistical_history_type;
DROP TYPE public.statistical_history_facet_type;

-- ===================================================================== delta tables and their maintenance
-- ===================================================================== tables
-- Stock deltas per (cell, month). Summed up to a period end they give the stock at that end.
CREATE TABLE public.statistical_history_facet_stock_delta (
    unit_type public.statistical_unit_type NOT NULL,
    primary_activity_category_path public.ltree,
    secondary_activity_category_path public.ltree,
    sector_path public.ltree,
    legal_form_id integer,
    physical_region_path public.ltree,
    physical_country_id integer,
    unit_size_id integer,
    status_id integer,
    on_month date NOT NULL,
    exists_delta integer NOT NULL,
    countable_delta integer NOT NULL,
    stats_delta jsonb,
    unit_ids integer[] NOT NULL
);
CREATE UNIQUE INDEX statistical_history_facet_stock_delta_key ON public.statistical_history_facet_stock_delta (unit_type, primary_activity_category_path,
    secondary_activity_category_path, sector_path, legal_form_id, physical_region_path, physical_country_id,
    unit_size_id, status_id, on_month) NULLS NOT DISTINCT;
CREATE INDEX ON public.statistical_history_facet_stock_delta (unit_type, on_month);

-- Flow deltas per (cell, period).
CREATE TABLE public.statistical_history_facet_flow_delta (
    resolution public.history_resolution NOT NULL,
    year integer NOT NULL,
    month integer,
    unit_type public.statistical_unit_type NOT NULL,
    primary_activity_category_path public.ltree,
    secondary_activity_category_path public.ltree,
    sector_path public.ltree,
    legal_form_id integer,
    physical_region_path public.ltree,
    physical_country_id integer,
    unit_size_id integer,
    status_id integer,
    flows integer[] NOT NULL,
    stats_ended jsonb,
    unit_ids integer[] NOT NULL
);
COMMENT ON COLUMN public.statistical_history_facet_flow_delta.flows IS 'In order: exists_change, exists_added_count, exists_removed_count, countable_change, countable_added_count, countable_removed_count, births, deaths, name, primary_activity_category, secondary_activity_category, sector, legal_form, physical_region, physical_country, physical_address, unit_size, status change counts.';
CREATE UNIQUE INDEX statistical_history_facet_flow_delta_key ON public.statistical_history_facet_flow_delta (resolution, year, month, unit_type,
    primary_activity_category_path, secondary_activity_category_path, sector_path, legal_form_id,
    physical_region_path, physical_country_id, unit_size_id, status_id) NULLS NOT DISTINCT;

-- Staging: signed per-unit rows written by the concurrent per-range children, summed by the reduce.
-- Logged, like statistical_unit_staging: crash recovery empties an unlogged table, and rows staged for a
-- flush that has committed must still be added after a restart.
CREATE TABLE public.statistical_history_facet_stock_delta_staging (
    unit_id integer NOT NULL, sign smallint NOT NULL,
    unit_type public.statistical_unit_type NOT NULL,
    primary_activity_category_path public.ltree, secondary_activity_category_path public.ltree,
    sector_path public.ltree, legal_form_id integer, physical_region_path public.ltree,
    physical_country_id integer, unit_size_id integer, status_id integer,
    on_month date NOT NULL, exists_delta integer NOT NULL, countable_delta integer NOT NULL, stats_delta jsonb,
    generation bigint NOT NULL);
CREATE TABLE public.statistical_history_facet_flow_delta_staging (
    unit_id integer NOT NULL, sign smallint NOT NULL,
    resolution public.history_resolution NOT NULL, year integer NOT NULL, month integer,
    unit_type public.statistical_unit_type NOT NULL,
    primary_activity_category_path public.ltree, secondary_activity_category_path public.ltree,
    sector_path public.ltree, legal_form_id integer, physical_region_path public.ltree,
    physical_country_id integer, unit_size_id integer, status_id integer,
    flows integer[] NOT NULL, stats_ended jsonb,
    generation bigint NOT NULL);

-- Which staged rows count. Rows are staged from statistical_unit_staging (new versions) and
-- statistical_unit (old versions) before the flush; they are true only once that flush has committed.
CREATE TABLE worker.statistical_history_facet_delta_state (
    flushed_generation bigint NOT NULL DEFAULT 0,
    rebuild_generation bigint,
    rebuild_needed boolean NOT NULL DEFAULT false
);
CREATE UNIQUE INDEX statistical_history_facet_delta_state_single_row ON worker.statistical_history_facet_delta_state ((true));
INSERT INTO worker.statistical_history_facet_delta_state DEFAULT VALUES;
COMMENT ON TABLE worker.statistical_history_facet_delta_state IS 'One row: which staged history delta rows count. A cycle''s rows carry its generation (the derive_statistical_history_facet_delta task id); they count once the flush of that cycle has committed.';
COMMENT ON COLUMN worker.statistical_history_facet_delta_state.flushed_generation IS 'Generation of the last cycle whose history staging completed and whose statistical_unit_flush_staging committed (set by that flush, in its transaction). Staged rows with generation <= flushed_generation are true and are added by the reduce; rows above it belong to a cycle whose flush never committed, and the next cycle replaces them (its units are still in statistical_unit_staging).';
COMMENT ON COLUMN worker.statistical_history_facet_delta_state.rebuild_generation IS 'Generation of a rebuild cycle not yet added. Its reduce replaces the delta tables in one transaction, so readers keep the previous rows until the rebuilt ones commit. While set, every cycle rebuilds.';
COMMENT ON COLUMN worker.statistical_history_facet_delta_state.rebuild_needed IS 'Set when statistical_unit_flush_staging ran in a task tree without a history step (a tree spawned before this design, or a direct call), so units moved without their deltas; the next cycle rebuilds.';
COMMENT ON COLUMN public.statistical_history_facet_stock_delta_staging.generation IS 'The cycle that staged the row (see worker.statistical_history_facet_delta_state). 0 for rows that are true when they commit: the subtraction of units deleted from statistical_unit in the same transaction.';
COMMENT ON COLUMN public.statistical_history_facet_flow_delta_staging.generation IS 'As statistical_history_facet_stock_delta_staging.generation.';

-- Membership after a reduce: a unit stays or enters when its count (1 if present, +1 per add, -1 per
-- removal) is positive.
CREATE FUNCTION worker.unit_ids_apply(p_ids integer[], p_plus integer[], p_minus integer[]) RETURNS integer[]
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $unit_ids_apply$
    SELECT COALESCE(array_agg(id ORDER BY id), '{}') FROM (
        SELECT id FROM (SELECT unnest(p_ids) AS id, 1 AS n
                        UNION ALL SELECT unnest(p_plus), 1
                        UNION ALL SELECT unnest(p_minus), -1) AS x
         GROUP BY id HAVING sum(n) > 0) AS y
$unit_ids_apply$;

-- Element-wise sum of two integer arrays; a missing element counts as 0. Used to add a cycle's flows to a stored
-- row. Many rows are summed with one sum() per element instead: 2x faster on Norway's 6.2 M staged flow rows.
CREATE FUNCTION public.int_array_add(a integer[], b integer[]) RETURNS integer[]
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE AS $int_array_add$
    SELECT array_agg(COALESCE(x, 0) + COALESCE(y, 0) ORDER BY i) FROM unnest(a, b) WITH ORDINALITY AS z(x, y, i)
$int_array_add$;

-- ===================================================================== contribution
-- Contribution of the unit versions in table p_source (statistical_unit rows) restricted to the units in
-- pg_temp.hd_units (unit_type, unit_id). Writes unsigned per-unit rows to pg_temp.hd_stock / pg_temp.hd_flow
-- tagged with p_sign. Each kind depends only on one unit's own versions, so per-unit rows are exact.
CREATE PROCEDURE worker.statistical_history_facet_delta_contribution(p_source regclass, p_sign smallint)
LANGUAGE plpgsql AS $statistical_history_facet_delta_contribution$
BEGIN
    IF to_regclass('pg_temp.hd_v') IS NOT NULL THEN DROP TABLE pg_temp.hd_v; END IF;
    EXECUTE format($SQL$
    CREATE TEMP TABLE hd_v AS
    SELECT s.unit_type, s.unit_id, s.valid_from, s.valid_to, s.valid_until, s.birth_date, s.death_date,
           s.used_for_counting, s.name, s.stats_summary,
           s.primary_activity_category_path, s.secondary_activity_category_path, s.sector_path, s.legal_form_id,
           s.physical_region_path, s.physical_country_id, s.unit_size_id, s.status_id,
           (s.physical_address_part1, s.physical_address_part2, s.physical_address_part3,
            s.physical_postcode, s.physical_postplace)::text AS addr,
           public.unit_existence_from(s.valid_from, s.birth_date) AS ef,
           public.unit_existence_until(s.valid_until, s.death_date) AS eu
      FROM %1$s AS s
      JOIN pg_temp.hd_units AS u ON u.unit_type = s.unit_type AND u.unit_id = s.unit_id
    $SQL$, p_source);
    CREATE INDEX ON hd_v (unit_type, unit_id, valid_from);
    ANALYZE hd_v;

    -- Stock: +1/-1 at each version's existence window (today: latest version overlapping the period,
    -- existing at its end; versions of one unit do not overlap, so the sums agree), countable likewise.
    -- Dates are bucketed to their month (on_month, see its column comment): exact at every month end, and
    -- a unit's changes within one month collapse into one row, or cancel. A version without a known start
    -- (-infinity) enters at on_month -infinity, before every period; an open end (infinity) never leaves.
    INSERT INTO pg_temp.hd_stock
    SELECT v.unit_id, p_sign, v.unit_type, v.primary_activity_category_path, v.secondary_activity_category_path,
           v.sector_path, v.legal_form_id, v.physical_region_path, v.physical_country_id, v.unit_size_id, v.status_id,
           date_trunc('month', x.d)::date, sum(x.ne)::int, sum(x.nc)::int, NULL::jsonb
      FROM hd_v AS v
     CROSS JOIN LATERAL (VALUES (v.ef, 1, v.used_for_counting::int), (v.eu, -1, -v.used_for_counting::int)) AS x(d, ne, nc)
     WHERE v.ef < v.eu AND x.d <> 'infinity'::date
     GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
    HAVING sum(x.ne) <> 0 OR sum(x.nc) <> 0;
    -- Stats valid: a counted version's summary holds from valid_from until valid_until. Within one month a
    -- unit's leaving and re-entering summaries are added; a row where every key's in and out flows are
    -- equal changes no stock and is not kept.
    INSERT INTO pg_temp.hd_stock
    SELECT v.unit_id, p_sign, v.unit_type, v.primary_activity_category_path, v.secondary_activity_category_path,
           v.sector_path, v.legal_form_id, v.physical_region_path, v.physical_country_id, v.unit_size_id, v.status_id,
           date_trunc('month', x.d)::date, 0, 0, public.jsonb_stats_delta_agg(x.sd)
      FROM hd_v AS v
     CROSS JOIN LATERAL (VALUES (v.valid_from, public.jsonb_stats_to_delta(v.stats_summary)),
                                (v.valid_until, public.jsonb_stats_negate(public.jsonb_stats_to_delta(v.stats_summary)))) AS x(d, sd)
     WHERE v.used_for_counting AND x.d <> 'infinity'::date
     GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
    HAVING EXISTS (SELECT 1 FROM jsonb_each(public.jsonb_stats_delta_agg(x.sd) - 'type'::text) AS e
                    WHERE e.value->'in' IS DISTINCT FROM e.value->'out');

    -- Calendar periods holding any of the unit's edges, independent of the data's date range.
    IF to_regclass('pg_temp.hd_ep') IS NOT NULL THEN DROP TABLE pg_temp.hd_ep; END IF;
    CREATE TEMP TABLE hd_ep AS
    SELECT DISTINCT v.unit_type, v.unit_id, p.resolution, p.year, p.month, p.curr_start, p.curr_stop, p.prev_stop
      FROM hd_v AS v
     CROSS JOIN LATERAL (VALUES (v.valid_from), (v.valid_until), (v.birth_date), (v.death_date), (v.ef), (v.eu)) AS e(d)
     CROSS JOIN LATERAL (VALUES
            ('year'::public.history_resolution, extract(year FROM e.d)::int, NULL::int,
             make_date(extract(year FROM e.d)::int, 1, 1), make_date(extract(year FROM e.d)::int, 12, 31),
             make_date(extract(year FROM e.d)::int - 1, 12, 31)),
            ('year-month'::public.history_resolution, extract(year FROM e.d)::int, extract(month FROM e.d)::int,
             date_trunc('month', e.d)::date, (date_trunc('month', e.d) + interval '1 month' - interval '1 day')::date,
             (date_trunc('month', e.d) - interval '1 day')::date)) AS p(resolution, year, month, curr_start, curr_stop, prev_stop)
     WHERE e.d IS NOT NULL AND isfinite(e.d);
    CREATE INDEX ON hd_ep (unit_type, unit_id);
    ANALYZE hd_ep;

    -- Flows: the unit at prev_stop (p) and curr_stop (c), as the former statistical_history_facet_def compared
    -- them. A period in which the unit changed nothing (all 18 counts zero) stores no row.
    INSERT INTO pg_temp.hd_flow
    SELECT * FROM (
    SELECT ep.unit_id, p_sign, ep.resolution, ep.year, ep.month, ep.unit_type,
           COALESCE(c.primary_activity_category_path, p.primary_activity_category_path),
           COALESCE(c.secondary_activity_category_path, p.secondary_activity_category_path),
           COALESCE(c.sector_path, p.sector_path), COALESCE(c.legal_form_id, p.legal_form_id),
           COALESCE(c.physical_region_path, p.physical_region_path), COALESCE(c.physical_country_id, p.physical_country_id),
           COALESCE(c.unit_size_id, p.unit_size_id), COALESCE(c.status_id, p.status_id),
           ARRAY[(c.unit_id IS NOT NULL)::int - (p.unit_id IS NOT NULL)::int,
                 (c.unit_id IS NOT NULL AND p.unit_id IS NULL)::int,
                 (p.unit_id IS NOT NULL AND c.unit_id IS NULL)::int,
                 COALESCE(c.used_for_counting, false)::int - COALESCE(p.used_for_counting, false)::int,
                 (COALESCE(c.used_for_counting, false) AND NOT COALESCE(p.used_for_counting, false))::int,
                 (COALESCE(p.used_for_counting, false) AND NOT COALESCE(c.used_for_counting, false))::int,
                 (COALESCE(l.used_for_counting, false) AND COALESCE(l.birth_date BETWEEN ep.curr_start AND ep.curr_stop, false))::int,
                 (COALESCE(l.used_for_counting, false) AND COALESCE(l.death_date BETWEEN ep.curr_start AND ep.curr_stop, false))::int,
                 (b.both AND c.name IS DISTINCT FROM p.name)::int,
                 (b.both AND c.primary_activity_category_path IS DISTINCT FROM p.primary_activity_category_path)::int,
                 (b.both AND c.secondary_activity_category_path IS DISTINCT FROM p.secondary_activity_category_path)::int,
                 (b.both AND c.sector_path IS DISTINCT FROM p.sector_path)::int,
                 (b.both AND c.legal_form_id IS DISTINCT FROM p.legal_form_id)::int,
                 (b.both AND c.physical_region_path IS DISTINCT FROM p.physical_region_path)::int,
                 (b.both AND c.physical_country_id IS DISTINCT FROM p.physical_country_id)::int,
                 (b.both AND c.addr IS DISTINCT FROM p.addr)::int,
                 (b.both AND c.unit_size_id IS DISTINCT FROM p.unit_size_id)::int,
                 (b.both AND c.status_id IS DISTINCT FROM p.status_id)::int],
           NULL::jsonb
      FROM hd_ep AS ep
      LEFT JOIN hd_v AS c ON c.unit_type = ep.unit_type AND c.unit_id = ep.unit_id
           AND c.valid_from <= ep.curr_stop AND ep.curr_stop < c.valid_until
           AND c.ef <= ep.curr_stop AND ep.curr_stop < c.eu
      LEFT JOIN hd_v AS p ON p.unit_type = ep.unit_type AND p.unit_id = ep.unit_id
           AND p.valid_from <= ep.prev_stop AND ep.prev_stop < p.valid_until
           AND p.ef <= ep.prev_stop AND ep.prev_stop < p.eu
      LEFT JOIN LATERAL (SELECT l.used_for_counting, l.birth_date, l.death_date FROM hd_v AS l
                          WHERE l.unit_type = ep.unit_type AND l.unit_id = ep.unit_id
                            AND l.valid_from <= ep.curr_stop AND l.valid_to >= ep.curr_start
                          ORDER BY l.valid_from DESC, l.valid_until DESC LIMIT 1) AS l ON true
     CROSS JOIN LATERAL (SELECT COALESCE(p.used_for_counting AND c.used_for_counting, false) AS both) AS b
     WHERE c.unit_id IS NOT NULL OR p.unit_id IS NOT NULL) AS r(unit_id, sign, resolution, year, month, unit_type,
         primary_activity_category_path, secondary_activity_category_path, sector_path, legal_form_id,
         physical_region_path, physical_country_id, unit_size_id, status_id, flows, stats_ended)
     WHERE r.flows <> array_fill(0, ARRAY[18]);

    -- Stats ended: the latest counted version overlapping a period counts for the period's stats; when it
    -- ended inside the period it is not in the stock at the period end, so it is added here.
    INSERT INTO pg_temp.hd_flow
    SELECT v.unit_id, p_sign, ep.resolution, ep.year, ep.month, v.unit_type, v.primary_activity_category_path,
           v.secondary_activity_category_path, v.sector_path, v.legal_form_id, v.physical_region_path,
           v.physical_country_id, v.unit_size_id, v.status_id,
           array_fill(0, ARRAY[18]), public.jsonb_stats_to_delta(v.stats_summary)
      FROM hd_ep AS ep
      JOIN hd_v AS v ON v.unit_type = ep.unit_type AND v.unit_id = ep.unit_id
       AND v.used_for_counting AND v.valid_from <= ep.curr_stop
       AND ep.curr_start < v.valid_until AND v.valid_until <= ep.curr_stop
     WHERE NOT EXISTS (SELECT 1 FROM hd_v AS w WHERE w.unit_type = v.unit_type AND w.unit_id = v.unit_id
                          AND w.valid_from > v.valid_from AND w.valid_from <= ep.curr_stop);
END;
$statistical_history_facet_delta_contribution$;

CREATE PROCEDURE worker.statistical_history_facet_delta_contribution_begin()
LANGUAGE plpgsql AS $statistical_history_facet_delta_contribution_begin$
BEGIN
    IF to_regclass('pg_temp.hd_stock') IS NOT NULL THEN DROP TABLE pg_temp.hd_stock; END IF;
    CREATE TEMP TABLE hd_stock (LIKE public.statistical_history_facet_stock_delta_staging);
    ALTER TABLE hd_stock DROP COLUMN generation;
    IF to_regclass('pg_temp.hd_flow') IS NOT NULL THEN DROP TABLE pg_temp.hd_flow; END IF;
    CREATE TEMP TABLE hd_flow (LIKE public.statistical_history_facet_flow_delta_staging);
    ALTER TABLE hd_flow DROP COLUMN generation;
END;
$statistical_history_facet_delta_contribution_begin$;

-- Move hd_stock / hd_flow to the staging tables with their sign applied, tagged with p_generation. A unit's
-- old row that reappears identical among its new rows cancels first, so units refreshed without change
-- stage nothing.
CREATE PROCEDURE worker.statistical_history_facet_delta_contribution_stage(p_generation bigint)
LANGUAGE plpgsql AS $statistical_history_facet_delta_contribution_stage$
BEGIN
    INSERT INTO public.statistical_history_facet_stock_delta_staging
    WITH plus AS (SELECT unit_id, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path,
                         legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id, on_month,
                         exists_delta, countable_delta, stats_delta FROM pg_temp.hd_stock WHERE sign > 0),
         minus AS (SELECT unit_id, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path,
                          legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id, on_month,
                          exists_delta, countable_delta, stats_delta FROM pg_temp.hd_stock WHERE sign < 0)
    SELECT unit_id, 1, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path,
           legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id, on_month,
           exists_delta, countable_delta, stats_delta, p_generation
      FROM (SELECT * FROM plus EXCEPT ALL SELECT * FROM minus) AS a
    UNION ALL
    SELECT unit_id, -1, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path,
           legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id, on_month,
           -exists_delta, -countable_delta, public.jsonb_stats_negate(stats_delta), p_generation
      FROM (SELECT * FROM minus EXCEPT ALL SELECT * FROM plus) AS r;

    INSERT INTO public.statistical_history_facet_flow_delta_staging
    WITH plus AS (SELECT unit_id, resolution, year, month, unit_type, primary_activity_category_path,
                         secondary_activity_category_path, sector_path, legal_form_id, physical_region_path,
                         physical_country_id, unit_size_id, status_id, flows, stats_ended FROM pg_temp.hd_flow WHERE sign > 0),
         minus AS (SELECT unit_id, resolution, year, month, unit_type, primary_activity_category_path,
                          secondary_activity_category_path, sector_path, legal_form_id, physical_region_path,
                          physical_country_id, unit_size_id, status_id, flows, stats_ended FROM pg_temp.hd_flow WHERE sign < 0)
    SELECT unit_id, 1, resolution, year, month, unit_type, primary_activity_category_path,
           secondary_activity_category_path, sector_path, legal_form_id, physical_region_path,
           physical_country_id, unit_size_id, status_id, flows, stats_ended, p_generation
      FROM (SELECT * FROM plus EXCEPT ALL SELECT * FROM minus) AS a
    UNION ALL
    SELECT unit_id, -1, resolution, year, month, unit_type, primary_activity_category_path,
           secondary_activity_category_path, sector_path, legal_form_id, physical_region_path,
           physical_country_id, unit_size_id, status_id,
           (SELECT array_agg(-f ORDER BY i) FROM unnest(flows) WITH ORDINALITY AS z(f, i)),
           public.jsonb_stats_negate(stats_ended), p_generation
      FROM (SELECT * FROM minus EXCEPT ALL SELECT * FROM plus) AS r;
    TRUNCATE pg_temp.hd_stock, pg_temp.hd_flow;
END;
$statistical_history_facet_delta_contribution_stage$;

-- ===================================================================== per-range step
-- One hash range. The units in p_new (statistical_unit_staging) are the units this cycle refreshed:
-- incrementally, their versions in p_old (statistical_unit) are subtracted and their new versions added.
-- For a rebuild the delta tables are replaced by the reduce, and every unit is added as it will stand after
-- the flush: refreshed units from p_new, the others from p_old. Rows are tagged with p_generation: the
-- worker passes its cycle's, so the rows count once that cycle's flush commits; 0 makes them count at the
-- next apply, for a caller whose p_old and p_new are already final.
CREATE PROCEDURE worker.statistical_history_facet_delta_stage_partition(p_hash_range int4range, p_rebuild boolean,
                                          p_old regclass DEFAULT 'public.statistical_unit',
                                          p_new regclass DEFAULT 'public.statistical_unit_staging',
                                          p_generation bigint DEFAULT 0)
LANGUAGE plpgsql AS $statistical_history_facet_delta_stage_partition$
BEGIN
    CALL worker.statistical_history_facet_delta_contribution_begin();
    IF to_regclass('pg_temp.hd_units') IS NOT NULL THEN DROP TABLE pg_temp.hd_units; END IF;
    IF to_regclass('pg_temp.hd_refreshed') IS NOT NULL THEN DROP TABLE pg_temp.hd_refreshed; END IF;
    EXECUTE format($SQL$CREATE TEMP TABLE hd_refreshed AS SELECT DISTINCT unit_type, unit_id FROM %1$s
                        WHERE %2$L <= hash_slot AND hash_slot < %3$L$SQL$, p_new, lower(p_hash_range), upper(p_hash_range));
    IF p_rebuild THEN
        EXECUTE format($SQL$CREATE TEMP TABLE hd_units AS
                            SELECT DISTINCT o.unit_type, o.unit_id FROM %1$s AS o
                             WHERE %2$L <= o.hash_slot AND o.hash_slot < %3$L
                               AND NOT EXISTS (SELECT 1 FROM pg_temp.hd_refreshed AS r
                                                WHERE r.unit_type = o.unit_type AND r.unit_id = o.unit_id)$SQL$,
                       p_old, lower(p_hash_range), upper(p_hash_range));
        CALL worker.statistical_history_facet_delta_contribution(p_old, 1::smallint);
        DROP TABLE pg_temp.hd_units;
        CREATE TEMP TABLE hd_units AS SELECT * FROM pg_temp.hd_refreshed;
        CALL worker.statistical_history_facet_delta_contribution(p_new, 1::smallint);
    ELSE
        CREATE TEMP TABLE hd_units AS SELECT * FROM pg_temp.hd_refreshed;
        CALL worker.statistical_history_facet_delta_contribution(p_old, (-1)::smallint);
        CALL worker.statistical_history_facet_delta_contribution(p_new, 1::smallint);
    END IF;
    CALL worker.statistical_history_facet_delta_contribution_stage(p_generation);
END;
$statistical_history_facet_delta_stage_partition$;

-- Units removed from statistical_unit outside the flush (worker.derive_statistical_unit deletes the rows of
-- units whose base row is gone): stage the subtraction of their versions before the rows are deleted. The
-- rows commit with that DELETE, so they are true at once (generation 0).
CREATE PROCEDURE worker.statistical_history_facet_delta_remove_units(p_unit_type public.statistical_unit_type, p_unit_ids integer[],
                                                 p_old regclass DEFAULT 'public.statistical_unit')
LANGUAGE plpgsql AS $statistical_history_facet_delta_remove_units$
BEGIN
    CALL worker.statistical_history_facet_delta_contribution_begin();
    IF to_regclass('pg_temp.hd_units') IS NOT NULL THEN DROP TABLE pg_temp.hd_units; END IF;
    CREATE TEMP TABLE hd_units AS SELECT p_unit_type AS unit_type, id AS unit_id FROM unnest(p_unit_ids) AS id;
    CALL worker.statistical_history_facet_delta_contribution(p_old, (-1)::smallint);
    CALL worker.statistical_history_facet_delta_contribution_stage(0);
END;
$statistical_history_facet_delta_remove_units$;

-- ===================================================================== apply
-- Adds the staged rows that count (generation <= flushed_generation, see
-- worker.statistical_history_facet_delta_state) into the tables and removes them from staging; rows of a
-- cycle whose flush has not committed stay. With p_replace (a rebuild's rows), the tables are emptied first
-- in the same transaction, so readers see the previous rows until the rebuilt ones commit.
-- Membership in unit_ids is counted, so the result does not depend on how many cycles were staged before
-- one apply, nor on their order.
-- A row with no stats keeps stats NULL (delta_agg over no summaries would store an empty stats_delta,
-- which every read then parses); the stats columns stay NULL until a summary arrives.
CREATE PROCEDURE worker.statistical_history_facet_delta_apply(p_replace boolean DEFAULT false)
LANGUAGE plpgsql
-- The MERGEs join a cycle's staged sums (small) to the whole delta table (large) on an exact text key;
-- a merge join sorts the whole table by that key every cycle (9.8 s on Norway for 500 staged rows),
-- a hash join reads it once (1.2 s). The planner picks the merge join on its cost estimate, so it is off.
SET enable_mergejoin = off
AS $statistical_history_facet_delta_apply$
DECLARE
    v_up_to bigint := (SELECT flushed_generation FROM worker.statistical_history_facet_delta_state);
BEGIN
    LOCK TABLE public.statistical_history_facet_stock_delta_staging, public.statistical_history_facet_flow_delta_staging IN EXCLUSIVE MODE;
    IF p_replace THEN
        DELETE FROM public.statistical_history_facet_stock_delta;
        DELETE FROM public.statistical_history_facet_flow_delta;
    END IF;

    IF to_regclass('pg_temp.hd_sum') IS NOT NULL THEN DROP TABLE pg_temp.hd_sum; END IF;
    CREATE TEMP TABLE hd_sum AS
    SELECT unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path, legal_form_id,
           physical_region_path, physical_country_id, unit_size_id, status_id, on_month,
           sum(exists_delta)::int AS exists_delta, sum(countable_delta)::int AS countable_delta,
           public.jsonb_stats_delta_agg(stats_delta) FILTER (WHERE stats_delta IS NOT NULL) AS stats_delta,
           array_agg(unit_id ORDER BY unit_id) FILTER (WHERE sign > 0) AS plus_ids,
           array_agg(unit_id ORDER BY unit_id) FILTER (WHERE sign < 0) AS minus_ids
      FROM public.statistical_history_facet_stock_delta_staging
     WHERE generation <= v_up_to
     GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10;

    -- The dimensions are nullable, and IS NOT DISTINCT FROM cannot drive a hash join; their row as text
    -- (NULL renders empty, '' renders quoted) is an exact key that can, so the MERGE stays linear.
    MERGE INTO public.statistical_history_facet_stock_delta AS t
    USING hd_sum AS s
       ON t.unit_type = s.unit_type AND t.on_month = s.on_month
      AND ROW(t.primary_activity_category_path, t.secondary_activity_category_path, t.sector_path, t.legal_form_id, t.physical_region_path, t.physical_country_id, t.unit_size_id, t.status_id)::text = ROW(s.primary_activity_category_path, s.secondary_activity_category_path, s.sector_path, s.legal_form_id, s.physical_region_path, s.physical_country_id, s.unit_size_id, s.status_id)::text
      AND t.primary_activity_category_path IS NOT DISTINCT FROM s.primary_activity_category_path
      AND t.secondary_activity_category_path IS NOT DISTINCT FROM s.secondary_activity_category_path
      AND t.sector_path IS NOT DISTINCT FROM s.sector_path
      AND t.legal_form_id IS NOT DISTINCT FROM s.legal_form_id
      AND t.physical_region_path IS NOT DISTINCT FROM s.physical_region_path
      AND t.physical_country_id IS NOT DISTINCT FROM s.physical_country_id
      AND t.unit_size_id IS NOT DISTINCT FROM s.unit_size_id
      AND t.status_id IS NOT DISTINCT FROM s.status_id
    WHEN MATCHED THEN UPDATE SET
        exists_delta = t.exists_delta + s.exists_delta,
        countable_delta = t.countable_delta + s.countable_delta,
        stats_delta = CASE WHEN t.stats_delta IS NULL THEN s.stats_delta
                           WHEN s.stats_delta IS NULL THEN t.stats_delta
                           ELSE public.jsonb_stats_delta_merge(t.stats_delta, s.stats_delta) END,
        unit_ids = worker.unit_ids_apply(t.unit_ids, s.plus_ids, s.minus_ids)
    WHEN NOT MATCHED THEN INSERT VALUES (s.unit_type, s.primary_activity_category_path, s.secondary_activity_category_path,
        s.sector_path, s.legal_form_id, s.physical_region_path, s.physical_country_id, s.unit_size_id, s.status_id,
        s.on_month, s.exists_delta, s.countable_delta, s.stats_delta, worker.unit_ids_apply('{}', s.plus_ids, s.minus_ids));
    DELETE FROM public.statistical_history_facet_stock_delta WHERE cardinality(unit_ids) = 0;

    IF to_regclass('pg_temp.hd_fsum') IS NOT NULL THEN DROP TABLE pg_temp.hd_fsum; END IF;
    CREATE TEMP TABLE hd_fsum AS
    SELECT resolution, year, month, unit_type, primary_activity_category_path, secondary_activity_category_path,
           sector_path, legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id,
           ARRAY[sum(flows[1]), sum(flows[2]), sum(flows[3]), sum(flows[4]), sum(flows[5]), sum(flows[6]),
                 sum(flows[7]), sum(flows[8]), sum(flows[9]), sum(flows[10]), sum(flows[11]), sum(flows[12]),
                 sum(flows[13]), sum(flows[14]), sum(flows[15]), sum(flows[16]), sum(flows[17]),
                 sum(flows[18])]::integer[] AS flows,
           public.jsonb_stats_delta_agg(stats_ended) FILTER (WHERE stats_ended IS NOT NULL) AS stats_ended,
           array_agg(unit_id ORDER BY unit_id) FILTER (WHERE sign > 0) AS plus_ids,
           array_agg(unit_id ORDER BY unit_id) FILTER (WHERE sign < 0) AS minus_ids
      FROM public.statistical_history_facet_flow_delta_staging
     WHERE generation <= v_up_to
     GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12;

    MERGE INTO public.statistical_history_facet_flow_delta AS t
    USING hd_fsum AS s
       ON t.resolution = s.resolution AND t.year = s.year AND t.month IS NOT DISTINCT FROM s.month
      AND t.unit_type = s.unit_type
      AND ROW(t.month, t.primary_activity_category_path, t.secondary_activity_category_path, t.sector_path, t.legal_form_id, t.physical_region_path, t.physical_country_id, t.unit_size_id, t.status_id)::text
        = ROW(s.month, s.primary_activity_category_path, s.secondary_activity_category_path, s.sector_path, s.legal_form_id, s.physical_region_path, s.physical_country_id, s.unit_size_id, s.status_id)::text
      AND t.primary_activity_category_path IS NOT DISTINCT FROM s.primary_activity_category_path
      AND t.secondary_activity_category_path IS NOT DISTINCT FROM s.secondary_activity_category_path
      AND t.sector_path IS NOT DISTINCT FROM s.sector_path
      AND t.legal_form_id IS NOT DISTINCT FROM s.legal_form_id
      AND t.physical_region_path IS NOT DISTINCT FROM s.physical_region_path
      AND t.physical_country_id IS NOT DISTINCT FROM s.physical_country_id
      AND t.unit_size_id IS NOT DISTINCT FROM s.unit_size_id
      AND t.status_id IS NOT DISTINCT FROM s.status_id
    WHEN MATCHED THEN UPDATE SET
        flows = public.int_array_add(t.flows, s.flows),
        stats_ended = CASE WHEN t.stats_ended IS NULL THEN s.stats_ended
                           WHEN s.stats_ended IS NULL THEN t.stats_ended
                           ELSE public.jsonb_stats_delta_merge(t.stats_ended, s.stats_ended) END,
        unit_ids = worker.unit_ids_apply(t.unit_ids, s.plus_ids, s.minus_ids)
    WHEN NOT MATCHED THEN INSERT VALUES (s.resolution, s.year, s.month, s.unit_type, s.primary_activity_category_path,
        s.secondary_activity_category_path, s.sector_path, s.legal_form_id, s.physical_region_path,
        s.physical_country_id, s.unit_size_id, s.status_id, s.flows, s.stats_ended,
        worker.unit_ids_apply('{}', s.plus_ids, s.minus_ids));
    DELETE FROM public.statistical_history_facet_flow_delta WHERE cardinality(unit_ids) = 0;

    IF EXISTS (SELECT 1 FROM public.statistical_history_facet_stock_delta_staging WHERE generation > v_up_to)
       OR EXISTS (SELECT 1 FROM public.statistical_history_facet_flow_delta_staging WHERE generation > v_up_to) THEN
        DELETE FROM public.statistical_history_facet_stock_delta_staging WHERE generation <= v_up_to;
        DELETE FROM public.statistical_history_facet_flow_delta_staging WHERE generation <= v_up_to;
    ELSE
        TRUNCATE public.statistical_history_facet_stock_delta_staging, public.statistical_history_facet_flow_delta_staging;
    END IF;
END;
$statistical_history_facet_delta_apply$;


-- ===================================================================== worker commands
-- The partition count for a number of units. Thresholds tuned for the 16384-slot space: few partitions for
-- small datasets, more as the unit count grows. admin.adjust_partition_count_target stores it for the
-- current statistical_unit; worker.derive_statistical_history_facet_delta sizes its ranges with it before the flush.
CREATE FUNCTION public.partition_count_target_for(p_unit_count bigint) RETURNS integer
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $partition_count_target_for$
    SELECT CASE
        WHEN p_unit_count <=      100 THEN     4
        WHEN p_unit_count <=   10000 THEN    16
        WHEN p_unit_count <=  100000 THEN    64
        WHEN p_unit_count <= 1000000 THEN   128
        WHEN p_unit_count <= 5000000 THEN   256
        ELSE                                 512
    END
$partition_count_target_for$;

CREATE OR REPLACE PROCEDURE admin.adjust_partition_count_target()
 LANGUAGE plpgsql
 SET search_path TO 'admin', 'public', 'pg_temp'
AS $procedure$
DECLARE
    v_unit_count bigint;
    v_desired    integer;
BEGIN
    SELECT count(*) INTO v_unit_count FROM public.statistical_unit;
    v_desired := public.partition_count_target_for(v_unit_count);
    UPDATE public.settings
       SET partition_count_target = v_desired
     WHERE partition_count_target IS DISTINCT FROM v_desired;
END;
$procedure$;

-- Children of derive_statistical_history_facet_delta: one hash range each, run concurrently.
CREATE PROCEDURE worker.derive_statistical_history_facet_delta_partition(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_history_facet_delta_partition$
DECLARE
    v_hash_range int4range := (payload->>'hash_range')::int4range;
    v_rebuild boolean := COALESCE((payload->>'rebuild')::boolean, false);
    v_generation bigint := (payload->>'generation')::bigint;
BEGIN
    CALL worker.statistical_history_facet_delta_stage_partition(p_hash_range => v_hash_range, p_rebuild => v_rebuild,
                                                               p_generation => v_generation);
    p_info := jsonb_build_object('hash_range', v_hash_range::text, 'rebuild', v_rebuild);
END;
$derive_statistical_history_facet_delta_partition$;

-- Runs after derive_statistical_unit has filled statistical_unit_staging and before the flush. Spawns one
-- concurrent child per hash range holding a refreshed unit; on a rebuild, one child per hash range of all
-- units. Ranges are sized by public.partition_count_target_for the units this cycle covers
-- (statistical_unit before the flush, or the staged units on a first load), as the flush then sets
-- partition_count_target; any split is exact, since each unit is in one range.
-- The children tag their rows with this task's id as generation; the rows count once this cycle's flush
-- commits (worker.statistical_history_facet_delta_state).
CREATE PROCEDURE worker.derive_statistical_history_facet_delta(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_history_facet_delta$
DECLARE
    v_task_id bigint;
    v_state worker.statistical_history_facet_delta_state;
    v_rebuild boolean;
    v_range_size integer;
    v_range int4range;
    v_child_count integer := 0;
    v_discarded bigint := 0;
BEGIN
    SELECT id INTO v_task_id FROM worker.tasks
     WHERE state = 'processing' AND worker_pid = pg_backend_pid()
     ORDER BY id DESC LIMIT 1;
    SELECT * INTO v_state FROM worker.statistical_history_facet_delta_state FOR UPDATE;

    -- Rebuild on an all-time derive (valid_from = -infinity, valid_until = infinity:
    -- worker.enqueue_derive_statistical_unit_all), while an earlier rebuild is not yet added, when units
    -- were flushed without their deltas, and on a cycle that finds the tables empty while statistical_unit
    -- has rows.
    v_rebuild := ((payload->>'valid_from')::date = '-infinity'::date AND (payload->>'valid_until')::date = 'infinity'::date)
        OR v_state.rebuild_generation IS NOT NULL
        OR v_state.rebuild_needed
        OR (NOT EXISTS (SELECT 1 FROM public.statistical_history_facet_stock_delta LIMIT 1)
            AND EXISTS (SELECT 1 FROM public.statistical_unit LIMIT 1));

    IF v_rebuild THEN
        -- The rebuild's rows replace the tables, so no earlier staged row is needed.
        SELECT (SELECT count(*) FROM public.statistical_history_facet_stock_delta_staging)
             + (SELECT count(*) FROM public.statistical_history_facet_flow_delta_staging) INTO v_discarded;
        TRUNCATE public.statistical_history_facet_stock_delta_staging, public.statistical_history_facet_flow_delta_staging;
        UPDATE worker.statistical_history_facet_delta_state
           SET rebuild_generation = v_task_id, rebuild_needed = false;
    ELSE
        -- Rows of a cycle whose flush never committed: its units are still in statistical_unit_staging
        -- and are staged again below, against the same statistical_unit.
        WITH s AS (DELETE FROM public.statistical_history_facet_stock_delta_staging
                    WHERE generation > v_state.flushed_generation RETURNING 1),
             f AS (DELETE FROM public.statistical_history_facet_flow_delta_staging
                    WHERE generation > v_state.flushed_generation RETURNING 1)
        SELECT (SELECT count(*) FROM s) + (SELECT count(*) FROM f) INTO v_discarded;
    END IF;

    v_range_size := GREATEST(1, 16384 / public.partition_count_target_for(GREATEST(
        (SELECT count(*) FROM public.statistical_unit),
        (SELECT count(*) FROM public.statistical_unit_staging))));

    FOR v_range IN
        SELECT DISTINCT int4range((s.hash_slot / v_range_size) * v_range_size,
                                  LEAST((s.hash_slot / v_range_size) * v_range_size + v_range_size, 16384))
          FROM (SELECT hash_slot FROM public.statistical_unit_staging
                UNION ALL
                SELECT hash_slot FROM public.statistical_unit WHERE v_rebuild) AS s
         ORDER BY 1
    LOOP
        PERFORM worker.spawn(
            p_command => 'derive_statistical_history_facet_delta_partition',
            p_payload => jsonb_build_object('command', 'derive_statistical_history_facet_delta_partition',
                                            'hash_range', v_range::text, 'rebuild', v_rebuild,
                                            'generation', v_task_id),
            p_parent_id => v_task_id);
        v_child_count := v_child_count + 1;
    END LOOP;

    p_info := jsonb_build_object('child_count', v_child_count, 'rebuild', v_rebuild, 'range_size', v_range_size,
                                 'unflushed_rows_discarded', v_discarded);
END;
$derive_statistical_history_facet_delta$;

-- Last step of the reports phase: adds the staged deltas that count into the tables (a rebuild's replace
-- them), refreshes the period list, and clears the dirty hash slots every report derive of this cycle has
-- read.
CREATE PROCEDURE worker.statistical_history_facet_delta_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $statistical_history_facet_delta_reduce_cmd$
DECLARE
    v_state worker.statistical_history_facet_delta_state;
    v_stock_staged bigint;
    v_flow_staged bigint;
    v_applied text;
BEGIN
    SELECT * INTO v_state FROM worker.statistical_history_facet_delta_state FOR UPDATE;
    SELECT count(*) INTO v_stock_staged FROM public.statistical_history_facet_stock_delta_staging
     WHERE generation <= v_state.flushed_generation;
    SELECT count(*) INTO v_flow_staged FROM public.statistical_history_facet_flow_delta_staging
     WHERE generation <= v_state.flushed_generation;
    IF v_state.rebuild_generation IS NULL THEN
        CALL worker.statistical_history_facet_delta_apply();
        v_applied := 'added';
    ELSIF v_state.rebuild_generation <= v_state.flushed_generation THEN
        CALL worker.statistical_history_facet_delta_apply(p_replace => true);
        UPDATE worker.statistical_history_facet_delta_state SET rebuild_generation = NULL;
        v_applied := 'replaced';
    ELSE
        -- The rebuild cycle's flush has not committed: the tables keep their rows, and the next cycle
        -- rebuilds again.
        v_applied := 'rebuild not flushed';
    END IF;
    CALL public.statistical_history_period_refresh();
    TRUNCATE public.statistical_unit_facet_dirty_hash_slots;
    PERFORM pg_notify('worker_status',
        json_build_object('type', 'is_deriving_reports', 'status', false)::text);
    p_info := jsonb_build_object('stock_rows_staged', v_stock_staged, 'flow_rows_staged', v_flow_staged,
                                 'applied', v_applied);
END;
$statistical_history_facet_delta_reduce_cmd$;

INSERT INTO worker.command_registry (command, handler_procedure, description, queue) VALUES
    ('derive_statistical_history_facet_delta', 'worker.derive_statistical_history_facet_delta',
     'Spawn one history delta child per hash range of the units refreshed this cycle (or of all units for a rebuild)', 'analytics'),
    ('derive_statistical_history_facet_delta_partition', 'worker.derive_statistical_history_facet_delta_partition',
     'Stage the history deltas of one hash range: new versions in statistical_unit_staging minus old ones in statistical_unit', 'analytics'),
    ('statistical_history_facet_delta_reduce', 'worker.statistical_history_facet_delta_reduce',
     'Add the staged history deltas into statistical_history_facet_stock_delta and statistical_history_facet_flow_delta', 'analytics');
INSERT INTO worker.pipeline_step_weight (step, weight, seq, phase) VALUES
    ('derive_statistical_history_facet_delta', 10, 2, 'is_deriving_statistical_units'),
    ('statistical_history_facet_delta_reduce', 2, 9, 'is_deriving_reports');
UPDATE worker.pipeline_step_weight SET seq = 3 WHERE step = 'statistical_unit_flush_staging';

-- ===================================================================== periods and views
-- The periods the reports show, as get_statistical_history_periods() gives them for the current data.
-- Kept as a table because the function scans statistical_unit; statistical_history_facet_delta_reduce refreshes it.
CREATE TABLE public.statistical_history_period (
    resolution public.history_resolution NOT NULL,
    year integer NOT NULL,
    month integer,
    prev_stop date NOT NULL,
    curr_start date NOT NULL,
    curr_stop date NOT NULL
);
CREATE UNIQUE INDEX statistical_history_period_key ON public.statistical_history_period (resolution, year, month) NULLS NOT DISTINCT;
COMMENT ON TABLE public.statistical_history_period IS 'The periods statistical_history and statistical_history_facet show: get_statistical_history_periods() for the current data, refreshed by worker.statistical_history_facet_delta_reduce.';

CREATE PROCEDURE public.statistical_history_period_refresh()
LANGUAGE plpgsql AS $statistical_history_period_refresh$
BEGIN
    DELETE FROM public.statistical_history_period;
    INSERT INTO public.statistical_history_period (resolution, year, month, prev_stop, curr_start, curr_stop)
    SELECT resolution, year, month, prev_stop, curr_start, curr_stop FROM public.get_statistical_history_periods();
END;
$statistical_history_period_refresh$;

-- Filled by the statistical_history_facet_delta_reduce of the rebuild this migration enqueues; the tables start empty.

-- ===================================================================== views with today's names
CREATE VIEW public.statistical_history_facet WITH (security_invoker = on) AS
WITH stock AS (
    SELECT d.unit_type, d.primary_activity_category_path, d.secondary_activity_category_path, d.sector_path,
           d.legal_form_id, d.physical_region_path, d.physical_country_id, d.unit_size_id, d.status_id, d.on_month,
           sum(d.exists_delta) OVER w AS exists_count, sum(d.countable_delta) OVER w AS countable_count,
           public.jsonb_stats_delta_agg(d.stats_delta) OVER w AS stats_stock,
           lead(d.on_month) OVER w AS next_date
      FROM public.statistical_history_facet_stock_delta AS d
    WINDOW w AS (PARTITION BY d.unit_type, d.primary_activity_category_path, d.secondary_activity_category_path,
                 d.sector_path, d.legal_form_id, d.physical_region_path, d.physical_country_id, d.unit_size_id,
                 d.status_id ORDER BY d.on_month)
), parts AS (
    SELECT p.resolution, p.year, p.month, s.unit_type, s.primary_activity_category_path, s.secondary_activity_category_path,
           s.sector_path, s.legal_form_id, s.physical_region_path, s.physical_country_id, s.unit_size_id, s.status_id,
           (s.exists_count <> 0 OR s.countable_count <> 0) AS has_row, s.exists_count, s.countable_count,
           NULL::integer[] AS flows, s.stats_stock AS stats
      FROM public.statistical_history_period AS p
      JOIN stock AS s ON s.on_month <= p.curr_stop AND (s.next_date IS NULL OR p.curr_stop < s.next_date)
    UNION ALL
    SELECT f.resolution, f.year, f.month, f.unit_type, f.primary_activity_category_path, f.secondary_activity_category_path,
           f.sector_path, f.legal_form_id, f.physical_region_path, f.physical_country_id, f.unit_size_id, f.status_id,
           EXISTS (SELECT 1 FROM unnest(f.flows) AS x WHERE x <> 0), 0, 0, f.flows, f.stats_ended
      FROM public.statistical_history_facet_flow_delta AS f
      JOIN public.statistical_history_period AS p ON p.resolution = f.resolution AND p.year = f.year AND p.month IS NOT DISTINCT FROM f.month
)
SELECT resolution, year, month, unit_type, primary_activity_category_path, secondary_activity_category_path,
       sector_path, legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id,
       sum(exists_count)::integer AS exists_count,
       COALESCE(sum(flows[1]), 0)::integer AS exists_change,
       COALESCE(sum(flows[2]), 0)::integer AS exists_added_count,
       COALESCE(sum(flows[3]), 0)::integer AS exists_removed_count,
       sum(countable_count)::integer AS countable_count,
       COALESCE(sum(flows[4]), 0)::integer AS countable_change,
       COALESCE(sum(flows[5]), 0)::integer AS countable_added_count,
       COALESCE(sum(flows[6]), 0)::integer AS countable_removed_count,
       COALESCE(sum(flows[7]), 0)::integer AS births,
       COALESCE(sum(flows[8]), 0)::integer AS deaths,
       COALESCE(sum(flows[9]), 0)::integer AS name_change_count,
       COALESCE(sum(flows[10]), 0)::integer AS primary_activity_category_change_count,
       COALESCE(sum(flows[11]), 0)::integer AS secondary_activity_category_change_count,
       COALESCE(sum(flows[12]), 0)::integer AS sector_change_count,
       COALESCE(sum(flows[13]), 0)::integer AS legal_form_change_count,
       COALESCE(sum(flows[14]), 0)::integer AS physical_region_change_count,
       COALESCE(sum(flows[15]), 0)::integer AS physical_country_change_count,
       COALESCE(sum(flows[16]), 0)::integer AS physical_address_change_count,
       COALESCE(sum(flows[17]), 0)::integer AS unit_size_change_count,
       COALESCE(sum(flows[18]), 0)::integer AS status_change_count,
       COALESCE(public.jsonb_stats_delta_to_agg(public.jsonb_stats_delta_agg(stats)), '{}'::jsonb) AS stats_summary
  FROM parts
 GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
HAVING bool_or(has_row);

-- Without dimensions: the deltas are aggregated per unit type and month first (sums are linear), then per
-- period: the stock at a period end is the sum of the months up to it, joined on the few aggregated rows
-- rather than per period over the delta table. Flows are grouped by period directly.
CREATE VIEW public.statistical_history WITH (security_invoker = on) AS
WITH per_month AS (
    SELECT d.unit_type, d.on_month, sum(d.exists_delta) AS exists_delta, sum(d.countable_delta) AS countable_delta,
           public.jsonb_stats_delta_agg(d.stats_delta) AS stats_delta
      FROM public.statistical_history_facet_stock_delta AS d GROUP BY 1, 2
), stock AS (
    SELECT p.resolution, p.year, p.month, m.unit_type, sum(m.exists_delta) AS exists_count,
           sum(m.countable_delta) AS countable_count, public.jsonb_stats_delta_agg(m.stats_delta) AS stats_stock
      FROM public.statistical_history_period AS p
      JOIN per_month AS m ON m.on_month <= p.curr_stop
     GROUP BY 1, 2, 3, 4
), flow AS (
    SELECT f.resolution, f.year, f.month, f.unit_type,
           ARRAY[sum(f.flows[1]), sum(f.flows[2]), sum(f.flows[3]), sum(f.flows[4]), sum(f.flows[5]), sum(f.flows[6]),
                 sum(f.flows[7]), sum(f.flows[8]), sum(f.flows[9]), sum(f.flows[10]), sum(f.flows[11]), sum(f.flows[12]),
                 sum(f.flows[13]), sum(f.flows[14]), sum(f.flows[15]), sum(f.flows[16]), sum(f.flows[17]),
                 sum(f.flows[18])]::integer[] AS flows,
           public.jsonb_stats_delta_agg(f.stats_ended) AS stats_ended
      FROM public.statistical_history_facet_flow_delta AS f GROUP BY 1, 2, 3, 4
)
SELECT COALESCE(s.resolution, f.resolution) AS resolution, COALESCE(s.year, f.year) AS year,
       COALESCE(s.month, f.month) AS month, COALESCE(s.unit_type, f.unit_type) AS unit_type,
       COALESCE(s.exists_count, 0)::integer AS exists_count,
       COALESCE(f.flows[1], 0) AS exists_change, COALESCE(f.flows[2], 0) AS exists_added_count,
       COALESCE(f.flows[3], 0) AS exists_removed_count,
       COALESCE(s.countable_count, 0)::integer AS countable_count,
       COALESCE(f.flows[4], 0) AS countable_change, COALESCE(f.flows[5], 0) AS countable_added_count,
       COALESCE(f.flows[6], 0) AS countable_removed_count,
       COALESCE(f.flows[7], 0) AS births, COALESCE(f.flows[8], 0) AS deaths,
       COALESCE(f.flows[9], 0) AS name_change_count,
       COALESCE(f.flows[10], 0) AS primary_activity_category_change_count,
       COALESCE(f.flows[11], 0) AS secondary_activity_category_change_count,
       COALESCE(f.flows[12], 0) AS sector_change_count, COALESCE(f.flows[13], 0) AS legal_form_change_count,
       COALESCE(f.flows[14], 0) AS physical_region_change_count,
       COALESCE(f.flows[15], 0) AS physical_country_change_count,
       COALESCE(f.flows[16], 0) AS physical_address_change_count,
       COALESCE(public.jsonb_stats_delta_to_agg(public.jsonb_stats_delta_merge(
           COALESCE(s.stats_stock, '{"type": "stats_delta"}'), COALESCE(f.stats_ended, '{"type": "stats_delta"}'))),
           '{}'::jsonb) AS stats_summary,
       NULL::int4range AS hash_partition
  FROM stock AS s
  FULL JOIN (SELECT f.* FROM flow AS f
              WHERE EXISTS (SELECT 1 FROM public.statistical_history_period AS p
                             WHERE p.resolution = f.resolution AND p.year = f.year
                               AND COALESCE(p.month, 0) = COALESCE(f.month, 0))) AS f
    ON f.unit_type = s.unit_type AND f.resolution = s.resolution AND f.year = s.year
   AND COALESCE(f.month, 0) = COALESCE(s.month, 0)
 -- A period shows when units exist at its end or changed in it; the stock's stats come along either way
 -- (a unit that died in the period has count 0 but its stats still hold for the period).
 WHERE COALESCE(s.exists_count, 0) <> 0 OR COALESCE(s.countable_count, 0) <> 0 OR f.unit_type IS NOT NULL;

-- The statistical_history rows of one resolution and unit type (optionally one year), aggregated first from the
-- deltas of that unit type only: per month, then per asked period end. The view computes every unit type and
-- period before the filter applies; readers that know their filter call this instead.
CREATE FUNCTION public.statistical_history_for(p_resolution history_resolution, p_unit_type statistical_unit_type, p_year integer DEFAULT NULL)
 RETURNS SETOF public.statistical_history
 LANGUAGE sql STABLE
 SET search_path TO 'public', 'pg_temp'
AS $statistical_history_for$
    WITH period AS MATERIALIZED (
        SELECT p.resolution, p.year, p.month, p.curr_stop FROM public.statistical_history_period AS p
         WHERE p.resolution = p_resolution AND (p_year IS NULL OR p.year = p_year)
    ), per_month AS MATERIALIZED (
        SELECT d.on_month, sum(d.exists_delta) AS exists_delta, sum(d.countable_delta) AS countable_delta,
               public.jsonb_stats_delta_agg(d.stats_delta) FILTER (WHERE d.stats_delta IS NOT NULL) AS stats_delta
          FROM public.statistical_history_facet_stock_delta AS d
         WHERE d.unit_type = p_unit_type AND d.on_month <= (SELECT max(curr_stop) FROM period)
         GROUP BY 1
    ), stock AS MATERIALIZED (
        SELECT p.year, p.month, sum(m.exists_delta) AS exists_count, sum(m.countable_delta) AS countable_count,
               public.jsonb_stats_delta_agg(m.stats_delta) FILTER (WHERE m.stats_delta IS NOT NULL) AS stats_stock
          FROM period AS p JOIN per_month AS m ON m.on_month <= p.curr_stop
         GROUP BY 1, 2
    ), flow AS MATERIALIZED (
        SELECT f.year, f.month,
               ARRAY[sum(f.flows[1]), sum(f.flows[2]), sum(f.flows[3]), sum(f.flows[4]), sum(f.flows[5]), sum(f.flows[6]),
                     sum(f.flows[7]), sum(f.flows[8]), sum(f.flows[9]), sum(f.flows[10]), sum(f.flows[11]), sum(f.flows[12]),
                     sum(f.flows[13]), sum(f.flows[14]), sum(f.flows[15]), sum(f.flows[16]), sum(f.flows[17]),
                     sum(f.flows[18])]::integer[] AS flows,
               public.jsonb_stats_delta_agg(f.stats_ended) FILTER (WHERE f.stats_ended IS NOT NULL) AS stats_ended
          FROM public.statistical_history_facet_flow_delta AS f
          JOIN period AS p ON p.year = f.year AND COALESCE(p.month, 0) = COALESCE(f.month, 0)
         WHERE f.resolution = p_resolution AND f.unit_type = p_unit_type
           AND (p_year IS NULL OR f.year = p_year)
         GROUP BY 1, 2
    )
    SELECT p_resolution, COALESCE(s.year, f.year), COALESCE(s.month, f.month), p_unit_type,
           COALESCE(s.exists_count, 0)::integer,
           COALESCE(f.flows[1], 0), COALESCE(f.flows[2], 0), COALESCE(f.flows[3], 0),
           COALESCE(s.countable_count, 0)::integer,
           COALESCE(f.flows[4], 0), COALESCE(f.flows[5], 0), COALESCE(f.flows[6], 0),
           COALESCE(f.flows[7], 0), COALESCE(f.flows[8], 0), COALESCE(f.flows[9], 0),
           COALESCE(f.flows[10], 0), COALESCE(f.flows[11], 0), COALESCE(f.flows[12], 0), COALESCE(f.flows[13], 0),
           COALESCE(f.flows[14], 0), COALESCE(f.flows[15], 0), COALESCE(f.flows[16], 0),
           COALESCE(public.jsonb_stats_delta_to_agg(public.jsonb_stats_delta_merge(
               COALESCE(s.stats_stock, '{"type": "stats_delta"}'), COALESCE(f.stats_ended, '{"type": "stats_delta"}'))),
               '{}'::jsonb),
           NULL::int4range
      FROM stock AS s
      FULL JOIN flow AS f ON f.year = s.year AND COALESCE(f.month, 0) = COALESCE(s.month, 0)
     WHERE COALESCE(s.exists_count, 0) <> 0 OR COALESCE(s.countable_count, 0) <> 0 OR f.year IS NOT NULL
$statistical_history_for$;
COMMENT ON FUNCTION public.statistical_history_for(history_resolution, statistical_unit_type, integer) IS 'The rows of statistical_history for one resolution and unit type, optionally one year: the same rows and columns, computed from the deltas of that unit type only.';

-- ===================================================================== flush
-- The flush moves the staged versions into statistical_unit. In the same transaction it marks this cycle's
-- staged history rows as counting: they were computed against the statistical_unit the flush replaces. The
-- cycle's history step is the derive_statistical_history_facet_delta sibling under the same
-- derive_units_phase; its rows count when it completed (every range staged). When it failed, or the tree
-- has none, the units move without their deltas and the next cycle rebuilds.
CREATE OR REPLACE PROCEDURE worker.statistical_unit_flush_staging(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_staging_count bigint;
    v_history_task worker.tasks;
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

    SELECT h.* INTO v_history_task
      FROM worker.tasks AS me
      JOIN worker.tasks AS h ON h.parent_id = me.parent_id AND h.command = 'derive_statistical_history_facet_delta'
     WHERE me.state = 'processing' AND me.worker_pid = pg_backend_pid() AND me.command = 'statistical_unit_flush_staging'
     ORDER BY h.id DESC LIMIT 1;
    IF v_history_task.state = 'completed' THEN
        UPDATE worker.statistical_history_facet_delta_state SET flushed_generation = v_history_task.id;
    ELSIF EXISTS (SELECT 1 FROM public.statistical_unit_staging) THEN
        UPDATE worker.statistical_history_facet_delta_state SET rebuild_needed = true;
    END IF;

    SELECT count(*) INTO v_staging_count FROM public.statistical_unit_staging;
    CALL public.statistical_unit_flush_staging();
    PERFORM pg_notify('worker_status',
        json_build_object('type', 'is_deriving_statistical_units', 'status', false)::text);
    p_info := jsonb_build_object('rows_flushed', v_staging_count,
                                 'history_generation_flushed', CASE WHEN v_history_task.state = 'completed' THEN v_history_task.id END);
END;
$procedure$;

-- ===================================================================== pipeline
-- collect_changes: derive_statistical_history_facet_delta before the flush, statistical_history_facet_delta_reduce last in the reports phase.
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
            p_command => 'derive_statistical_history_facet_delta',
            p_payload => v_payload,
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
            p_command => 'statistical_history_facet_delta_reduce',
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

-- derive_statistical_unit: deleted units lose their history contribution before their rows are deleted.
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
                -- The history deltas lose the unit's contribution here; the flush never sees it again.
                CALL worker.statistical_history_facet_delta_remove_units(p_unit_type => 'enterprise', p_unit_ids => v_orphan_enterprise_ids);
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
                CALL worker.statistical_history_facet_delta_remove_units(p_unit_type => 'legal_unit', p_unit_ids => v_orphan_legal_unit_ids);
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
                CALL worker.statistical_history_facet_delta_remove_units(p_unit_type => 'establishment', p_unit_ids => v_orphan_establishment_ids);
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
                CALL worker.statistical_history_facet_delta_remove_units(p_unit_type => 'power_group', p_unit_ids => v_orphan_power_group_ids);
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
    PERFORM admin.add_rls_regular_user_can_read('public.statistical_history_facet_stock_delta'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.statistical_history_facet_flow_delta'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.statistical_history_period'::regclass);
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
            public.statistical_history_facet_stock_delta,
            public.statistical_history_facet_flow_delta,
            public.statistical_history_facet_stock_delta_staging,
            public.statistical_history_facet_flow_delta_staging,
            public.statistical_history_period;

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

-- statistical_history_highcharts: reads public.statistical_history_for instead of filtering the view.
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
    FROM public.statistical_history_for(p_resolution, p_unit_type, p_year) AS sh;

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
        FROM public.statistical_history_for(p_resolution, p_unit_type, p_year)
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

-- statistical_history_drilldown reads the delta tables directly: it filters the deltas, groups them by the
-- asked dimension, and sums, instead of reading statistical_history_facet period by period and cell by cell.
-- Same signature and JSON (stats per period, breadcrumbs, available breakdowns with counts and has_children).
CREATE OR REPLACE FUNCTION public.statistical_history_drilldown(unit_type statistical_unit_type DEFAULT 'enterprise'::statistical_unit_type, resolution history_resolution DEFAULT 'year'::history_resolution, year integer DEFAULT NULL::integer, region_path ltree DEFAULT NULL::ltree, activity_category_path ltree DEFAULT NULL::ltree, sector_path ltree DEFAULT NULL::ltree, status_id integer DEFAULT NULL::integer, legal_form_id integer DEFAULT NULL::integer, country_id integer DEFAULT NULL::integer, year_min integer DEFAULT NULL::integer, year_max integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    WITH params AS MATERIALIZED (
        SELECT unit_type AS param_unit_type, resolution AS param_resolution, year AS param_year,
               region_path AS param_region_path, activity_category_path AS param_activity_category_path,
               sector_path AS param_sector_path, legal_form_id AS param_legal_form_id, status_id AS param_status_id,
               country_id AS param_country_id,
               statistical_history_drilldown.year_min AS param_year_min,
               statistical_history_drilldown.year_max AS param_year_max,
               -- The unit types to read, as an array the indexes on unit_type can use (NULL: all).
               CASE WHEN unit_type IS NULL THEN enum_range(NULL::public.statistical_unit_type)
                    ELSE ARRAY[unit_type] END AS param_unit_types
    ), settings_activity_category_standard AS (
        SELECT activity_category_standard_id AS id FROM public.settings
    ),
    -- The asked periods.
    period AS MATERIALIZED (
        SELECT p.resolution, p.year, p.month, p.curr_stop
          FROM public.statistical_history_period AS p, params
         WHERE (param_resolution IS NULL OR p.resolution = param_resolution)
           AND (param_year IS NULL OR p.year = param_year)
           AND (param_year_min IS NULL OR p.year >= param_year_min)
           AND (param_year_max IS NULL OR p.year <= param_year_max)
    ),
    -- Stock deltas of the asked unit type that pass every filter. Rows dated after the last asked period end
    -- cannot reach any period.
    stock AS MATERIALIZED (
        SELECT d.primary_activity_category_path, d.sector_path, d.legal_form_id, d.physical_region_path,
               d.physical_country_id, d.status_id, d.on_month, d.exists_delta, d.countable_delta
          FROM public.statistical_history_facet_stock_delta AS d, params
         WHERE d.unit_type = ANY (ARRAY(SELECT unnest(param_unit_types) FROM params))
           AND d.on_month <= (SELECT max(curr_stop) FROM period)
           AND (param_region_path IS NULL OR d.physical_region_path IS NOT NULL AND d.physical_region_path OPERATOR(public.<@) param_region_path)
           AND (param_activity_category_path IS NULL OR d.primary_activity_category_path IS NOT NULL AND d.primary_activity_category_path OPERATOR(public.<@) param_activity_category_path)
           AND (param_sector_path IS NULL OR d.sector_path IS NOT NULL AND d.sector_path OPERATOR(public.<@) param_sector_path)
           AND (param_legal_form_id IS NULL OR d.legal_form_id IS NOT NULL AND d.legal_form_id = param_legal_form_id)
           AND (param_status_id IS NULL OR d.status_id IS NOT NULL AND d.status_id = param_status_id)
           AND (param_country_id IS NULL OR d.physical_country_id IS NOT NULL AND d.physical_country_id = param_country_id)
    ),
    -- How many asked period ends each month's deltas reach.
    month_periods AS MATERIALIZED (
        SELECT m.on_month, (SELECT count(*) FROM period AS p WHERE m.on_month <= p.curr_stop) AS periods
          FROM (SELECT DISTINCT on_month FROM stock) AS m
    ),
    -- A breakdown count is the countable stock at each asked period end, summed over the periods. The stock
    -- at an end is the sum of the deltas up to it, so the total is each delta times the periods it reaches.
    weight AS MATERIALIZED (
        SELECT s.primary_activity_category_path, s.sector_path, s.legal_form_id, s.physical_region_path,
               s.physical_country_id, s.status_id, s.countable_delta * mp.periods AS count
          FROM stock AS s JOIN month_periods AS mp USING (on_month)
         WHERE s.countable_delta <> 0
    ),
    flow AS MATERIALIZED (
        SELECT f.year, f.month,
               sum(f.flows[1])::bigint AS exists_change, sum(f.flows[2])::bigint AS exists_added_count,
               sum(f.flows[3])::bigint AS exists_removed_count, sum(f.flows[4])::bigint AS countable_change,
               sum(f.flows[5])::bigint AS countable_added_count, sum(f.flows[6])::bigint AS countable_removed_count,
               sum(f.flows[7])::bigint AS births, sum(f.flows[8])::bigint AS deaths,
               sum(f.flows[9])::bigint AS name_change_count, sum(f.flows[10])::bigint AS primary_activity_category_change_count,
               sum(f.flows[11])::bigint AS secondary_activity_category_change_count, sum(f.flows[12])::bigint AS sector_change_count,
               sum(f.flows[13])::bigint AS legal_form_change_count, sum(f.flows[14])::bigint AS physical_region_change_count,
               sum(f.flows[15])::bigint AS physical_country_change_count, sum(f.flows[16])::bigint AS physical_address_change_count,
               sum(f.flows[17])::bigint AS unit_size_change_count, sum(f.flows[18])::bigint AS status_change_count,
               public.jsonb_stats_delta_agg(f.stats_ended) FILTER (WHERE f.stats_ended IS NOT NULL) AS stats_ended
          FROM public.statistical_history_facet_flow_delta AS f
          JOIN period AS p ON p.resolution = f.resolution AND p.year = f.year AND COALESCE(p.month, 0) = COALESCE(f.month, 0)
             , params
         -- One index range per asked resolution and year; the month is matched in the join.
         WHERE f.resolution = ANY (ARRAY(SELECT DISTINCT resolution FROM period))
           AND f.year = ANY (ARRAY(SELECT DISTINCT year FROM period))
           AND f.unit_type = ANY (ARRAY(SELECT unnest(param_unit_types) FROM params))
           AND (param_region_path IS NULL OR f.physical_region_path IS NOT NULL AND f.physical_region_path OPERATOR(public.<@) param_region_path)
           AND (param_activity_category_path IS NULL OR f.primary_activity_category_path IS NOT NULL AND f.primary_activity_category_path OPERATOR(public.<@) param_activity_category_path)
           AND (param_sector_path IS NULL OR f.sector_path IS NOT NULL AND f.sector_path OPERATOR(public.<@) param_sector_path)
           AND (param_legal_form_id IS NULL OR f.legal_form_id IS NOT NULL AND f.legal_form_id = param_legal_form_id)
           AND (param_status_id IS NULL OR f.status_id IS NOT NULL AND f.status_id = param_status_id)
           AND (param_country_id IS NULL OR f.physical_country_id IS NOT NULL AND f.physical_country_id = param_country_id)
         GROUP BY 1, 2
    ),
    -- Stats of the stock: per month first, then per period end.
    stats_month AS MATERIALIZED (
        SELECT d.on_month, public.jsonb_stats_delta_agg(d.stats_delta) AS stats_delta
          FROM public.statistical_history_facet_stock_delta AS d, params
         WHERE d.stats_delta IS NOT NULL
           AND d.unit_type = ANY (ARRAY(SELECT unnest(param_unit_types) FROM params))
           AND d.on_month <= (SELECT max(curr_stop) FROM period)
           AND (param_region_path IS NULL OR d.physical_region_path IS NOT NULL AND d.physical_region_path OPERATOR(public.<@) param_region_path)
           AND (param_activity_category_path IS NULL OR d.primary_activity_category_path IS NOT NULL AND d.primary_activity_category_path OPERATOR(public.<@) param_activity_category_path)
           AND (param_sector_path IS NULL OR d.sector_path IS NOT NULL AND d.sector_path OPERATOR(public.<@) param_sector_path)
           AND (param_legal_form_id IS NULL OR d.legal_form_id IS NOT NULL AND d.legal_form_id = param_legal_form_id)
           AND (param_status_id IS NULL OR d.status_id IS NOT NULL AND d.status_id = param_status_id)
           AND (param_country_id IS NULL OR d.physical_country_id IS NOT NULL AND d.physical_country_id = param_country_id)
         GROUP BY 1
    ),
    count_month AS MATERIALIZED (
        SELECT s.on_month, sum(s.exists_delta) AS exists_delta, sum(s.countable_delta) AS countable_delta
          FROM stock AS s GROUP BY 1
    ),
    stock_period AS MATERIALIZED (
        SELECT p.year, p.month,
               COALESCE((SELECT sum(c.exists_delta) FROM count_month AS c WHERE c.on_month <= p.curr_stop), 0) AS exists_count,
               COALESCE((SELECT sum(c.countable_delta) FROM count_month AS c WHERE c.on_month <= p.curr_stop), 0) AS countable_count,
               (SELECT public.jsonb_stats_delta_agg(m.stats_delta) FROM stats_month AS m WHERE m.on_month <= p.curr_stop) AS stats_stock
          FROM period AS p
    ),
    available_history_stats AS (
        SELECT sp.year, sp.month
             , sp.exists_count::integer AS exists_count
             , COALESCE(f.exists_change, 0)::integer AS exists_change
             , COALESCE(f.exists_added_count, 0)::integer AS exists_added_count
             , COALESCE(f.exists_removed_count, 0)::integer AS exists_removed_count
             , sp.countable_count::integer AS countable_count
             , COALESCE(f.countable_change, 0)::integer AS countable_change
             , COALESCE(f.countable_added_count, 0)::integer AS countable_added_count
             , COALESCE(f.countable_removed_count, 0)::integer AS countable_removed_count
             , COALESCE(f.births, 0)::integer AS births
             , COALESCE(f.deaths, 0)::integer AS deaths
             , COALESCE(f.name_change_count, 0)::integer AS name_change_count
             , COALESCE(f.primary_activity_category_change_count, 0)::integer AS primary_activity_category_change_count
             , COALESCE(f.secondary_activity_category_change_count, 0)::integer AS secondary_activity_category_change_count
             , COALESCE(f.sector_change_count, 0)::integer AS sector_change_count
             , COALESCE(f.legal_form_change_count, 0)::integer AS legal_form_change_count
             , COALESCE(f.physical_region_change_count, 0)::integer AS physical_region_change_count
             , COALESCE(f.physical_country_change_count, 0)::integer AS physical_country_change_count
             , COALESCE(f.physical_address_change_count, 0)::integer AS physical_address_change_count
             , COALESCE(f.unit_size_change_count, 0)::integer AS unit_size_change_count
             , COALESCE(f.status_change_count, 0)::integer AS status_change_count
             , COALESCE(public.jsonb_stats_delta_to_agg(
                   CASE WHEN sp.stats_stock IS NULL THEN f.stats_ended
                        WHEN f.stats_ended IS NULL THEN sp.stats_stock
                        ELSE public.jsonb_stats_delta_merge(sp.stats_stock, f.stats_ended) END), '{"type": "stats_agg"}'::jsonb) AS stats_summary
          FROM stock_period AS sp
          LEFT JOIN flow AS f ON f.year = sp.year AND f.month IS NOT DISTINCT FROM sp.month
         WHERE sp.exists_count <> 0 OR sp.countable_count <> 0 OR f.year IS NOT NULL
         ORDER BY sp.year ASC, sp.month ASC NULLS FIRST
    ),
    breadcrumb_region AS (
        SELECT r.path, r.label, r.code, r.name FROM public.region AS r
         WHERE region_path IS NOT NULL AND r.path OPERATOR(public.@>) (region_path)
         ORDER BY path
    ),
    available_region AS (
        SELECT r.path, r.label, r.code, r.name FROM public.region AS r
         WHERE (region_path IS NULL AND r.path OPERATOR(public.~) '*{1}'::public.lquery)
            OR (region_path IS NOT NULL AND r.path OPERATOR(public.~) (region_path::text || '.*{1}')::public.lquery)
         ORDER BY r.path
    ), region_weight AS (
        SELECT w.physical_region_path AS path, sum(w.count) AS count
          FROM weight AS w WHERE w.physical_region_path IS NOT NULL GROUP BY 1
    ), aggregated_region_counts AS (
        SELECT ar.path, ar.label, ar.code, ar.name
             , COALESCE(SUM(rw.count), 0) AS count
             , COALESCE(bool_or(true) FILTER (WHERE rw.path OPERATOR(public.<>) ar.path AND rw.count <> 0), false) AS has_children
          FROM available_region AS ar
          LEFT JOIN region_weight AS rw ON rw.path OPERATOR(public.<@) ar.path
         GROUP BY ar.path, ar.label, ar.code, ar.name
    ),
    breadcrumb_activity_category AS (
        SELECT ac.path, ac.label, ac.code, ac.name FROM public.activity_category AS ac
         WHERE ac.enabled AND ac.standard_id = (SELECT id FROM settings_activity_category_standard)
           AND activity_category_path IS NOT NULL AND ac.path OPERATOR(public.@>) activity_category_path
         ORDER BY path
    ),
    available_activity_category AS (
        SELECT ac.path, ac.label, ac.code, ac.name FROM public.activity_category AS ac
         WHERE ac.enabled AND ac.standard_id = (SELECT id FROM settings_activity_category_standard)
           AND ((activity_category_path IS NULL AND ac.path OPERATOR(public.~) '*{1}'::public.lquery)
             OR (activity_category_path IS NOT NULL AND ac.path OPERATOR(public.~) (activity_category_path::text || '.*{1}')::public.lquery))
         ORDER BY ac.path
    ), activity_weight AS (
        SELECT w.primary_activity_category_path AS path, sum(w.count) AS count
          FROM weight AS w WHERE w.primary_activity_category_path IS NOT NULL GROUP BY 1
    ), aggregated_activity_counts AS (
        SELECT aac.path, aac.label, aac.code, aac.name
             , COALESCE(SUM(aw.count), 0) AS count
             , COALESCE(bool_or(true) FILTER (WHERE aw.path OPERATOR(public.<>) aac.path AND aw.count <> 0), false) AS has_children
          FROM available_activity_category AS aac
          LEFT JOIN activity_weight AS aw ON aw.path OPERATOR(public.<@) aac.path
         GROUP BY aac.path, aac.label, aac.code, aac.name
         ORDER BY aac.path
    ),
    breadcrumb_sector AS (
        SELECT s.path, s.label, s.code, s.name FROM public.sector AS s
         WHERE sector_path IS NOT NULL AND s.path OPERATOR(public.@>) (sector_path)
         ORDER BY s.path
    ),
    available_sector AS (
        SELECT "as".path, "as".label, "as".code, "as".name FROM public.sector AS "as"
         WHERE (sector_path IS NULL AND "as".path OPERATOR(public.~) '*{1}'::public.lquery)
            OR (sector_path IS NOT NULL AND "as".path OPERATOR(public.~) (sector_path::text || '.*{1}')::public.lquery)
         ORDER BY "as".path
    ), sector_weight AS (
        SELECT w.sector_path AS path, sum(w.count) AS count
          FROM weight AS w WHERE w.sector_path IS NOT NULL GROUP BY 1
    ), aggregated_sector_counts AS (
        SELECT "as".path, "as".label, "as".code, "as".name
             , COALESCE(SUM(sw.count), 0) AS count
             , COALESCE(bool_or(true) FILTER (WHERE sw.path OPERATOR(public.<>) "as".path AND sw.count <> 0), false) AS has_children
          FROM available_sector AS "as"
          LEFT JOIN sector_weight AS sw ON sw.path OPERATOR(public.<@) "as".path
         GROUP BY "as".path, "as".label, "as".code, "as".name
         ORDER BY "as".path
    ),
    breadcrumb_legal_form AS (
        SELECT lf.id, lf.code, lf.name FROM public.legal_form AS lf
         WHERE legal_form_id IS NOT NULL AND lf.id = legal_form_id
         ORDER BY lf.code
    ),
    available_legal_form AS (
        SELECT lf.id, lf.code, lf.name FROM public.legal_form AS lf
         -- Every legal form is available, unless one is selected.
         WHERE legal_form_id IS NULL
         ORDER BY lf.code
    ), legal_form_weight AS (
        SELECT w.legal_form_id AS id, sum(w.count) AS count FROM weight AS w WHERE w.legal_form_id IS NOT NULL GROUP BY 1
    ), aggregated_legal_form_counts AS (
        SELECT lf.id, lf.code, lf.name
             , COALESCE(lw.count, 0) AS count
             , false AS has_children
          FROM available_legal_form AS lf
          LEFT JOIN legal_form_weight AS lw ON lw.id = lf.id
         ORDER BY lf.code
    ),
    breadcrumb_status AS (
        SELECT s.id, s.code, s.name FROM public.status AS s
         WHERE status_id IS NOT NULL AND s.id = status_id
         ORDER BY s.code
    ),
    available_status AS (
        SELECT s.id, s.code, s.name FROM public.status AS s
         -- Every status is available, unless one is selected.
         WHERE status_id IS NULL
         ORDER BY s.code
    ), status_weight AS (
        SELECT w.status_id AS id, sum(w.count) AS count FROM weight AS w WHERE w.status_id IS NOT NULL GROUP BY 1
    ), aggregated_status_counts AS (
        SELECT s.id, s.code, s.name
             , COALESCE(sw.count, 0) AS count
             , false AS has_children
          FROM available_status AS s
          LEFT JOIN status_weight AS sw ON sw.id = s.id
         ORDER BY s.code
    ),
    breadcrumb_physical_country AS (
        SELECT pc.id, pc.iso_2, pc.name FROM public.country AS pc
         WHERE country_id IS NOT NULL AND pc.id = country_id
         ORDER BY pc.iso_2
    ),
    available_physical_country AS (
        SELECT pc.id, pc.iso_2, pc.name FROM public.country AS pc
         -- Every country is available, unless one is selected.
         WHERE country_id IS NULL
         ORDER BY pc.iso_2
    ), country_weight AS (
        SELECT w.physical_country_id AS id, sum(w.count) AS count
          FROM weight AS w WHERE w.physical_country_id IS NOT NULL GROUP BY 1
    ), aggregated_physical_country_counts AS (
        SELECT pc.id, pc.iso_2, pc.name
             , COALESCE(cw.count, 0) AS count
             , false AS has_children
          FROM available_physical_country AS pc
          LEFT JOIN country_weight AS cw ON cw.id = pc.id
         ORDER BY pc.iso_2
    )
    SELECT
        jsonb_build_object(
          'unit_type', unit_type,
          'stats', (SELECT jsonb_agg(to_jsonb(source.*)) FROM available_history_stats AS source),
          'breadcrumb', jsonb_build_object(
            'region', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_region AS source),
            'activity_category', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_activity_category AS source),
            'sector', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_sector AS source),
            'legal_form', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_legal_form AS source),
            'status', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_status AS source),
            'country', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_physical_country AS source)
          ),
          'available', jsonb_build_object(
            'region', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_region_counts AS source WHERE count > 0),
            'activity_category', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_activity_counts AS source WHERE count > 0),
            'sector', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_sector_counts AS source WHERE count > 0),
            'legal_form', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_legal_form_counts AS source WHERE count > 0),
            'status', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_status_counts AS source WHERE count > 0),
            'country', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_physical_country_counts AS source WHERE count > 0)
          ),
          'filter', jsonb_build_object(
            'type', param_resolution,
            'year', param_year,
            'unit_type', param_unit_type,
            'region_path', param_region_path,
            'activity_category_path', param_activity_category_path,
            'sector_path', param_sector_path,
            'legal_form_id', param_legal_form_id,
            'status_id', param_status_id,
            'country_id', param_country_id
          )
        )
    FROM params;
$function$;

-- ===================================================================== access
-- The delta tables and periods are read like the other derived tables; the views run as the caller.
SELECT admin.add_rls_regular_user_can_read('public.statistical_history_facet_stock_delta'::regclass);
SELECT admin.add_rls_regular_user_can_read('public.statistical_history_facet_flow_delta'::regclass);
SELECT admin.add_rls_regular_user_can_read('public.statistical_history_period'::regclass);
GRANT SELECT ON public.statistical_history, public.statistical_history_facet TO authenticated, regular_user, admin_user;
-- public.reset runs as the caller (admin_user) and empties the staging with the other derived tables.
GRANT TRUNCATE ON public.statistical_history_facet_stock_delta_staging, public.statistical_history_facet_flow_delta_staging TO admin_user;

COMMENT ON TABLE public.statistical_history_facet_stock_delta IS 'Stock changes per cell and month (on_month): +1/-1 when a unit enters/leaves the cell (exists_delta; countable_delta when it is used for counting) and the stats of counted versions entering and leaving (stats_delta, jsonb_stats stats_delta). The stock at a month end is the sum up to it. unit_ids lists the units contributing to the row. Maintained by worker.derive_statistical_history_facet_delta and worker.statistical_history_facet_delta_reduce.';
COMMENT ON TABLE public.statistical_history_facet_flow_delta IS 'Change counts per cell and period, comparing each unit at the previous and current period end (flows, in the order of the statistical_history_facet columns exists_change .. status_change_count), and the stats of units whose latest overlapping version ended inside the period (stats_ended). unit_ids lists the contributing units.';
COMMENT ON COLUMN public.statistical_history_facet_stock_delta.unit_ids IS 'Units contributing to this row, sorted. A unit leaves when its contribution is removed; the row is deleted when no unit remains.';
COMMENT ON COLUMN public.statistical_history_facet_stock_delta.on_month IS 'First day of the month in which the change takes effect. Every report period ends on a month end, and a change on any day of a month is in the stock at that month''s end, so bucketing by month gives the same stock at every period end as the exact dates. It keeps one row per cell and month however many changes fall inside the month, and a unit''s changes that undo each other within a month leave no row.';
COMMENT ON TABLE public.statistical_history_facet_stock_delta_staging IS 'Signed per-unit rows staged by worker.derive_statistical_history_facet_delta_partition children for this cycle; worker.statistical_history_facet_delta_reduce adds them into statistical_history_facet_stock_delta.';
COMMENT ON TABLE public.statistical_history_facet_flow_delta_staging IS 'Signed per-unit rows staged by worker.derive_statistical_history_facet_delta_partition children for this cycle; worker.statistical_history_facet_delta_reduce adds them into statistical_history_facet_flow_delta.';
COMMENT ON VIEW public.statistical_history IS 'Totals per period and unit type, from statistical_history_facet_stock_delta and statistical_history_facet_flow_delta. stats_summary is the stock read from deltas (jsonb_stats_delta_to_agg): exact count, sum and sum_sq; no min/max, since those cannot be undone when a unit leaves.';
COMMENT ON COLUMN public.statistical_history.hash_partition IS 'Always NULL: every row is a period total. Kept so readers of the former table, which filtered hash_partition IS NULL to get the totals, read the same rows.';
COMMENT ON VIEW public.statistical_history_facet IS 'Counts and stats per period and cell, from statistical_history_facet_stock_delta and statistical_history_facet_flow_delta. stats_summary as in statistical_history: exact count, sum and sum_sq, no min/max.';

-- Rebuild the history deltas from statistical_unit after this migration commits; no-op on an empty database.
SELECT worker.enqueue_derive_statistical_unit_all();

END;
