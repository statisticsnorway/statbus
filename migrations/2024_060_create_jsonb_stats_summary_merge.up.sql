BEGIN;

\echo public.jsonb_stats_summary_merge
CREATE FUNCTION public.jsonb_stats_summary_merge(a jsonb, b jsonb) RETURNS jsonb LANGUAGE plpgsql IMMUTABLE STRICT AS $$
DECLARE
    key_a text;
    key_b text;
    val_a jsonb;
    val_b jsonb;
    merged_val jsonb;
    type_a text;
    type_b text;
    result jsonb := '{}';
BEGIN
    -- Ensure both a and b are objects
    IF jsonb_typeof(a) <> 'object' OR jsonb_typeof(b) <> 'object' THEN
        RAISE EXCEPTION 'Both arguments must be JSONB objects';
    END IF;

    -- Iterate over keys in both JSONB objects
    FOR key_a, val_a IN SELECT * FROM jsonb_each(a) LOOP
        IF b ? key_a THEN
            val_b := b->key_a;
            type_a := val_a->>'type';
            type_b := val_b->>'type';

            -- Ensure the types are the same for the same key
            IF type_a <> type_b THEN
                RAISE EXCEPTION 'Type mismatch for key "%": % vs %', key_a, type_a, type_b;
            END IF;

            -- Merge the values based on their type
            CASE type_a
                WHEN 'number' THEN
                    DECLARE
                        count_a INTEGER := (val_a->'count')::INTEGER;
                        count_b INTEGER := (val_b->'count')::INTEGER;
                        total_count INTEGER := count_a + count_b;

                        mean_a NUMERIC := (val_a->'mean')::NUMERIC;
                        mean_b NUMERIC := (val_b->'mean')::NUMERIC;
                        merged_mean NUMERIC := (mean_a * count_a + mean_b * count_b) / total_count;

                        sum_sq_diff_a NUMERIC := (val_a->'sum_sq_diff')::NUMERIC;
                        sum_sq_diff_b NUMERIC := (val_b->'sum_sq_diff')::NUMERIC;
                        delta NUMERIC := mean_b - mean_a;

                        merged_sum_sq_diff NUMERIC :=
                            sum_sq_diff_a + sum_sq_diff_b + delta * delta * count_a * count_b / total_count;
                        merged_variance NUMERIC :=
                            CASE WHEN total_count > 1
                            THEN merged_sum_sq_diff / (total_count - 1)
                            ELSE NULL
                            END;
                        merged_stddev NUMERIC :=
                            CASE WHEN merged_variance IS NOT NULL
                            THEN sqrt(merged_variance)
                            ELSE NULL
                            END;

                        -- Calculate Coefficient of Variation (CV)
                        coefficient_of_variation_pct NUMERIC :=
                            CASE WHEN merged_mean <> 0
                            THEN (merged_stddev / merged_mean) * 100
                            ELSE NULL
                            END;
                    BEGIN
                        merged_val := jsonb_build_object(
                            'sum', (val_a->'sum')::numeric + (val_b->'sum')::numeric,
                            'count', total_count,
                            'mean', merged_mean,
                            'min', LEAST((val_a->'min')::numeric, (val_b->'min')::numeric),
                            'max', GREATEST((val_a->'max')::numeric, (val_b->'max')::numeric),
                            'sum_sq_diff', merged_sum_sq_diff,
                            'variance', merged_variance,
                            'stddev', merged_stddev,
                            'coefficient_of_variation_pct', coefficient_of_variation_pct
                        );
                    END;

                WHEN 'string' THEN
                    merged_val := jsonb_build_object(
                        'counts', (
                            SELECT jsonb_object_agg(key, value)
                            FROM (
                                SELECT key, SUM(value) AS value
                                FROM (
                                    SELECT key, value::integer FROM jsonb_each(val_a->'counts')
                                    UNION ALL
                                    SELECT key, value::integer FROM jsonb_each(val_b->'counts')
                                ) AS enumerated
                                GROUP BY key
                            ) AS merged_counts
                        )
                    );

                WHEN 'boolean' THEN
                    merged_val := jsonb_build_object(
                        'counts', jsonb_build_object(
                            'true', (val_a->'counts'->>'true')::integer + (val_b->'counts'->>'true')::integer,
                            'false', (val_a->'counts'->>'false')::integer + (val_b->'counts'->>'false')::integer
                        )
                    );

                WHEN 'array' THEN
                    merged_val := jsonb_build_object(
                        'counts', (
                            SELECT jsonb_object_agg(key, value)
                            FROM (
                                SELECT key, SUM(value) AS value
                                FROM (
                                    SELECT key, value::integer FROM jsonb_each(val_a->'counts')
                                    UNION ALL
                                    SELECT key, value::integer FROM jsonb_each(val_b->'counts')
                                ) AS enumerated
                                GROUP BY key
                            ) AS merged_counts
                        )
                    );

                WHEN 'object' THEN
                    merged_val := public.jsonb_stats_summary_merge(val_a, val_b);

                ELSE
                    RAISE EXCEPTION 'Unsupported type "%" for key "%"', type_a, key_a;
            END CASE;

            -- Add the merged value to the result
            result := result || jsonb_build_object(key_a, jsonb_build_object('type', type_a) || merged_val);
        ELSE
            -- Key only in a
            result := result || jsonb_build_object(key_a, val_a);
        END IF;
    END LOOP;

    -- Add keys only in b
    FOR key_b, val_b IN SELECT key, value FROM jsonb_each(b) WHERE NOT (a ? key) LOOP
        result := result || jsonb_build_object(key_b, val_b);
    END LOOP;

    RETURN result;
END;
$$;


\echo public.jsonb_stats_summary_merge_agg
CREATE AGGREGATE public.jsonb_stats_summary_merge_agg(jsonb) (
    sfunc = public.jsonb_stats_summary_merge,
    stype = jsonb,
    initcond = '{}',
    finalfunc = public.jsonb_stats_to_summary_round
);

END;
