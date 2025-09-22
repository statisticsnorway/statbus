BEGIN;

CREATE TABLE public.statistical_unit (LIKE public.statistical_unit_def INCLUDING ALL);

CREATE UNIQUE INDEX "statistical_unit_upsert_pkey"
    ON public.statistical_unit
    (unit_type, unit_id, valid_from);

-- This index enforces uniqueness for each time segment. It uses `valid_until` as this is the canonical
-- column for the exclusive end of the validity period `[valid_from, valid_until)`, whereas `valid_to` is
-- a derived column for UI convenience.
CREATE UNIQUE INDEX "statistical_unit_from_key"
    ON public.statistical_unit
    (valid_from
    ,valid_until
    ,unit_type
    ,unit_id
    );

-- Ensure that incorrect data can not be entered, as a safeguard agains errors in processing by worker.
ALTER TABLE public.statistical_unit ADD
    CONSTRAINT "statistical_unit_type_id_daterange_excl"
    EXCLUDE USING gist (
        unit_type WITH =,
        unit_id WITH =,
        daterange(valid_from, valid_until, '[)'::text) WITH &&
    ) DEFERRABLE;


CREATE INDEX idx_statistical_unit_unit_type ON public.statistical_unit (unit_type);
CREATE INDEX idx_statistical_unit_establishment_id ON public.statistical_unit (unit_id);
CREATE INDEX idx_statistical_unit_search ON public.statistical_unit USING GIN (search);
CREATE INDEX idx_statistical_unit_primary_activity_category_id ON public.statistical_unit (primary_activity_category_id);
CREATE INDEX idx_statistical_unit_secondary_activity_category_id ON public.statistical_unit (secondary_activity_category_id);
CREATE INDEX idx_statistical_unit_physical_region_id ON public.statistical_unit (physical_region_id);
CREATE INDEX idx_statistical_unit_physical_country_id ON public.statistical_unit (physical_country_id);
CREATE INDEX idx_statistical_unit_sector_id ON public.statistical_unit (sector_id);

CREATE INDEX idx_statistical_unit_data_source_ids ON public.statistical_unit USING GIN (data_source_ids);

CREATE INDEX idx_statistical_unit_sector_path ON public.statistical_unit(sector_path);
CREATE INDEX idx_gist_statistical_unit_sector_path ON public.statistical_unit USING GIST (sector_path);

CREATE INDEX idx_statistical_unit_legal_form_id ON public.statistical_unit (legal_form_id);
CREATE INDEX idx_statistical_unit_invalid_codes ON public.statistical_unit USING gin (invalid_codes);
CREATE INDEX idx_statistical_unit_invalid_codes_exists ON public.statistical_unit (invalid_codes) WHERE invalid_codes IS NOT NULL;

CREATE INDEX idx_statistical_unit_primary_activity_category_path ON public.statistical_unit(primary_activity_category_path);
CREATE INDEX idx_gist_statistical_unit_primary_activity_category_path ON public.statistical_unit USING GIST (primary_activity_category_path);

CREATE INDEX idx_statistical_unit_secondary_activity_category_path ON public.statistical_unit(secondary_activity_category_path);
CREATE INDEX idx_gist_statistical_unit_secondary_activity_category_path ON public.statistical_unit USING GIST (secondary_activity_category_path);

CREATE INDEX idx_statistical_unit_activity_category_paths ON public.statistical_unit(activity_category_paths);
CREATE INDEX idx_gist_statistical_unit_activity_category_paths ON public.statistical_unit USING GIST (activity_category_paths);

CREATE INDEX idx_statistical_unit_physical_region_path ON public.statistical_unit(physical_region_path);
CREATE INDEX idx_gist_statistical_unit_physical_region_path ON public.statistical_unit USING GIST (physical_region_path);

CREATE INDEX idx_statistical_unit_external_idents ON public.statistical_unit(external_idents);
CREATE INDEX idx_gist_statistical_unit_external_idents ON public.statistical_unit USING GIN (external_idents jsonb_path_ops);

