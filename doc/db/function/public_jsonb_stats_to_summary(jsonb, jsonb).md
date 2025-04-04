```sql
CREATE OR REPLACE FUNCTION public.jsonb_stats_to_summary(state jsonb, stats jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE PARALLEL SAFE STRICT
AS $function$
DECLARE
    prev_stat_state jsonb;
    stat_key text;
    stat_value jsonb;
    stat_type text;
    prev_stat_type text;
    next_stat_state jsonb;
    state_type text;
    stats_type text;
BEGIN
    IF state IS NULL OR stats IS NULL THEN
        RAISE EXCEPTION 'Logic error: STRICT function should never be called with NULL';
    END IF;

    state_type := jsonb_typeof(state);
    IF state_type <> 'object' THEN
        RAISE EXCEPTION 'Type mismatch for state "%": % <> object', state, state_type;
    END IF;

    stats_type := jsonb_typeof(stats);
    IF stats_type <> 'object' THEN
        RAISE EXCEPTION 'Type mismatch for stats "%": % <> object', stats, stats_type;
    END IF;

    -- Update state with data from `value`
    FOR stat_key, stat_value IN SELECT * FROM jsonb_each(stats) LOOP
        stat_type := jsonb_typeof(stat_value);

        IF state ? stat_key THEN
            prev_stat_state := state->stat_key;
            prev_stat_type := prev_stat_state->>'type';
            IF stat_type <> prev_stat_type THEN
                RAISE EXCEPTION 'Type mismatch between values for key "%" was "%" became "%"', stat_key, prev_stat_type, stat_type;
            END IF;
            next_stat_state = jsonb_build_object('type', stat_type);

            CASE stat_type
                -- Handle numeric values with iterative mean, variance, standard deviation, and coefficient of variation.
                WHEN 'number' THEN
                    DECLARE
                        sum numeric := (prev_stat_state->'sum')::numeric + stat_value::numeric;
                        count integer := (prev_stat_state->'count')::integer + 1;
                        delta numeric := stat_value::numeric - (prev_stat_state->'mean')::numeric;
                        mean numeric := (prev_stat_state->'mean')::numeric + delta / count;
                        min numeric := LEAST((prev_stat_state->'min')::numeric, stat_value::numeric);
                        max numeric := GREATEST((prev_stat_state->'max')::numeric, stat_value::numeric);
                        sum_sq_diff numeric := (prev_stat_state->'sum_sq_diff')::numeric + delta * (stat_value::numeric - mean);

                        -- Calculate variance and standard deviation
                        variance numeric := CASE WHEN count > 1 THEN sum_sq_diff / (count - 1) ELSE NULL END;
                        stddev numeric := CASE WHEN variance IS NOT NULL THEN sqrt(variance) ELSE NULL END;

                        -- Calculate Coefficient of Variation (CV)
                        coefficient_of_variation_pct numeric := CASE
                            WHEN mean IS NULL OR mean = 0 THEN NULL
                            ELSE (stddev / mean) * 100
                        END;
                    BEGIN
                        next_stat_state :=  next_stat_state ||
                            jsonb_build_object(
                                'sum', sum,
                                'count', count,
                                'mean', mean,
                                'min', min,
                                'max', max,
                                'sum_sq_diff', sum_sq_diff,
                                'variance', variance,
                                'stddev', stddev,
                                'coefficient_of_variation_pct', coefficient_of_variation_pct
                            );
                    END;

                -- Handle string values
                WHEN 'string' THEN
                    next_stat_state :=  next_stat_state ||
                        jsonb_build_object(
                            'counts',
                            -- The previous dictionary with count for each key.
                            (prev_stat_state->'counts')
                            -- Appending to it
                            ||
                            -- The updated count for this particular key.
                            jsonb_build_object(
                                -- Notice that `->>0` extracts the non-quoted string,
                                -- otherwise the key would be double quoted.
                                stat_value->>0,
                                COALESCE((prev_stat_state->'counts'->(stat_value->>0))::integer, 0) + 1
                            )
                        );

                -- Handle boolean types
                WHEN 'boolean' THEN
                    next_stat_state :=  next_stat_state ||
                        jsonb_build_object(
                            'counts', jsonb_build_object(
                                'true', COALESCE((prev_stat_state->'counts'->'true')::integer, 0) + (stat_value::boolean)::integer,
                                'false', COALESCE((prev_stat_state->'counts'->'false')::integer, 0) + (NOT stat_value::boolean)::integer
                            )
                        );

                -- Handle array types
                WHEN 'array' THEN
                    DECLARE
                        element text;
                        element_count integer;
                        count integer;
                    BEGIN
                        -- Start with the previous state, to preserve previous counts.
                        next_stat_state := prev_stat_state;

                        FOR element IN SELECT jsonb_array_elements_text(stat_value) LOOP
                            -- Retrieve the old count for this element, defaulting to 0 if not present
                            count := COALESCE((next_stat_state->'counts'->element)::integer, 0) + 1;

                            -- Update the next state with the incremented count
                            next_stat_state := jsonb_set(
                                next_stat_state,
                                ARRAY['counts',element],
                                to_jsonb(count)
                            );
                        END LOOP;
                    END;

                -- Handle object (nested JSON)
                WHEN 'object' THEN
                    next_stat_state := public.jsonb_stats_to_summary(prev_stat_state, stat_value);

                ELSE
                    RAISE EXCEPTION 'Unsupported type "%" for %', stat_type, stat_value;
            END CASE;
        ELSE
            -- Initialize new entry in state
            next_stat_state = jsonb_build_object('type', stat_type);
            CASE stat_type
                WHEN 'number' THEN
                    next_stat_state := next_stat_state ||
                        jsonb_build_object(
                            'sum', stat_value::numeric,
                            'count', 1,
                            'mean', stat_value::numeric,
                            'min', stat_value::numeric,
                            'max', stat_value::numeric,
                            'sum_sq_diff', 0,
                            'variance', 0,
                            'stddev', 0,
                            'coefficient_of_variation_pct', 0
                        );

                WHEN 'string' THEN
                    next_stat_state :=  next_stat_state ||
                        jsonb_build_object(
                            -- Notice that `->>0` extracts the non-quoted string,
                            -- otherwise the key would be double quoted.
                            'counts', jsonb_build_object(stat_value->>0, 1)
                        );

                WHEN 'boolean' THEN
                    next_stat_state :=  next_stat_state ||
                            jsonb_build_object(
                            'counts', jsonb_build_object(
                                'true', (stat_value::boolean)::integer,
                                'false', (NOT stat_value::boolean)::integer
                            )
                        );

                WHEN 'array' THEN
                    -- Initialize array with counts of each unique value
                    next_stat_state :=  next_stat_state ||
                        jsonb_build_object(
                            'counts',
                            (
                            SELECT jsonb_object_agg(element,1)
                            FROM jsonb_array_elements_text(stat_value) AS element
                            )
                        );

                WHEN 'object' THEN
                    next_stat_state := public.jsonb_stats_to_summary(next_stat_state, stat_value);

                ELSE
                    RAISE EXCEPTION 'Unsupported type "%" for %', stat_type, stat_value;
            END CASE;
        END IF;

        state := state || jsonb_build_object(stat_key, next_stat_state);
    END LOOP;

    RETURN state;
END;
$function$
```
