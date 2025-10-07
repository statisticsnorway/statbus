```sql
CREATE OR REPLACE PROCEDURE public.timepoints_refresh(IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    rec RECORD;
    v_en_batch INT[];
    v_lu_batch INT[];
    v_es_batch INT[];
    v_batch_size INT := 32768; -- Number of enterprises to process per batch
    v_total_enterprises INT;
    v_processed_count INT := 0;
    v_batch_num INT := 0;
    v_batch_start_time timestamptz;
    v_batch_duration_ms numeric;
    v_batch_speed numeric;
BEGIN
    ANALYZE public.establishment, public.legal_unit, public.enterprise, public.activity, public.location, public.contact, public.stat_for_unit, public.person_for_unit;

    IF p_establishment_id_ranges IS NULL AND p_legal_unit_id_ranges IS NULL AND p_enterprise_id_ranges IS NULL THEN
        -- Full refresh: Use a staging table for performance and to minimize lock duration.
        CREATE TEMP TABLE timepoints_new (LIKE public.timepoints) ON COMMIT DROP;

        SELECT count(*) INTO v_total_enterprises FROM public.enterprise;
        RAISE DEBUG 'Starting full timepoints refresh for % enterprises in batches of %...', v_total_enterprises, v_batch_size;

        FOR rec IN SELECT id FROM public.enterprise LOOP
            v_en_batch := array_append(v_en_batch, rec.id);

            IF array_length(v_en_batch, 1) >= v_batch_size THEN
                v_batch_start_time := clock_timestamp();
                -- For this batch of enterprises, find all descendant LUs and ESTs
                v_processed_count := v_processed_count + array_length(v_en_batch, 1);
                v_batch_num := v_batch_num + 1;

                v_lu_batch := ARRAY(SELECT id FROM public.legal_unit WHERE enterprise_id = ANY(v_en_batch));
                v_es_batch := ARRAY(
                    SELECT id FROM public.establishment WHERE legal_unit_id = ANY(v_lu_batch)
                    UNION
                    SELECT id FROM public.establishment WHERE enterprise_id = ANY(v_en_batch)
                );

                INSERT INTO timepoints_new
                SELECT * FROM public.timepoints_calculate(
                    public.array_to_int4multirange(v_es_batch),
                    public.array_to_int4multirange(v_lu_batch),
                    public.array_to_int4multirange(v_en_batch)
                ) ON CONFLICT DO NOTHING;

                v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
                v_batch_speed := v_batch_size / (v_batch_duration_ms / 1000.0);
                RAISE DEBUG 'Timepoints batch %/% for enterprises done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_enterprises::decimal / v_batch_size), v_batch_size, round(v_batch_duration_ms), round(v_batch_speed);

                v_en_batch := '{}'; -- Reset for next batch
            END IF;
        END LOOP;

        -- Process the final, smaller batch
        IF array_length(v_en_batch, 1) > 0 THEN
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_lu_batch := ARRAY(SELECT id FROM public.legal_unit WHERE enterprise_id = ANY(v_en_batch));
            v_es_batch := ARRAY(
                SELECT id FROM public.establishment WHERE legal_unit_id = ANY(v_lu_batch)
                UNION
                SELECT id FROM public.establishment WHERE enterprise_id = ANY(v_en_batch)
            );
            INSERT INTO timepoints_new
            SELECT * FROM public.timepoints_calculate(
                public.array_to_int4multirange(v_es_batch),
                public.array_to_int4multirange(v_lu_batch),
                public.array_to_int4multirange(v_en_batch)
            ) ON CONFLICT DO NOTHING;
            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_batch_speed := array_length(v_en_batch, 1) / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Timepoints final batch %/% for enterprises done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_enterprises::decimal / v_batch_size), array_length(v_en_batch, 1), round(v_batch_duration_ms), round(v_batch_speed);
        END IF;

        -- Atomically swap the data
        RAISE DEBUG 'Populated staging table, now swapping data...';
        TRUNCATE public.timepoints;
        INSERT INTO public.timepoints SELECT DISTINCT * FROM timepoints_new;
        RAISE DEBUG 'Full timepoints refresh complete.';
    ELSE
        -- Partial refresh
        RAISE DEBUG 'Starting partial timepoints refresh...';
        IF p_establishment_id_ranges IS NOT NULL THEN
            DELETE FROM public.timepoints WHERE unit_type = 'establishment' AND unit_id <@ p_establishment_id_ranges;
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            DELETE FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id <@ p_legal_unit_id_ranges;
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            DELETE FROM public.timepoints WHERE unit_type = 'enterprise' AND unit_id <@ p_enterprise_id_ranges;
        END IF;

        INSERT INTO public.timepoints SELECT * FROM public.timepoints_calculate(
            p_establishment_id_ranges,
            p_legal_unit_id_ranges,
            p_enterprise_id_ranges
        ) ON CONFLICT DO NOTHING;

        RAISE DEBUG 'Partial timepoints refresh complete.';
    END IF;

    ANALYZE public.timepoints;
END;
$procedure$
```