CREATE INDEX idx_statistical_unit_tag_paths ON public.statistical_unit(tag_paths);
CREATE INDEX idx_gist_statistical_unit_tag_paths ON public.statistical_unit USING GIST (tag_paths);

CREATE INDEX IF NOT EXISTS idx_statistical_unit_related_establishment_ids ON public.statistical_unit USING gin (related_establishment_ids);
CREATE INDEX IF NOT EXISTS idx_statistical_unit_related_legal_unit_ids ON public.statistical_unit USING gin (related_legal_unit_ids);
CREATE INDEX IF NOT EXISTS idx_statistical_unit_related_enterprise_ids ON public.statistical_unit USING gin (related_enterprise_ids);


CREATE OR REPLACE PROCEDURE public.statistical_unit_refresh(
    p_establishment_id_ranges int4multirange DEFAULT NULL,
    p_legal_unit_id_ranges int4multirange DEFAULT NULL,
    p_enterprise_id_ranges int4multirange DEFAULT NULL
)
LANGUAGE plpgsql AS $procedure$
DECLARE
    v_batch_size INT := 262144;
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
    v_batch_num INT;
    v_total_units INT;
    v_batch_start_time timestamptz;
    v_batch_duration_ms numeric;
    v_batch_speed numeric;
    v_current_batch_size int;
BEGIN
    ANALYZE public.timeline_establishment, public.timeline_legal_unit, public.timeline_enterprise;

    IF p_establishment_id_ranges IS NULL AND p_legal_unit_id_ranges IS NULL AND p_enterprise_id_ranges IS NULL THEN
        -- Full refresh: Use a staging table for performance and to minimize lock duration.
        CREATE TEMP TABLE statistical_unit_new (LIKE public.statistical_unit) ON COMMIT DROP;

        -- Establishments
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'establishment';
        RAISE DEBUG 'Refreshing statistical units for % establishments in batches of %...', v_total_units, v_batch_size;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            INSERT INTO statistical_unit_new SELECT * FROM public.statistical_unit_def
            WHERE unit_type = 'establishment' AND unit_id BETWEEN v_start_id AND v_end_id;
            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Establishment SU batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP; END IF;

        -- Legal Units
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'legal_unit';
        RAISE DEBUG 'Refreshing statistical units for % legal units in batches of %...', v_total_units, v_batch_size;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            INSERT INTO statistical_unit_new SELECT * FROM public.statistical_unit_def
            WHERE unit_type = 'legal_unit' AND unit_id BETWEEN v_start_id AND v_end_id;
            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Legal unit SU batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP; END IF;

        -- Enterprises
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'enterprise';
        RAISE DEBUG 'Refreshing statistical units for % enterprises in batches of %...', v_total_units, v_batch_size;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            INSERT INTO statistical_unit_new SELECT * FROM public.statistical_unit_def
            WHERE unit_type = 'enterprise' AND unit_id BETWEEN v_start_id AND v_end_id;
            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Enterprise SU batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP; END IF;

        -- Atomically swap the data
        TRUNCATE public.statistical_unit;
        INSERT INTO public.statistical_unit SELECT * FROM statistical_unit_new;

    ELSE
        -- Partial refresh
        IF p_establishment_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit WHERE unit_type = 'establishment' AND unit_id <@ p_establishment_id_ranges;
            INSERT INTO public.statistical_unit SELECT * FROM public.statistical_unit_def WHERE unit_type = 'establishment' AND unit_id <@ p_establishment_id_ranges;
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit WHERE unit_type = 'legal_unit' AND unit_id <@ p_legal_unit_id_ranges;
            INSERT INTO public.statistical_unit SELECT * FROM public.statistical_unit_def WHERE unit_type = 'legal_unit' AND unit_id <@ p_legal_unit_id_ranges;
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id <@ p_enterprise_id_ranges;
            INSERT INTO public.statistical_unit SELECT * FROM public.statistical_unit_def WHERE unit_type = 'enterprise' AND unit_id <@ p_enterprise_id_ranges;
        END IF;
    END IF;

    ANALYZE public.statistical_unit;
END;
$procedure$;

CALL public.statistical_unit_refresh();

END;
