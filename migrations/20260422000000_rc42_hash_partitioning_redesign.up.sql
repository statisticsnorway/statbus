-- rc.42: hash-partitioning redesign
--
-- Four bundled changes (see tmp/partner-fix-proposal-49.md and GitHub issue #49):
--   1. Fix #49 — data-driven range loop over populated L2 partitions in the
--      three derive spawners. Replaces the range-start-only `FOR … BY v_range_size`
--      loop that silently dropped slots in [modulus, 255] when modulus < 256.
--   2. L1 hash space 256 → 16384. Gives head-room for auto-tune to pick modulus
--      values > 256 without truncating slots.
--   3. L3 storage reshape: statistical_history.partition_seq int → hash_partition
--      int4range. One stored row per L2 range (not per slot), DELETE and INSERT
--      share the same range expression, so partition boundaries are self-consistent.
--   4. Full nomenclature rename:
--        report_partition_seq → hash_slot
--        partition_seq (all sites) → hash_slot / hash_partition / dirty_hash_slot
--        report_partition_modulus → partition_count_target
--        statistical_unit_facet_dirty_partitions → _dirty_hash_slots
--
-- Clean-install context: rune.statbus.org is a fresh deployment of rc.42. NO
-- legacy rows on NO; ET (19 units) rehashes sub-second via Block G.
--
-- Block structure:
--   A — Hash functions (rename + rewrite body with 16384)
--   B — Column and table renames (statistical_unit / _staging / facet / dirty)
--   C — statistical_history: drop + rebuild TYPE and typed table
--   D — Settings + auto-tune rename/rewrite
--   E — Rewrite the three derive spawners (fix #49 + renames)
--   F — Rewrite consumer fns (statistical_history_def / _facet_def + period handlers)
--   G — Rehash stored L1 slots on statistical_unit + _staging
--   H — Mechanical rename of 4 non-spawner INSERT-site routines

BEGIN;

-- ============================================================
-- Block A — Hash functions (rename + rewrite body with 16384)
-- ============================================================

ALTER FUNCTION public.report_partition_seq(text, integer) RENAME TO hash_slot;
ALTER FUNCTION public.report_partition_seq(public.statistical_unit_type, integer) RENAME TO hash_slot;

CREATE OR REPLACE FUNCTION public.hash_slot(p_unit_type text, p_unit_id integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $hash_slot$
    SELECT abs(hashtext(p_unit_type || ':' || p_unit_id::text)) % 16384;
$hash_slot$;

CREATE OR REPLACE FUNCTION public.hash_slot(p_unit_type public.statistical_unit_type, p_unit_id integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $hash_slot$
    SELECT abs(hashtext(p_unit_type::text || ':' || p_unit_id::text)) % 16384;
$hash_slot$;

ALTER FUNCTION public.set_report_partition_seq() RENAME TO set_hash_slot;

CREATE OR REPLACE FUNCTION public.set_hash_slot()
RETURNS trigger
LANGUAGE plpgsql
AS $set_hash_slot$
BEGIN
    NEW.hash_slot := public.hash_slot(NEW.unit_type, NEW.unit_id);
    RETURN NEW;
END;
$set_hash_slot$;

-- ============================================================
-- Block B — Column and table renames
-- ============================================================

-- statistical_unit + _staging: report_partition_seq → hash_slot
ALTER TABLE public.statistical_unit
    RENAME COLUMN report_partition_seq TO hash_slot;
ALTER TABLE public.statistical_unit_staging
    RENAME COLUMN report_partition_seq TO hash_slot;

ALTER INDEX public.idx_statistical_unit_report_partition_seq
    RENAME TO idx_statistical_unit_hash_slot;
-- statistical_unit_staging has no index on the L1-slot column
-- (only (unit_type, unit_id)). Nothing to rename on that side.

ALTER TRIGGER trg_set_report_partition_seq ON public.statistical_unit
    RENAME TO trg_set_hash_slot;
ALTER TRIGGER trg_set_report_partition_seq ON public.statistical_unit_staging
    RENAME TO trg_set_hash_slot;

-- Facet pipeline: partition_seq → hash_slot (per-slot semantics preserved)
ALTER TABLE public.statistical_unit_facet
    RENAME COLUMN partition_seq TO hash_slot;
ALTER TABLE public.statistical_unit_facet_staging
    RENAME COLUMN partition_seq TO hash_slot;
ALTER TABLE public.statistical_history_facet_partitions
    RENAME COLUMN partition_seq TO hash_slot;

ALTER INDEX public.idx_statistical_unit_facet_partition_seq
    RENAME TO idx_statistical_unit_facet_hash_slot;
ALTER INDEX public.idx_statistical_unit_facet_staging_partition_seq
    RENAME TO idx_statistical_unit_facet_staging_hash_slot;
ALTER INDEX public.statistical_unit_facet_stagin_partition_seq_valid_from_vali_key
    RENAME TO statistical_unit_facet_stagin_hash_slot_valid_from_vali_key;
ALTER INDEX public.idx_shf_partitions_seq
    RENAME TO idx_shf_partitions_hash_slot;
ALTER INDEX public.statistical_history_facet_par_partition_seq_resolution_year_key
    RENAME TO statistical_history_facet_par_hash_slot_resolution_year_key;

-- Dirty-queue table + column rename, plus pkey
ALTER TABLE public.statistical_unit_facet_dirty_partitions
    RENAME TO statistical_unit_facet_dirty_hash_slots;
ALTER TABLE public.statistical_unit_facet_dirty_hash_slots
    RENAME COLUMN partition_seq TO dirty_hash_slot;
ALTER INDEX public.statistical_unit_facet_dirty_partitions_pkey
    RENAME TO statistical_unit_facet_dirty_hash_slots_pkey;

-- Constraint renames to match renamed columns / tables (cosmetic but keeps schema tidy).
-- Block C drops only statistical_history (and its type), NOT
-- statistical_history_facet_partitions — so the NOT NULL constraint on the
-- renamed column survives and must be renamed here too.
ALTER TABLE public.statistical_unit_facet_staging
    RENAME CONSTRAINT statistical_unit_facet_staging_partition_seq_not_null
                   TO statistical_unit_facet_staging_hash_slot_not_null;
ALTER TABLE public.statistical_unit_facet_dirty_hash_slots
    RENAME CONSTRAINT statistical_unit_facet_dirty_partitions_partition_seq_not_null
                   TO statistical_unit_facet_dirty_hash_slots_dirty_hash_slot_not_null;
ALTER TABLE public.statistical_history_facet_partitions
    RENAME CONSTRAINT statistical_history_facet_partitions_partition_seq_not_null
                   TO statistical_history_facet_partitions_hash_slot_not_null;

-- Re-issue TRUNCATE grant after table rename (belt-and-braces; audit §4).
GRANT TRUNCATE ON TABLE public.statistical_unit_facet_dirty_hash_slots TO admin_user;

-- ============================================================
-- Block C — statistical_history: drop + rebuild TYPE and typed table
-- ============================================================
--
-- DROP CASCADE removes the TYPE's dependents (statistical_history table via OF,
-- statistical_history_def function which RETURNS SETOF statistical_history_type).
-- Both are rebuilt in this block (table, indexes, RLS, grants) and in Block F
-- (statistical_history_def). Derived data rebuilds automatically on the next
-- derive trigger tick after rc.42 boots.

DROP TABLE public.statistical_history CASCADE;
DROP TYPE  public.statistical_history_type CASCADE;

-- Recreate type; attr 24 changes from partition_seq integer → hash_partition int4range.
CREATE TYPE public.statistical_history_type AS (
    resolution                               public.history_resolution,
    year                                     integer,
    month                                    integer,
    unit_type                                public.statistical_unit_type,
    exists_count                             integer,
    exists_change                            integer,
    exists_added_count                       integer,
    exists_removed_count                     integer,
    countable_count                          integer,
    countable_change                         integer,
    countable_added_count                    integer,
    countable_removed_count                  integer,
    births                                   integer,
    deaths                                   integer,
    name_change_count                        integer,
    primary_activity_category_change_count   integer,
    secondary_activity_category_change_count integer,
    sector_change_count                      integer,
    legal_form_change_count                  integer,
    physical_region_change_count             integer,
    physical_country_change_count            integer,
    physical_address_change_count            integer,
    stats_summary                            jsonb,
    hash_partition                           int4range
);

CREATE TABLE public.statistical_history OF public.statistical_history_type;

-- 9 indexes from doc/db/table/public_statistical_history.md, with
-- partition_seq → hash_partition substituted in names and predicates.
CREATE INDEX idx_history_resolution
    ON public.statistical_history (resolution)
    WHERE hash_partition IS NULL;
CREATE INDEX idx_statistical_history_month
    ON public.statistical_history (month)
    WHERE hash_partition IS NULL;
CREATE INDEX idx_statistical_history_hash_partition
    ON public.statistical_history (hash_partition)
    WHERE hash_partition IS NOT NULL;
CREATE INDEX idx_statistical_history_stats_summary
    ON public.statistical_history USING gin (stats_summary jsonb_path_ops)
    WHERE hash_partition IS NULL;
CREATE INDEX idx_statistical_history_year
    ON public.statistical_history (year)
    WHERE hash_partition IS NULL;
CREATE UNIQUE INDEX statistical_history_month_key
    ON public.statistical_history (resolution, year, month, unit_type)
    WHERE resolution = 'year-month'::public.history_resolution AND hash_partition IS NULL;
CREATE UNIQUE INDEX statistical_history_partition_month_key
    ON public.statistical_history (hash_partition, resolution, year, month, unit_type)
    WHERE resolution = 'year-month'::public.history_resolution AND hash_partition IS NOT NULL;
CREATE UNIQUE INDEX statistical_history_partition_year_key
    ON public.statistical_history (hash_partition, resolution, year, unit_type)
    WHERE resolution = 'year'::public.history_resolution AND hash_partition IS NOT NULL;
CREATE UNIQUE INDEX statistical_history_year_key
    ON public.statistical_history (resolution, year, unit_type)
    WHERE resolution = 'year'::public.history_resolution AND hash_partition IS NULL;

-- 3 RLS policies (same gate semantics, column swapped).
ALTER TABLE public.statistical_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY statistical_history_admin_user_manage ON public.statistical_history
    TO admin_user
    USING (hash_partition IS NULL)
    WITH CHECK (true);
CREATE POLICY statistical_history_authenticated_read ON public.statistical_history
    FOR SELECT TO authenticated
    USING (hash_partition IS NULL);
CREATE POLICY statistical_history_regular_user_read ON public.statistical_history
    FOR SELECT TO regular_user
    USING (hash_partition IS NULL);

GRANT SELECT ON public.statistical_history TO authenticated, regular_user;
GRANT ALL    ON public.statistical_history TO admin_user;

-- ============================================================
-- Block D — Settings + auto-tune rename/rewrite
-- ============================================================

ALTER TABLE public.settings
    RENAME COLUMN report_partition_modulus TO partition_count_target;
ALTER TABLE public.settings
    ALTER COLUMN partition_count_target SET DEFAULT 256;

-- Reset existing rows to neutral default; adjust_partition_count_target
-- will retune on its next invocation based on current unit count.
UPDATE public.settings SET partition_count_target = 256;

ALTER FUNCTION public.get_report_partition_modulus() RENAME TO get_partition_count_target;

CREATE OR REPLACE FUNCTION public.get_partition_count_target()
RETURNS integer
LANGUAGE sql
STABLE PARALLEL SAFE
AS $get_partition_count_target$
    SELECT COALESCE((SELECT partition_count_target FROM public.settings LIMIT 1), 256);
$get_partition_count_target$;

ALTER PROCEDURE admin.adjust_report_partition_modulus() RENAME TO adjust_partition_count_target;

CREATE OR REPLACE PROCEDURE admin.adjust_partition_count_target()
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'admin', 'public', 'pg_temp'
AS $adjust_partition_count_target$
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
$adjust_partition_count_target$;

-- ============================================================
-- Block E — Rewrite the three derive spawners (fix #49 + renames)
-- ============================================================
--
-- The #49 fix lives here. Old bodies used `FOR v_range_start IN 0..(v_modulus-1) BY v_range_size LOOP`,
-- which skipped slots in [v_modulus, 255] when v_modulus < 256 — exactly the
-- bug that let enterprise id=3 (slot 168) and friends disappear from
-- statistical_history. New bodies iterate over the set of ranges actually
-- populated by statistical_unit rows, derived from `statistical_unit.hash_slot`
-- via integer division by v_hash_partition_size. By construction, every row
-- lands in exactly one range, and no range is iterated unless it contains
-- data.

-- -- worker.derive_statistical_history --------------------------------------
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_history$
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

    -- Bail to full rebuild if no history rows exist yet (fresh install, post-reset).
    IF NOT EXISTS (SELECT 1 FROM public.statistical_history WHERE hash_partition IS NOT NULL LIMIT 1) THEN
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
            -- Dirty branch: one singleton range per dirty slot.
            FOR i IN 1..COALESCE(array_length(v_dirty_hash_slots, 1), 0) LOOP
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_history_period',
                    p_payload => jsonb_build_object(
                        'command', 'derive_statistical_history_period',
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'hash_partition', int4range(v_dirty_hash_slots[i], v_dirty_hash_slots[i] + 1)::text
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
$derive_statistical_history$;

-- -- worker.derive_statistical_history_facet --------------------------------
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_history_facet$
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

    IF NOT EXISTS (SELECT 1 FROM public.statistical_history_facet_partitions LIMIT 1) THEN
        v_dirty_hash_slots := NULL;
    END IF;

    -- Snapshot dirty dims BEFORE children rewrite partitions.
    IF v_dirty_hash_slots IS NOT NULL THEN
        TRUNCATE public.statistical_history_facet_pre_dirty_dims;
        INSERT INTO public.statistical_history_facet_pre_dirty_dims
        SELECT DISTINCT s.resolution, s.year, s.month, s.unit_type,
               s.primary_activity_category_path, s.secondary_activity_category_path,
               s.sector_path, s.legal_form_id, s.physical_region_path,
               s.physical_country_id, s.unit_size_id, s.status_id
        FROM public.statistical_history_facet_partitions AS s
        WHERE s.hash_slot = ANY(v_dirty_hash_slots);
    ELSE
        TRUNCATE public.statistical_history_facet_pre_dirty_dims;
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
            FOR i IN 1..COALESCE(array_length(v_dirty_hash_slots, 1), 0) LOOP
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_history_facet_period',
                    p_payload => jsonb_build_object(
                        'command', 'derive_statistical_history_facet_period',
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'hash_partition', int4range(v_dirty_hash_slots[i], v_dirty_hash_slots[i] + 1)::text
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
$derive_statistical_history_facet$;

-- -- worker.derive_statistical_unit_facet -----------------------------------
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_unit_facet$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_task_id bigint;
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

    -- Bail to full rebuild if the staging table is empty (fresh install, post-reset).
    IF NOT EXISTS (SELECT 1 FROM public.statistical_unit_facet_staging LIMIT 1) THEN
        v_dirty_hash_slots := NULL;
    END IF;

    -- Snapshot dirty dims BEFORE children rewrite staging.
    IF v_dirty_hash_slots IS NOT NULL THEN
        TRUNCATE public.statistical_unit_facet_pre_dirty_dims;
        INSERT INTO public.statistical_unit_facet_pre_dirty_dims
        SELECT DISTINCT s.valid_from, s.valid_to, s.valid_until, s.unit_type,
               s.physical_region_path, s.primary_activity_category_path,
               s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id
        FROM public.statistical_unit_facet_staging AS s
        WHERE s.hash_slot = ANY(v_dirty_hash_slots);

        FOR i IN 1..COALESCE(array_length(v_dirty_hash_slots, 1), 0) LOOP
            PERFORM worker.spawn(
                p_command => 'derive_statistical_unit_facet_partition',
                p_payload => jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'hash_partition', int4range(v_dirty_hash_slots[i], v_dirty_hash_slots[i] + 1)::text
                ),
                p_parent_id => v_task_id
            );
            v_child_count := v_child_count + 1;
        END LOOP;
    ELSE
        TRUNCATE public.statistical_unit_facet_pre_dirty_dims;

        FOR v_hash_partition IN
            SELECT DISTINCT int4range(
                (su.hash_slot / v_hash_partition_size) * v_hash_partition_size,
                LEAST((su.hash_slot / v_hash_partition_size) * v_hash_partition_size + v_hash_partition_size, 16384)
            )
            FROM public.statistical_unit AS su
            WHERE su.used_for_counting
            ORDER BY 1
        LOOP
            PERFORM worker.spawn(
                p_command => 'derive_statistical_unit_facet_partition',
                p_payload => jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'hash_partition', v_hash_partition::text
                ),
                p_parent_id => v_task_id
            );
            v_child_count := v_child_count + 1;
        END LOOP;
    END IF;

    p_info := jsonb_build_object('child_count', v_child_count);
END;
$derive_statistical_unit_facet$;

-- ============================================================
-- Block F — Rewrite consumer fns + period handlers
-- ============================================================

-- -- public.statistical_history_def (signature changes: int4range param) -----
-- Note: old (history_resolution, int, int, int, int) was dropped by Block C's
-- DROP TYPE CASCADE. Create fresh.
CREATE FUNCTION public.statistical_history_def(
    p_resolution public.history_resolution,
    p_year integer,
    p_month integer,
    p_hash_partition int4range DEFAULT NULL
)
RETURNS SETOF public.statistical_history_type
LANGUAGE plpgsql
AS $statistical_history_def$
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
        WHERE lvc.valid_until > v_curr_stop
          AND COALESCE(lvc.birth_date, lvc.valid_from) <= v_curr_stop
          AND (lvc.death_date IS NULL OR lvc.death_date > v_curr_stop)
    ),
    stock_at_end_of_prev AS (
        SELECT * FROM latest_versions_prev lvp
        WHERE lvp.valid_until > v_prev_stop
          AND COALESCE(lvp.birth_date, lvp.valid_from) <= v_prev_stop
          AND (lvp.death_date IS NULL OR lvp.death_date > v_prev_stop)
    ),
    changed_units AS (
        SELECT
            COALESCE(c.unit_id, p.unit_id) AS unit_id,
            COALESCE(c.unit_type, p.unit_type) AS unit_type,
            c AS curr,
            p AS prev,
            lvc AS last_version_in_curr
        FROM stock_at_end_of_curr c
        FULL JOIN stock_at_end_of_prev p ON c.unit_id = p.unit_id AND c.unit_type = p.unit_type
        LEFT JOIN latest_versions_curr lvc ON lvc.unit_id = COALESCE(p.unit_id, c.unit_id) AND lvc.unit_type = COALESCE(p.unit_type, c.unit_type)
    ),
    stats_by_unit_type AS (
        SELECT
            lvc.unit_type,
            COALESCE(public.jsonb_stats_merge_agg(lvc.stats_summary), '{}'::jsonb) AS stats_summary
        FROM latest_versions_curr lvc
        WHERE lvc.used_for_counting
        GROUP BY lvc.unit_type
    ),
    demographics AS (
        SELECT
            p_resolution, p_year, p_month, unit_type,
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
        GROUP BY 1, 2, 3, 4
    )
    SELECT
        d.p_resolution AS resolution, d.p_year AS year, d.p_month AS month, d.unit_type,
        d.exists_count, d.exists_change, d.exists_added_count, d.exists_removed_count,
        d.countable_count, d.countable_change, d.countable_added_count, d.countable_removed_count,
        d.births, d.deaths,
        d.name_change_count, d.primary_activity_category_change_count, d.secondary_activity_category_change_count,
        d.sector_change_count, d.legal_form_change_count, d.physical_region_change_count,
        d.physical_country_change_count, d.physical_address_change_count,
        COALESCE(sbut.stats_summary, '{}'::jsonb) AS stats_summary,
        -- hash_partition stores the int4range the DELETE/INSERT pair uses.
        -- DELETE gates on `hash_partition = p_hash_partition`; INSERT writes
        -- the same range, so boundaries are self-consistent by construction.
        p_hash_partition AS hash_partition
    FROM demographics d
    LEFT JOIN stats_by_unit_type sbut ON sbut.unit_type = d.unit_type;
END;
$statistical_history_def$;

-- -- public.statistical_history_facet_def (param rename, same signature) -----
-- Parameter name changes (p_partition_seq → p_hash_slot) but arg types are
-- unchanged. PostgreSQL `CREATE OR REPLACE FUNCTION` CANNOT rename IN
-- parameters ("cannot change name of input parameter"), so we must DROP
-- first. statistical_history_facet_type is NOT dropped by Block C (only
-- statistical_history_type is), so the pre-rc.42 facet_def is still live
-- here and blocks CREATE OR REPLACE. Explicit DROP frees the slot.
--
-- Body is verbatim from
-- doc/db/function/public_statistical_history_facet_def(history_resolution, integer, integer, integer).md
-- with TWO substitutions:
--   p_partition_seq            → p_hash_slot
--   su.report_partition_seq    → su.hash_slot
DROP FUNCTION IF EXISTS public.statistical_history_facet_def(
    public.history_resolution, integer, integer, integer
);
CREATE OR REPLACE FUNCTION public.statistical_history_facet_def(
    p_resolution public.history_resolution,
    p_year integer,
    p_month integer,
    p_hash_slot integer DEFAULT NULL
)
RETURNS SETOF public.statistical_history_facet_type
LANGUAGE plpgsql
AS $statistical_history_facet_def$
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
          AND (p_hash_slot IS NULL OR su.hash_slot = p_hash_slot)
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
        WHERE lvc.valid_until > v_curr_stop
          AND COALESCE(lvc.birth_date, lvc.valid_from) <= v_curr_stop
          AND (lvc.death_date IS NULL OR lvc.death_date > v_curr_stop)
    ),
    stock_at_end_of_prev AS (
        SELECT * FROM latest_versions_prev lvp
        WHERE lvp.valid_until > v_prev_stop
          AND COALESCE(lvp.birth_date, lvp.valid_from) <= v_prev_stop
          AND (lvp.death_date IS NULL OR lvp.death_date > v_prev_stop)
    ),
    -- PERF: pre-aggregate stats with composite key for fast hash join.
    stats_by_facet AS (
        SELECT
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
        GROUP BY 1
    ),
    -- PERF: flatten columns instead of storing entire ROW types.
    changed_units AS (
        SELECT
            COALESCE(c.unit_id, p.unit_id) AS unit_id,
            COALESCE(c.unit_type, p.unit_type) AS unit_type,
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
        GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
    )
    SELECT
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
    LEFT JOIN stats_by_facet s ON s.facet_key = d.facet_key;
END;
$statistical_history_facet_def$;

-- -- worker.derive_statistical_history_period (payload key: hash_partition) -
-- Two-branch body: scoped (hash_partition present) vs root (key absent).
-- Root calculation remains; it's produced by worker.statistical_history_reduce
-- in normal operation but this procedure preserves the direct-call path.
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_period(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_history_period$
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
        DELETE FROM public.statistical_history
         WHERE resolution = v_resolution
           AND year = v_year
           AND month IS NOT DISTINCT FROM v_month
           AND hash_partition = v_hash_partition;

        INSERT INTO public.statistical_history
        SELECT h.*
        FROM public.statistical_history_def(v_resolution, v_year, v_month, v_hash_partition) AS h;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;
    ELSE
        DELETE FROM public.statistical_history
         WHERE resolution = v_resolution
           AND year = v_year
           AND month IS NOT DISTINCT FROM v_month
           AND hash_partition IS NULL;

        INSERT INTO public.statistical_history
        SELECT h.*
        FROM public.statistical_history_def(v_resolution, v_year, v_month) AS h;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;
    END IF;

    RAISE DEBUG 'Completed statistical_history for resolution=%, year=%, month=%, hash_partition=%',
                 v_resolution, v_year, v_month, v_hash_partition;

    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$derive_statistical_history_period$;

-- -- worker.derive_statistical_history_facet_period -------------------------
-- Fans the int4range out slot-by-slot (generate_series) and calls the
-- per-slot statistical_history_facet_def for each.
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet_period(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_history_facet_period$
DECLARE
    v_resolution public.history_resolution := (payload->>'resolution')::public.history_resolution;
    v_year integer := (payload->>'year')::integer;
    v_month integer := (payload->>'month')::integer;
    v_hash_partition int4range := (payload->>'hash_partition')::int4range;
    v_hash_slot_from integer := lower(v_hash_partition);
    v_hash_slot_to   integer := upper(v_hash_partition) - 1;  -- int4range upper is exclusive
    v_row_count bigint;
BEGIN
    DELETE FROM public.statistical_history_facet_partitions
     WHERE resolution = v_resolution
       AND year = v_year
       AND month IS NOT DISTINCT FROM v_month
       AND hash_slot BETWEEN v_hash_slot_from AND v_hash_slot_to;

    INSERT INTO public.statistical_history_facet_partitions
    SELECT hash_slot, h.*
    FROM generate_series(v_hash_slot_from, v_hash_slot_to) AS hash_slot
    CROSS JOIN LATERAL public.statistical_history_facet_def(v_resolution, v_year, v_month, hash_slot) AS h;

    GET DIAGNOSTICS v_row_count := ROW_COUNT;
    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$derive_statistical_history_facet_period$;

-- -- worker.derive_statistical_unit_facet_partition (payload: hash_partition) -
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet_partition(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_unit_facet_partition$
DECLARE
    v_hash_partition int4range := (payload->>'hash_partition')::int4range;
    -- Pre-compute explicit half-open bounds so the btree index on hash_slot is
    -- used. Range containment (<@) via a variable int4range is not planned as a
    -- btree scan at 2.2M rows; explicit bounds are. Mirrors the sibling
    -- derive_statistical_history_facet_period which passes scalar bounds.
    v_from  integer := lower(v_hash_partition);
    v_until integer := upper(v_hash_partition);
    v_row_count bigint;
BEGIN
    DELETE FROM public.statistical_unit_facet_staging
     WHERE hash_slot >= v_from AND hash_slot < v_until;

    INSERT INTO public.statistical_unit_facet_staging
    SELECT su.hash_slot,
           su.valid_from, su.valid_to, su.valid_until, su.unit_type,
           su.physical_region_path, su.primary_activity_category_path,
           su.sector_path, su.legal_form_id, su.physical_country_id, su.status_id,
           COUNT(*)::integer,
           public.jsonb_stats_merge_agg(su.stats_summary)
    FROM public.statistical_unit AS su
    WHERE su.used_for_counting
      AND su.hash_slot >= v_from AND su.hash_slot < v_until
    GROUP BY su.hash_slot, su.valid_from, su.valid_to, su.valid_until, su.unit_type,
             su.physical_region_path, su.primary_activity_category_path,
             su.sector_path, su.legal_form_id, su.physical_country_id, su.status_id;
    GET DIAGNOSTICS v_row_count := ROW_COUNT;
    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$derive_statistical_unit_facet_partition$;

-- ============================================================
-- Block G — Rehash stored L1 slots
-- ============================================================
--
-- On ET (19 units): sub-second. On NO rune (clean install, empty tables): no-op.
-- Triggers are BEFORE INSERT only, so UPDATE does not re-fire them; we
-- assign the new value directly.

UPDATE public.statistical_unit         SET hash_slot = public.hash_slot(unit_type, unit_id);
UPDATE public.statistical_unit_staging SET hash_slot = public.hash_slot(unit_type, unit_id);

-- ============================================================
-- Block H — MERGE POINT: paralegal #67 output
-- ============================================================
--
-- Mechanical rename transform for 4 non-spawner INSERT-site routines:
--   - public.reset (f)
--   - worker.derive_statistical_unit (f)
--   - worker.statistical_history_facet_reduce (p)
--   - worker.statistical_unit_facet_reduce (p)
-- Renames applied:
--   statistical_unit_facet_dirty_partitions → statistical_unit_facet_dirty_hash_slots
--   (partition_seq) → (dirty_hash_slot) in INSERTs against that table
--   report_partition_seq → hash_slot (on statistical_unit columns)
--   partition_seq → hash_slot (on *_facet{,_staging,_partitions} columns)
-- Paralegal writes to tmp/paralegal-rc42-block-h.sql; partner splices here.

-- Block H: mechanical rename for rc.42
-- Generated by tmp/rc42-run-block-h.py

-- public.reset
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
$function$;

-- worker.derive_statistical_unit
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
    -- Adaptive power group batching: target ~64 batches for large datasets
    v_pg_batch_size INT;
BEGIN
    v_is_full_refresh := (p_establishment_id_ranges IS NULL
                         AND p_legal_unit_id_ranges IS NULL
                         AND p_enterprise_id_ranges IS NULL
                         AND p_power_group_id_ranges IS NULL);

    IF v_is_full_refresh THEN
        FOR v_batch IN SELECT * FROM public.get_closed_group_batches(p_target_batch_size => 1000)
        LOOP
            v_enterprise_count := v_enterprise_count + COALESCE(array_length(v_batch.enterprise_ids, 1), 0);
            v_legal_unit_count := v_legal_unit_count + COALESCE(array_length(v_batch.legal_unit_ids, 1), 0);
            v_establishment_count := v_establishment_count + COALESCE(array_length(v_batch.establishment_ids, 1), 0);

            PERFORM worker.spawn(
                p_command => 'statistical_unit_refresh_batch',
                p_payload => jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch.batch_seq,
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
            -- Adaptive batch size: target ~64 batches max, minimum 1 per batch
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

        -- ORPHAN CLEANUP
        IF COALESCE(array_length(v_enterprise_ids, 1), 0) > 0 THEN
            v_orphan_enterprise_ids := ARRAY(SELECT id FROM unnest(v_enterprise_ids) AS id EXCEPT SELECT e.id FROM public.enterprise AS e WHERE e.id = ANY(v_enterprise_ids));
            IF COALESCE(array_length(v_orphan_enterprise_ids, 1), 0) > 0 THEN
                DELETE FROM public.timepoints WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timeline_enterprise WHERE enterprise_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
            END IF;
        END IF;
        IF COALESCE(array_length(v_legal_unit_ids, 1), 0) > 0 THEN
            v_orphan_legal_unit_ids := ARRAY(SELECT id FROM unnest(v_legal_unit_ids) AS id EXCEPT SELECT lu.id FROM public.legal_unit AS lu WHERE lu.id = ANY(v_legal_unit_ids));
            IF COALESCE(array_length(v_orphan_legal_unit_ids, 1), 0) > 0 THEN
                DELETE FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timeline_legal_unit WHERE legal_unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
            END IF;
        END IF;
        IF COALESCE(array_length(v_establishment_ids, 1), 0) > 0 THEN
            v_orphan_establishment_ids := ARRAY(SELECT id FROM unnest(v_establishment_ids) AS id EXCEPT SELECT es.id FROM public.establishment AS es WHERE es.id = ANY(v_establishment_ids));
            IF COALESCE(array_length(v_orphan_establishment_ids, 1), 0) > 0 THEN
                DELETE FROM public.timepoints WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timeline_establishment WHERE establishment_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
            END IF;
        END IF;
        IF COALESCE(array_length(v_power_group_ids, 1), 0) > 0 THEN
            v_orphan_power_group_ids := ARRAY(SELECT id FROM unnest(v_power_group_ids) AS id EXCEPT SELECT pg.id FROM public.power_group AS pg WHERE pg.id = ANY(v_power_group_ids));
            IF COALESCE(array_length(v_orphan_power_group_ids, 1), 0) > 0 THEN
                DELETE FROM public.timepoints WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.timeline_power_group WHERE power_group_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
            END IF;
        END IF;

        IF p_establishment_id_ranges IS NOT NULL
           OR p_legal_unit_id_ranges IS NOT NULL
           OR p_enterprise_id_ranges IS NOT NULL THEN
            IF to_regclass('pg_temp._batches') IS NOT NULL THEN DROP TABLE _batches; END IF;
            CREATE TEMP TABLE _batches ON COMMIT DROP AS
            SELECT * FROM public.get_closed_group_batches(
                p_target_batch_size => 1000,
                p_establishment_id_ranges => NULLIF(p_establishment_id_ranges, '{}'::int4multirange),
                p_legal_unit_id_ranges => NULLIF(p_legal_unit_id_ranges, '{}'::int4multirange),
                p_enterprise_id_ranges => NULLIF(p_enterprise_id_ranges, '{}'::int4multirange)
            );
            -- hash_slot() is IMMUTABLE with fixed space 16384; no settings lookup needed
            INSERT INTO public.statistical_unit_facet_dirty_hash_slots (dirty_hash_slot)
            SELECT DISTINCT public.hash_slot(t.unit_type, t.unit_id)
            FROM (
                SELECT 'enterprise'::text AS unit_type, unnest(b.enterprise_ids) AS unit_id FROM _batches AS b
                UNION ALL SELECT 'legal_unit', unnest(b.legal_unit_ids) FROM _batches AS b
                UNION ALL SELECT 'establishment', unnest(b.establishment_ids) FROM _batches AS b
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
                    FROM (SELECT unnest(establishment_ids) AS id FROM _batches) AS t);
                v_all_batch_lu_ranges := (SELECT range_agg(int4range(id, id, '[]'))
                    FROM (SELECT unnest(legal_unit_ids) AS id FROM _batches) AS t);
                v_all_batch_en_ranges := (SELECT range_agg(int4range(id, id, '[]'))
                    FROM (SELECT unnest(enterprise_ids) AS id FROM _batches) AS t);

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

            FOR v_batch IN SELECT * FROM _batches LOOP
                PERFORM worker.spawn(
                    p_command => 'statistical_unit_refresh_batch',
                    p_payload => jsonb_build_object(
                        'command', 'statistical_unit_refresh_batch',
                        'batch_seq', v_batch.batch_seq,
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
            -- hash_slot() is IMMUTABLE with fixed space 16384; no settings lookup needed
            INSERT INTO public.statistical_unit_facet_dirty_hash_slots (dirty_hash_slot)
            SELECT DISTINCT public.hash_slot('power_group', pg_id)
            FROM unnest(v_power_group_ids) AS pg_id
            ON CONFLICT DO NOTHING;

            -- Adaptive batch size: target ~64 batches max
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

    PERFORM public.activity_category_used_derive();
    PERFORM public.region_used_derive();
    PERFORM public.sector_used_derive();
    PERFORM public.data_source_used_derive();
    PERFORM public.legal_form_used_derive();
    PERFORM public.country_used_derive();

    -- Info Principle: report effective counts (post-propagation), not affected counts (raw change-log)
    RETURN jsonb_build_object(
        'effective_establishment_count', v_establishment_count,
        'effective_legal_unit_count', v_legal_unit_count,
        'effective_enterprise_count', v_enterprise_count,
        'effective_power_group_count', v_power_group_count,
        'batch_count', v_batch_count
    );
END;
$function$;

-- worker.statistical_history_facet_reduce
CREATE OR REPLACE PROCEDURE worker.statistical_history_facet_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_dirty_hash_slots int[];
    v_row_count bigint;
    v_delete_count bigint;
BEGIN
    -- Read dirty partitions before truncating them at the end.
    SELECT array_agg(dp.dirty_hash_slot)
      INTO v_dirty_hash_slots
      FROM public.statistical_unit_facet_dirty_hash_slots AS dp;

    IF v_dirty_hash_slots IS NULL OR array_length(v_dirty_hash_slots, 1) IS NULL THEN
        ---------------------------------------------------------------
        -- Full refresh: drop indexes, TRUNCATE + INSERT, rebuild indexes
        ---------------------------------------------------------------
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_year;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_month;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_unit_type;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_primary_activity_category_path;
        DROP INDEX IF EXISTS public.idx_gist_statistical_history_facet_primary_activity_category_pa;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_secondary_activity_category_path;
        DROP INDEX IF EXISTS public.idx_gist_statistical_history_facet_secondary_activity_category_;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_sector_path;
        DROP INDEX IF EXISTS public.idx_gist_statistical_history_facet_sector_path;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_legal_form_id;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_physical_region_path;
        DROP INDEX IF EXISTS public.idx_gist_statistical_history_facet_physical_region_path;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_physical_country_id;
        DROP INDEX IF EXISTS public.idx_statistical_history_facet_stats_summary;
        DROP INDEX IF EXISTS public.statistical_history_facet_month_key;
        DROP INDEX IF EXISTS public.statistical_history_facet_year_key;

        TRUNCATE public.statistical_history_facet;

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
            legal_form_change_count, physical_region_change_count,
            physical_country_change_count, physical_address_change_count,
            unit_size_change_count, status_change_count,
            stats_summary
        )
        SELECT
            resolution, year, month, unit_type,
            primary_activity_category_path, secondary_activity_category_path,
            sector_path, legal_form_id, physical_region_path,
            physical_country_id, unit_size_id, status_id,
            SUM(exists_count)::integer, SUM(exists_change)::integer,
            SUM(exists_added_count)::integer, SUM(exists_removed_count)::integer,
            SUM(countable_count)::integer, SUM(countable_change)::integer,
            SUM(countable_added_count)::integer, SUM(countable_removed_count)::integer,
            SUM(births)::integer, SUM(deaths)::integer,
            SUM(name_change_count)::integer, SUM(primary_activity_category_change_count)::integer,
            SUM(secondary_activity_category_change_count)::integer, SUM(sector_change_count)::integer,
            SUM(legal_form_change_count)::integer, SUM(physical_region_change_count)::integer,
            SUM(physical_country_change_count)::integer, SUM(physical_address_change_count)::integer,
            SUM(unit_size_change_count)::integer, SUM(status_change_count)::integer,
            jsonb_stats_merge_agg(stats_summary)
        FROM public.statistical_history_facet_partitions
        GROUP BY resolution, year, month, unit_type,
                 primary_activity_category_path, secondary_activity_category_path,
                 sector_path, legal_form_id, physical_region_path,
                 physical_country_id, unit_size_id, status_id;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;

        CREATE UNIQUE INDEX statistical_history_facet_month_key
            ON public.statistical_history_facet (resolution, year, month, unit_type,
                primary_activity_category_path, secondary_activity_category_path,
                sector_path, legal_form_id, physical_region_path, physical_country_id)
            WHERE resolution = 'year-month'::public.history_resolution;
        CREATE UNIQUE INDEX statistical_history_facet_year_key
            ON public.statistical_history_facet (year, month, unit_type,
                primary_activity_category_path, secondary_activity_category_path,
                sector_path, legal_form_id, physical_region_path, physical_country_id)
            WHERE resolution = 'year'::public.history_resolution;
        CREATE INDEX idx_statistical_history_facet_year ON public.statistical_history_facet (year);
        CREATE INDEX idx_statistical_history_facet_month ON public.statistical_history_facet (month);
        CREATE INDEX idx_statistical_history_facet_unit_type ON public.statistical_history_facet (unit_type);
        CREATE INDEX idx_statistical_history_facet_primary_activity_category_path ON public.statistical_history_facet (primary_activity_category_path);
        CREATE INDEX idx_gist_statistical_history_facet_primary_activity_category_pa ON public.statistical_history_facet USING GIST (primary_activity_category_path);
        CREATE INDEX idx_statistical_history_facet_secondary_activity_category_path ON public.statistical_history_facet (secondary_activity_category_path);
        CREATE INDEX idx_gist_statistical_history_facet_secondary_activity_category_ ON public.statistical_history_facet USING GIST (secondary_activity_category_path);
        CREATE INDEX idx_statistical_history_facet_sector_path ON public.statistical_history_facet (sector_path);
        CREATE INDEX idx_gist_statistical_history_facet_sector_path ON public.statistical_history_facet USING GIST (sector_path);
        CREATE INDEX idx_statistical_history_facet_legal_form_id ON public.statistical_history_facet (legal_form_id);
        CREATE INDEX idx_statistical_history_facet_physical_region_path ON public.statistical_history_facet (physical_region_path);
        CREATE INDEX idx_gist_statistical_history_facet_physical_region_path ON public.statistical_history_facet USING GIST (physical_region_path);
        CREATE INDEX idx_statistical_history_facet_physical_country_id ON public.statistical_history_facet (physical_country_id);
        CREATE INDEX idx_statistical_history_facet_stats_summary ON public.statistical_history_facet USING GIN (stats_summary jsonb_path_ops);

        p_info := jsonb_build_object('mode', 'full', 'rows_reduced', v_row_count);
    ELSIF array_length(v_dirty_hash_slots, 1) <= 128 THEN
        ---------------------------------------------------------------
        -- Path B: Scoped MERGE (few dirty partitions).
        -- Uses row-value IN with ::text cast for Hash Join.
        ---------------------------------------------------------------

        -- Scoped aggregate using row-value IN (::text cast = Hash Join)
        IF to_regclass('pg_temp._scoped_history_agg') IS NOT NULL THEN
            DROP TABLE _scoped_history_agg;
        END IF;
        CREATE TEMP TABLE _scoped_history_agg ON COMMIT DROP AS
        SELECT
            s.resolution, s.year, s.month, s.unit_type,
            s.primary_activity_category_path, s.secondary_activity_category_path,
            s.sector_path, s.legal_form_id, s.physical_region_path,
            s.physical_country_id, s.unit_size_id, s.status_id,
            SUM(s.exists_count)::integer AS exists_count,
            SUM(s.exists_change)::integer AS exists_change,
            SUM(s.exists_added_count)::integer AS exists_added_count,
            SUM(s.exists_removed_count)::integer AS exists_removed_count,
            SUM(s.countable_count)::integer AS countable_count,
            SUM(s.countable_change)::integer AS countable_change,
            SUM(s.countable_added_count)::integer AS countable_added_count,
            SUM(s.countable_removed_count)::integer AS countable_removed_count,
            SUM(s.births)::integer AS births,
            SUM(s.deaths)::integer AS deaths,
            SUM(s.name_change_count)::integer AS name_change_count,
            SUM(s.primary_activity_category_change_count)::integer AS primary_activity_category_change_count,
            SUM(s.secondary_activity_category_change_count)::integer AS secondary_activity_category_change_count,
            SUM(s.sector_change_count)::integer AS sector_change_count,
            SUM(s.legal_form_change_count)::integer AS legal_form_change_count,
            SUM(s.physical_region_change_count)::integer AS physical_region_change_count,
            SUM(s.physical_country_change_count)::integer AS physical_country_change_count,
            SUM(s.physical_address_change_count)::integer AS physical_address_change_count,
            SUM(s.unit_size_change_count)::integer AS unit_size_change_count,
            SUM(s.status_change_count)::integer AS status_change_count,
            jsonb_stats_merge_agg(s.stats_summary) AS stats_summary
        FROM public.statistical_history_facet_partitions AS s
        WHERE (s.resolution::text, s.year, COALESCE(s.month, -1), s.unit_type::text,
               COALESCE(s.primary_activity_category_path::text, ''),
               COALESCE(s.secondary_activity_category_path::text, ''),
               COALESCE(s.sector_path::text, ''),
               COALESCE(s.legal_form_id, -1),
               COALESCE(s.physical_region_path::text, ''),
               COALESCE(s.physical_country_id, -1),
               COALESCE(s.unit_size_id, -1),
               COALESCE(s.status_id, -1))
            IN (
                SELECT d.resolution::text, d.year, COALESCE(d.month, -1), d.unit_type::text,
                       COALESCE(d.primary_activity_category_path::text, ''),
                       COALESCE(d.secondary_activity_category_path::text, ''),
                       COALESCE(d.sector_path::text, ''),
                       COALESCE(d.legal_form_id, -1),
                       COALESCE(d.physical_region_path::text, ''),
                       COALESCE(d.physical_country_id, -1),
                       COALESCE(d.unit_size_id, -1),
                       COALESCE(d.status_id, -1)
                FROM public.statistical_history_facet_partitions AS d
                WHERE d.hash_slot = ANY(v_dirty_hash_slots)
                UNION
                SELECT p.resolution::text, p.year, COALESCE(p.month, -1), p.unit_type::text,
                       COALESCE(p.primary_activity_category_path::text, ''),
                       COALESCE(p.secondary_activity_category_path::text, ''),
                       COALESCE(p.sector_path::text, ''),
                       COALESCE(p.legal_form_id, -1),
                       COALESCE(p.physical_region_path::text, ''),
                       COALESCE(p.physical_country_id, -1),
                       COALESCE(p.unit_size_id, -1),
                       COALESCE(p.status_id, -1)
                FROM public.statistical_history_facet_pre_dirty_dims AS p
            )
        GROUP BY s.resolution, s.year, s.month, s.unit_type,
                 s.primary_activity_category_path, s.secondary_activity_category_path,
                 s.sector_path, s.legal_form_id, s.physical_region_path,
                 s.physical_country_id, s.unit_size_id, s.status_id;

        -- Scoped MERGE
        MERGE INTO public.statistical_history_facet AS target
        USING _scoped_history_agg AS source
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
             OR target.exists_change <> source.exists_change
             OR target.exists_added_count <> source.exists_added_count
             OR target.exists_removed_count <> source.exists_removed_count
             OR target.countable_count <> source.countable_count
             OR target.countable_change <> source.countable_change
             OR target.countable_added_count <> source.countable_added_count
             OR target.countable_removed_count <> source.countable_removed_count
             OR target.births <> source.births
             OR target.deaths <> source.deaths
             OR target.name_change_count <> source.name_change_count
             OR target.primary_activity_category_change_count <> source.primary_activity_category_change_count
             OR target.secondary_activity_category_change_count <> source.secondary_activity_category_change_count
             OR target.sector_change_count <> source.sector_change_count
             OR target.legal_form_change_count <> source.legal_form_change_count
             OR target.physical_region_change_count <> source.physical_region_change_count
             OR target.physical_country_change_count <> source.physical_country_change_count
             OR target.physical_address_change_count <> source.physical_address_change_count
             OR target.unit_size_change_count <> source.unit_size_change_count
             OR target.status_change_count <> source.status_change_count
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
                source.stats_summary);
        GET DIAGNOSTICS v_row_count := ROW_COUNT;

        -- DELETE stale combos (in snapshot but not in scoped aggregate)
        DELETE FROM public.statistical_history_facet AS f
        WHERE (f.resolution::text, f.year, COALESCE(f.month, -1), f.unit_type::text,
               COALESCE(f.primary_activity_category_path::text, ''),
               COALESCE(f.secondary_activity_category_path::text, ''),
               COALESCE(f.sector_path::text, ''),
               COALESCE(f.legal_form_id, -1),
               COALESCE(f.physical_region_path::text, ''),
               COALESCE(f.physical_country_id, -1),
               COALESCE(f.unit_size_id, -1),
               COALESCE(f.status_id, -1))
            IN (
                SELECT p.resolution::text, p.year, COALESCE(p.month, -1), p.unit_type::text,
                       COALESCE(p.primary_activity_category_path::text, ''),
                       COALESCE(p.secondary_activity_category_path::text, ''),
                       COALESCE(p.sector_path::text, ''),
                       COALESCE(p.legal_form_id, -1),
                       COALESCE(p.physical_region_path::text, ''),
                       COALESCE(p.physical_country_id, -1),
                       COALESCE(p.unit_size_id, -1),
                       COALESCE(p.status_id, -1)
                FROM public.statistical_history_facet_pre_dirty_dims AS p
            )
            AND NOT EXISTS (
                SELECT 1 FROM _scoped_history_agg AS a
                WHERE a.resolution = f.resolution
                  AND a.year = f.year
                  AND COALESCE(a.month, -1) = COALESCE(f.month, -1)
                  AND a.unit_type = f.unit_type
                  AND COALESCE(a.primary_activity_category_path::text, '') = COALESCE(f.primary_activity_category_path::text, '')
                  AND COALESCE(a.secondary_activity_category_path::text, '') = COALESCE(f.secondary_activity_category_path::text, '')
                  AND COALESCE(a.sector_path::text, '') = COALESCE(f.sector_path::text, '')
                  AND COALESCE(a.legal_form_id, -1) = COALESCE(f.legal_form_id, -1)
                  AND COALESCE(a.physical_region_path::text, '') = COALESCE(f.physical_region_path::text, '')
                  AND COALESCE(a.physical_country_id, -1) = COALESCE(f.physical_country_id, -1)
                  AND COALESCE(a.unit_size_id, -1) = COALESCE(f.unit_size_id, -1)
                  AND COALESCE(a.status_id, -1) = COALESCE(f.status_id, -1)
            );
        GET DIAGNOSTICS v_delete_count := ROW_COUNT;

        p_info := jsonb_build_object(
            'mode', 'scoped',
            'dirty_hash_slots', to_jsonb(v_dirty_hash_slots),
            'rows_merged', v_row_count,
            'rows_deleted', v_delete_count);
    ELSE
        ---------------------------------------------------------------
        -- Path C: Full MERGE (many dirty partitions > 128).
        -- Skip index drop/rebuild since MERGE preserves indexes.
        ---------------------------------------------------------------
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
            'mode', 'incremental',
            'dirty_hash_slots', to_jsonb(v_dirty_hash_slots),
            'rows_merged', v_row_count);
    END IF;

    -- Clean up dirty partitions at the very end, after all consumers have read them
    TRUNCATE public.statistical_unit_facet_dirty_hash_slots;

    PERFORM pg_notify('worker_status',
        json_build_object('type', 'is_deriving_reports', 'status', false)::text);
END;
$procedure$;

-- worker.statistical_unit_facet_reduce
CREATE OR REPLACE PROCEDURE worker.statistical_unit_facet_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_dirty_hash_slots int[];
    v_row_count bigint;
    v_delete_count bigint;
BEGIN
    -- Read dirty partitions BEFORE anything else, because
    -- statistical_history_facet_reduce (which runs later) truncates them.
    SELECT array_agg(dp.dirty_hash_slot)
      INTO v_dirty_hash_slots
      FROM public.statistical_unit_facet_dirty_hash_slots AS dp;

    IF v_dirty_hash_slots IS NULL OR array_length(v_dirty_hash_slots, 1) IS NULL THEN
        ---------------------------------------------------------------
        -- Full refresh: TRUNCATE + INSERT (original path, unchanged)
        ---------------------------------------------------------------
        TRUNCATE public.statistical_unit_facet;

        INSERT INTO public.statistical_unit_facet
            (valid_from, valid_to, valid_until, unit_type,
             physical_region_path, primary_activity_category_path,
             sector_path, legal_form_id, physical_country_id, status_id,
             count, stats_summary)
        SELECT s.valid_from, s.valid_to, s.valid_until, s.unit_type,
               s.physical_region_path, s.primary_activity_category_path,
               s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id,
               SUM(s.count)::BIGINT,
               jsonb_stats_merge_agg(s.stats_summary)
          FROM public.statistical_unit_facet_staging AS s
         GROUP BY s.valid_from, s.valid_to, s.valid_until, s.unit_type,
                  s.physical_region_path, s.primary_activity_category_path,
                  s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;

        p_info := jsonb_build_object('mode', 'full', 'rows_reduced', v_row_count);
    ELSIF array_length(v_dirty_hash_slots, 1) <= 128 THEN
        ---------------------------------------------------------------
        -- Path B: Scoped MERGE (few dirty partitions).
        -- Uses row-value IN with ::text cast for Hash Join (3.8s verified).
        -- Only re-aggregates dim combos from dirty partitions + snapshot.
        ---------------------------------------------------------------

        -- Scoped aggregate using row-value IN (::text cast = Hash Join)
        IF to_regclass('pg_temp._scoped_agg') IS NOT NULL THEN
            DROP TABLE _scoped_agg;
        END IF;
        CREATE TEMP TABLE _scoped_agg ON COMMIT DROP AS
        SELECT s.valid_from, s.valid_to, s.valid_until, s.unit_type,
               s.physical_region_path, s.primary_activity_category_path,
               s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id,
               SUM(s.count)::BIGINT AS count,
               jsonb_stats_merge_agg(s.stats_summary) AS stats_summary
        FROM public.statistical_unit_facet_staging AS s
        WHERE (s.valid_from, s.valid_to,
               COALESCE(s.valid_until, 'infinity'::date), s.unit_type,
               COALESCE(s.physical_region_path::text, ''),
               COALESCE(s.primary_activity_category_path::text, ''),
               COALESCE(s.sector_path::text, ''),
               COALESCE(s.legal_form_id, -1),
               COALESCE(s.physical_country_id, -1),
               COALESCE(s.status_id, -1))
            IN (
                -- Current staging dims for dirty partitions (new/changed)
                SELECT d.valid_from, d.valid_to,
                       COALESCE(d.valid_until, 'infinity'::date), d.unit_type,
                       COALESCE(d.physical_region_path::text, ''),
                       COALESCE(d.primary_activity_category_path::text, ''),
                       COALESCE(d.sector_path::text, ''),
                       COALESCE(d.legal_form_id, -1),
                       COALESCE(d.physical_country_id, -1),
                       COALESCE(d.status_id, -1)
                FROM public.statistical_unit_facet_staging AS d
                WHERE d.hash_slot = ANY(v_dirty_hash_slots)
                UNION
                -- Pre-dirty snapshot (disappeared combos)
                SELECT p.valid_from, p.valid_to,
                       COALESCE(p.valid_until, 'infinity'::date), p.unit_type,
                       COALESCE(p.physical_region_path::text, ''),
                       COALESCE(p.primary_activity_category_path::text, ''),
                       COALESCE(p.sector_path::text, ''),
                       COALESCE(p.legal_form_id, -1),
                       COALESCE(p.physical_country_id, -1),
                       COALESCE(p.status_id, -1)
                FROM public.statistical_unit_facet_pre_dirty_dims AS p
            )
        GROUP BY s.valid_from, s.valid_to, s.valid_until, s.unit_type,
                 s.physical_region_path, s.primary_activity_category_path,
                 s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id;

        -- Scoped MERGE into final table
        MERGE INTO public.statistical_unit_facet AS target
        USING _scoped_agg AS source
           ON target.valid_from = source.valid_from
          AND target.valid_to = source.valid_to
          AND COALESCE(target.valid_until, 'infinity'::date) = COALESCE(source.valid_until, 'infinity'::date)
          AND target.unit_type = source.unit_type
          AND COALESCE(target.physical_region_path::text, '') = COALESCE(source.physical_region_path::text, '')
          AND COALESCE(target.primary_activity_category_path::text, '') = COALESCE(source.primary_activity_category_path::text, '')
          AND COALESCE(target.sector_path::text, '') = COALESCE(source.sector_path::text, '')
          AND COALESCE(target.legal_form_id, -1) = COALESCE(source.legal_form_id, -1)
          AND COALESCE(target.physical_country_id, -1) = COALESCE(source.physical_country_id, -1)
          AND COALESCE(target.status_id, -1) = COALESCE(source.status_id, -1)
        WHEN MATCHED AND (target.count <> source.count
                          OR target.stats_summary IS DISTINCT FROM source.stats_summary)
            THEN UPDATE SET count = source.count,
                            stats_summary = source.stats_summary
        WHEN NOT MATCHED BY TARGET
            THEN INSERT (valid_from, valid_to, valid_until, unit_type,
                         physical_region_path, primary_activity_category_path,
                         sector_path, legal_form_id, physical_country_id, status_id,
                         count, stats_summary)
                 VALUES (source.valid_from, source.valid_to, source.valid_until, source.unit_type,
                         source.physical_region_path, source.primary_activity_category_path,
                         source.sector_path, source.legal_form_id, source.physical_country_id, source.status_id,
                         source.count, source.stats_summary);
        GET DIAGNOSTICS v_row_count := ROW_COUNT;

        -- DELETE stale combos (in snapshot but not in scoped aggregate)
        DELETE FROM public.statistical_unit_facet AS f
        WHERE (f.valid_from, f.valid_to,
               COALESCE(f.valid_until, 'infinity'::date), f.unit_type,
               COALESCE(f.physical_region_path::text, ''),
               COALESCE(f.primary_activity_category_path::text, ''),
               COALESCE(f.sector_path::text, ''),
               COALESCE(f.legal_form_id, -1),
               COALESCE(f.physical_country_id, -1),
               COALESCE(f.status_id, -1))
            IN (
                SELECT p.valid_from, p.valid_to,
                       COALESCE(p.valid_until, 'infinity'::date), p.unit_type,
                       COALESCE(p.physical_region_path::text, ''),
                       COALESCE(p.primary_activity_category_path::text, ''),
                       COALESCE(p.sector_path::text, ''),
                       COALESCE(p.legal_form_id, -1),
                       COALESCE(p.physical_country_id, -1),
                       COALESCE(p.status_id, -1)
                FROM public.statistical_unit_facet_pre_dirty_dims AS p
            )
            AND NOT EXISTS (
                SELECT 1 FROM _scoped_agg AS a
                WHERE a.valid_from = f.valid_from
                  AND a.valid_to = f.valid_to
                  AND COALESCE(a.valid_until, 'infinity'::date) = COALESCE(f.valid_until, 'infinity'::date)
                  AND a.unit_type = f.unit_type
                  AND COALESCE(a.physical_region_path::text, '') = COALESCE(f.physical_region_path::text, '')
                  AND COALESCE(a.primary_activity_category_path::text, '') = COALESCE(f.primary_activity_category_path::text, '')
                  AND COALESCE(a.sector_path::text, '') = COALESCE(f.sector_path::text, '')
                  AND COALESCE(a.legal_form_id, -1) = COALESCE(f.legal_form_id, -1)
                  AND COALESCE(a.physical_country_id, -1) = COALESCE(f.physical_country_id, -1)
                  AND COALESCE(a.status_id, -1) = COALESCE(f.status_id, -1)
            );
        GET DIAGNOSTICS v_delete_count := ROW_COUNT;

        p_info := jsonb_build_object(
            'mode', 'scoped',
            'dirty_hash_slots', to_jsonb(v_dirty_hash_slots),
            'rows_merged', v_row_count,
            'rows_deleted', v_delete_count);
    ELSE
        ---------------------------------------------------------------
        -- Path C: Full MERGE (many dirty partitions > 128).
        -- Full aggregate is faster than scoped when most partitions dirty.
        ---------------------------------------------------------------
        MERGE INTO public.statistical_unit_facet AS target
        USING (
            SELECT s.valid_from, s.valid_to, s.valid_until, s.unit_type,
                   s.physical_region_path, s.primary_activity_category_path,
                   s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id,
                   SUM(s.count)::BIGINT AS count,
                   jsonb_stats_merge_agg(s.stats_summary) AS stats_summary
              FROM public.statistical_unit_facet_staging AS s
             GROUP BY s.valid_from, s.valid_to, s.valid_until, s.unit_type,
                      s.physical_region_path, s.primary_activity_category_path,
                      s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id
        ) AS source
           ON target.valid_from = source.valid_from
          AND target.valid_to = source.valid_to
          AND COALESCE(target.valid_until, 'infinity'::date) = COALESCE(source.valid_until, 'infinity'::date)
          AND target.unit_type = source.unit_type
          AND COALESCE(target.physical_region_path::text, '') = COALESCE(source.physical_region_path::text, '')
          AND COALESCE(target.primary_activity_category_path::text, '') = COALESCE(source.primary_activity_category_path::text, '')
          AND COALESCE(target.sector_path::text, '') = COALESCE(source.sector_path::text, '')
          AND COALESCE(target.legal_form_id, -1) = COALESCE(source.legal_form_id, -1)
          AND COALESCE(target.physical_country_id, -1) = COALESCE(source.physical_country_id, -1)
          AND COALESCE(target.status_id, -1) = COALESCE(source.status_id, -1)
        WHEN MATCHED AND (target.count <> source.count
                          OR target.stats_summary IS DISTINCT FROM source.stats_summary)
            THEN UPDATE SET count = source.count,
                            stats_summary = source.stats_summary
        WHEN NOT MATCHED BY TARGET
            THEN INSERT (valid_from, valid_to, valid_until, unit_type,
                         physical_region_path, primary_activity_category_path,
                         sector_path, legal_form_id, physical_country_id, status_id,
                         count, stats_summary)
                 VALUES (source.valid_from, source.valid_to, source.valid_until, source.unit_type,
                         source.physical_region_path, source.primary_activity_category_path,
                         source.sector_path, source.legal_form_id, source.physical_country_id, source.status_id,
                         source.count, source.stats_summary)
        WHEN NOT MATCHED BY SOURCE THEN DELETE;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;

        p_info := jsonb_build_object(
            'mode', 'incremental',
            'dirty_hash_slots', to_jsonb(v_dirty_hash_slots),
            'rows_merged', v_row_count);
    END IF;
END;
$procedure$;

-- ============================================================
-- Block H2 — Additional rename updates (4 routines not in #67 scope)
-- ============================================================
-- Paralegal #67's scope was procs INSERTing into statistical_unit_facet_dirty_partitions.
-- These four reference renamed columns or call renamed routines but do NOT
-- write to that dirty table, so they were outside that scope. Without these
-- updates, runtime fails as soon as a worker executes any of them after
-- Block B's column rename lands.
--
--   worker.statistical_history_reduce                  — partition_seq → hash_partition
--   import.get_statistical_unit_data_partial           — public.report_partition_seq() → public.hash_slot()
--   public.relevant_statistical_units                  — report_partition_seq → hash_slot
--   worker.statistical_unit_flush_staging              — CALL admin.adjust_report_partition_modulus() → adjust_partition_count_target()

-- -- worker.statistical_history_reduce --------------------------------------
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
$procedure$;

-- -- worker.statistical_unit_flush_staging ----------------------------------
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

-- -- public.relevant_statistical_units -------------------------------------
CREATE OR REPLACE FUNCTION public.relevant_statistical_units(unit_type statistical_unit_type, unit_id integer, valid_on date DEFAULT CURRENT_DATE)
 RETURNS SETOF statistical_unit
 LANGUAGE sql
 STABLE
AS $function$
    -- Step 1: Find the enterprise row directly via temporal PK index
    WITH root_unit AS (
        SELECT su.unit_type, su.unit_id,
               su.related_legal_unit_ids,
               su.related_establishment_ids,
               su.external_idents
        FROM public.statistical_unit AS su
        WHERE su.unit_type = 'enterprise'
          AND su.unit_id = public.statistical_unit_enterprise_id($1, $2, $3)
          AND su.valid_from <= $3 AND $3 < su.valid_until
    -- Step 2: Collect all relevant (unit_type, unit_id) pairs from arrays
    ), relevant_ids AS (
        SELECT 'enterprise'::statistical_unit_type AS unit_type, ru.unit_id FROM root_unit AS ru
        UNION ALL
        SELECT 'legal_unit'::statistical_unit_type, unnest(ru.related_legal_unit_ids) FROM root_unit AS ru
        UNION ALL
        SELECT 'establishment'::statistical_unit_type, unnest(ru.related_establishment_ids) FROM root_unit AS ru
    -- Step 3: Single join back to get full rows, ordered by external ident priority
    ), full_units AS (
        SELECT su.*
            , first_external.ident AS first_external_ident
        FROM relevant_ids AS ri
        JOIN public.statistical_unit AS su
          ON su.unit_type = ri.unit_type
         AND su.unit_id = ri.unit_id
         AND su.valid_from <= $3 AND $3 < su.valid_until
        LEFT JOIN LATERAL (
            SELECT eit.code, (su.external_idents->>eit.code)::text AS ident
            FROM public.external_ident_type AS eit
            ORDER BY eit.priority
            LIMIT 1
        ) first_external ON true
        ORDER BY su.unit_type, first_external_ident NULLS LAST, su.unit_id
    )
    SELECT unit_type
         , unit_id
         , valid_from
         , valid_to
         , valid_until
         , external_idents
         , name
         , birth_date
         , death_date
         , search
         , primary_activity_category_id
         , primary_activity_category_path
         , primary_activity_category_code
         , secondary_activity_category_id
         , secondary_activity_category_path
         , secondary_activity_category_code
         , activity_category_paths
         , sector_id
         , sector_path
         , sector_code
         , sector_name
         , data_source_ids
         , data_source_codes
         , legal_form_id
         , legal_form_code
         , legal_form_name
         --
         , physical_address_part1
         , physical_address_part2
         , physical_address_part3
         , physical_postcode
         , physical_postplace
         , physical_region_id
         , physical_region_path
         , physical_region_code
         , physical_country_id
         , physical_country_iso_2
         , physical_latitude
         , physical_longitude
         , physical_altitude
         --
         , domestic
         --
         , postal_address_part1
         , postal_address_part2
         , postal_address_part3
         , postal_postcode
         , postal_postplace
         , postal_region_id
         , postal_region_path
         , postal_region_code
         , postal_country_id
         , postal_country_iso_2
         , postal_latitude
         , postal_longitude
         , postal_altitude
         --
         , web_address
         , email_address
         , phone_number
         , landline
         , mobile_number
         , fax_number
         --
         , unit_size_id
         , unit_size_code
         --
         , status_id
         , status_code
         , used_for_counting
         --
         , last_edit_comment
         , last_edit_by_user_id
         , last_edit_at
         --
         , has_legal_unit
         , related_establishment_ids
         , excluded_establishment_ids
         , included_establishment_ids
         , related_legal_unit_ids
         , excluded_legal_unit_ids
         , included_legal_unit_ids
         , related_enterprise_ids
         , excluded_enterprise_ids
         , included_enterprise_ids
         , stats
         , stats_summary
         , included_establishment_count
         , included_legal_unit_count
         , included_enterprise_count
         , tag_paths
         , daterange(valid_from, valid_until) AS valid_range
         , hash_slot
    FROM full_units;
$function$;

-- -- import.get_statistical_unit_data_partial -------------------------------
CREATE OR REPLACE FUNCTION import.get_statistical_unit_data_partial(p_unit_type statistical_unit_type, p_id_ranges int4multirange)
 RETURNS SETOF statistical_unit
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_ids INT[] := public.int4multirange_to_array(p_id_ranges);
BEGIN
    IF p_unit_type = 'establishment' THEN
        RETURN QUERY
        SELECT t.unit_type, t.unit_id, t.valid_from, t.valid_to, t.valid_until,
            COALESCE(eia1.external_idents, '{}'::jsonb) AS external_idents,
            t.name, t.birth_date, t.death_date, t.search,
            t.primary_activity_category_id, t.primary_activity_category_path, t.primary_activity_category_code,
            t.secondary_activity_category_id, t.secondary_activity_category_path, t.secondary_activity_category_code,
            t.activity_category_paths, t.sector_id, t.sector_path, t.sector_code, t.sector_name,
            t.data_source_ids, t.data_source_codes, t.legal_form_id, t.legal_form_code, t.legal_form_name,
            t.physical_address_part1, t.physical_address_part2, t.physical_address_part3, t.physical_postcode, t.physical_postplace,
            t.physical_region_id, t.physical_region_path, t.physical_region_code, t.physical_country_id, t.physical_country_iso_2,
            t.physical_latitude, t.physical_longitude, t.physical_altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.postal_latitude, t.postal_longitude, t.postal_altitude,
            t.web_address, t.email_address, t.phone_number, t.landline, t.mobile_number, t.fax_number,
            t.unit_size_id, t.unit_size_code, t.status_id, t.status_code, t.used_for_counting,
            t.last_edit_comment, t.last_edit_by_user_id, t.last_edit_at, t.has_legal_unit,
            t.related_establishment_ids, t.excluded_establishment_ids, t.included_establishment_ids,
            t.related_legal_unit_ids, t.excluded_legal_unit_ids, t.included_legal_unit_ids,
            t.related_enterprise_ids, t.excluded_enterprise_ids, t.included_enterprise_ids,
            t.stats, t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range,
            public.hash_slot(t.unit_type, t.unit_id) AS hash_slot
        FROM public.timeline_establishment t
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.establishment_id = t.unit_id) eia1 ON true
        LEFT JOIN LATERAL (SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths FROM public.tag_for_unit tfu JOIN public.tag ON tfu.tag_id = tag.id WHERE tfu.establishment_id = t.unit_id) tpa ON true
        WHERE t.unit_id = ANY(v_ids);

    ELSIF p_unit_type = 'legal_unit' THEN
        RETURN QUERY
        SELECT t.unit_type, t.unit_id, t.valid_from, t.valid_to, t.valid_until,
            COALESCE(eia1.external_idents, '{}'::jsonb) AS external_idents,
            t.name, t.birth_date, t.death_date, t.search,
            t.primary_activity_category_id, t.primary_activity_category_path, t.primary_activity_category_code,
            t.secondary_activity_category_id, t.secondary_activity_category_path, t.secondary_activity_category_code,
            t.activity_category_paths, t.sector_id, t.sector_path, t.sector_code, t.sector_name,
            t.data_source_ids, t.data_source_codes, t.legal_form_id, t.legal_form_code, t.legal_form_name,
            t.physical_address_part1, t.physical_address_part2, t.physical_address_part3, t.physical_postcode, t.physical_postplace,
            t.physical_region_id, t.physical_region_path, t.physical_region_code, t.physical_country_id, t.physical_country_iso_2,
            t.physical_latitude, t.physical_longitude, t.physical_altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.postal_latitude, t.postal_longitude, t.postal_altitude,
            t.web_address, t.email_address, t.phone_number, t.landline, t.mobile_number, t.fax_number,
            t.unit_size_id, t.unit_size_code, t.status_id, t.status_code, t.used_for_counting,
            t.last_edit_comment, t.last_edit_by_user_id, t.last_edit_at, t.has_legal_unit,
            t.related_establishment_ids, t.excluded_establishment_ids, t.included_establishment_ids,
            t.related_legal_unit_ids, t.excluded_legal_unit_ids, t.included_legal_unit_ids,
            t.related_enterprise_ids, t.excluded_enterprise_ids, t.included_enterprise_ids,
            t.stats, t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range,
            public.hash_slot(t.unit_type, t.unit_id) AS hash_slot
        FROM public.timeline_legal_unit t
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.legal_unit_id = t.unit_id) eia1 ON true
        LEFT JOIN LATERAL (SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths FROM public.tag_for_unit tfu JOIN public.tag ON tfu.tag_id = tag.id WHERE tfu.legal_unit_id = t.unit_id) tpa ON true
        WHERE t.unit_id = ANY(v_ids);

    ELSIF p_unit_type = 'enterprise' THEN
        RETURN QUERY
        SELECT t.unit_type, t.unit_id, t.valid_from, t.valid_to, t.valid_until,
            COALESCE(eia1.external_idents, eia2.external_idents, eia3.external_idents, '{}'::jsonb) AS external_idents,
            t.name::varchar, t.birth_date, t.death_date, t.search,
            t.primary_activity_category_id, t.primary_activity_category_path, t.primary_activity_category_code,
            t.secondary_activity_category_id, t.secondary_activity_category_path, t.secondary_activity_category_code,
            t.activity_category_paths, t.sector_id, t.sector_path, t.sector_code, t.sector_name,
            t.data_source_ids, t.data_source_codes, t.legal_form_id, t.legal_form_code, t.legal_form_name,
            t.physical_address_part1, t.physical_address_part2, t.physical_address_part3, t.physical_postcode, t.physical_postplace,
            t.physical_region_id, t.physical_region_path, t.physical_region_code, t.physical_country_id, t.physical_country_iso_2,
            t.physical_latitude, t.physical_longitude, t.physical_altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.postal_latitude, t.postal_longitude, t.postal_altitude,
            t.web_address, t.email_address, t.phone_number, t.landline, t.mobile_number, t.fax_number,
            t.unit_size_id, t.unit_size_code, t.status_id, t.status_code, t.used_for_counting,
            t.last_edit_comment, t.last_edit_by_user_id, t.last_edit_at, t.has_legal_unit,
            t.related_establishment_ids, t.excluded_establishment_ids, t.included_establishment_ids,
            t.related_legal_unit_ids, t.excluded_legal_unit_ids, t.included_legal_unit_ids,
            t.related_enterprise_ids, t.excluded_enterprise_ids, t.included_enterprise_ids,
            NULL::JSONB AS stats, t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range,
            public.hash_slot(t.unit_type, t.unit_id) AS hash_slot
        FROM public.timeline_enterprise t
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.enterprise_id = t.unit_id) eia1 ON true
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.establishment_id = t.primary_establishment_id) eia2 ON true
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.legal_unit_id = t.primary_legal_unit_id) eia3 ON true
        LEFT JOIN LATERAL (SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths FROM public.tag_for_unit tfu JOIN public.tag ON tfu.tag_id = tag.id WHERE tfu.enterprise_id = t.unit_id) tpa ON true
        WHERE t.unit_id = ANY(v_ids);

    ELSIF p_unit_type = 'power_group' THEN
        RETURN QUERY
        SELECT t.unit_type, t.unit_id, t.valid_from, t.valid_to, t.valid_until,
            COALESCE(eia1.external_idents, '{}'::jsonb) AS external_idents,
            t.name::varchar, t.birth_date, t.death_date, t.search,
            t.primary_activity_category_id, t.primary_activity_category_path, t.primary_activity_category_code,
            t.secondary_activity_category_id, t.secondary_activity_category_path, t.secondary_activity_category_code,
            t.activity_category_paths, t.sector_id, t.sector_path, t.sector_code, t.sector_name,
            t.data_source_ids, t.data_source_codes, t.legal_form_id, t.legal_form_code, t.legal_form_name,
            t.physical_address_part1, t.physical_address_part2, t.physical_address_part3, t.physical_postcode, t.physical_postplace,
            t.physical_region_id, t.physical_region_path, t.physical_region_code, t.physical_country_id, t.physical_country_iso_2,
            t.physical_latitude, t.physical_longitude, t.physical_altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.postal_latitude, t.postal_longitude, t.postal_altitude,
            t.web_address, t.email_address, t.phone_number, t.landline, t.mobile_number, t.fax_number,
            t.unit_size_id, t.unit_size_code, t.status_id, t.status_code, t.used_for_counting,
            t.last_edit_comment, t.last_edit_by_user_id, t.last_edit_at, t.has_legal_unit,
            t.related_establishment_ids, t.excluded_establishment_ids, t.included_establishment_ids,
            t.related_legal_unit_ids, t.excluded_legal_unit_ids, t.included_legal_unit_ids,
            t.related_enterprise_ids, t.excluded_enterprise_ids, t.included_enterprise_ids,
            NULL::JSONB AS stats, t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range,
            public.hash_slot(t.unit_type, t.unit_id) AS hash_slot
        FROM public.timeline_power_group t
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.power_group_id = t.power_group_id) eia1 ON true
        LEFT JOIN LATERAL (SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths FROM public.tag_for_unit tfu JOIN public.tag ON tfu.tag_id = tag.id WHERE tfu.power_group_id = t.power_group_id) tpa ON true
        WHERE t.unit_id = ANY(v_ids);
    END IF;
END;
$function$;



COMMIT;

