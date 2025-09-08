BEGIN;

CREATE TABLE public.statistical_unit (LIKE public.statistical_unit_def INCLUDING ALL);

CREATE UNIQUE INDEX "statistical_unit_upsert_pkey"
    ON public.statistical_unit
    (unit_type, unit_id, valid_from);

CREATE UNIQUE INDEX "statistical_unit_from_key"
    ON public.statistical_unit
    (valid_from
    ,valid_to
    ,unit_type
    ,unit_id
    );

CREATE UNIQUE INDEX "statistical_unit_until_key"
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
    p_establishment_ids int[] DEFAULT NULL,
    p_legal_unit_ids int[] DEFAULT NULL,
    p_enterprise_ids int[] DEFAULT NULL
)
LANGUAGE plpgsql AS $procedure$
DECLARE
    v_batch_size INT := 50000; v_unit_type public.statistical_unit_type;
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
BEGIN
    IF p_establishment_ids IS NULL AND p_legal_unit_ids IS NULL AND p_enterprise_ids IS NULL THEN
        -- Full refresh
        FOREACH v_unit_type IN ARRAY ARRAY['establishment', 'legal_unit', 'enterprise']::public.statistical_unit_type[] LOOP
            SELECT MIN(unit_id), MAX(unit_id) INTO v_min_id, v_max_id FROM public.timesegments WHERE unit_type = v_unit_type;
            IF v_min_id IS NULL THEN CONTINUE; END IF;

            FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
                v_start_id := i;
                v_end_id := i + v_batch_size - 1;

                -- Batched DELETE is used instead of TRUNCATE to avoid taking an ACCESS EXCLUSIVE lock,
                -- which would block concurrent reads on the table. This is more MVCC-friendly.
                DELETE FROM public.statistical_unit
                WHERE unit_type = v_unit_type AND unit_id BETWEEN v_start_id AND v_end_id;

                INSERT INTO public.statistical_unit SELECT * FROM public.statistical_unit_def
                WHERE unit_type = v_unit_type AND unit_id BETWEEN v_start_id AND v_end_id;
            END LOOP;
        END LOOP;
    ELSE
        -- Partial refresh
        IF p_establishment_ids IS NOT NULL AND cardinality(p_establishment_ids) > 0 THEN
            DELETE FROM public.statistical_unit WHERE unit_type = 'establishment' AND unit_id = ANY(p_establishment_ids);
            INSERT INTO public.statistical_unit SELECT * FROM public.statistical_unit_def WHERE unit_type = 'establishment' AND unit_id = ANY(p_establishment_ids);
        END IF;
        IF p_legal_unit_ids IS NOT NULL AND cardinality(p_legal_unit_ids) > 0 THEN
            DELETE FROM public.statistical_unit WHERE unit_type = 'legal_unit' AND unit_id = ANY(p_legal_unit_ids);
            INSERT INTO public.statistical_unit SELECT * FROM public.statistical_unit_def WHERE unit_type = 'legal_unit' AND unit_id = ANY(p_legal_unit_ids);
        END IF;
        IF p_enterprise_ids IS NOT NULL AND cardinality(p_enterprise_ids) > 0 THEN
            DELETE FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id = ANY(p_enterprise_ids);
            INSERT INTO public.statistical_unit SELECT * FROM public.statistical_unit_def WHERE unit_type = 'enterprise' AND unit_id = ANY(p_enterprise_ids);
        END IF;
    END IF;
END;
$procedure$;

CALL public.statistical_unit_refresh();

END;
