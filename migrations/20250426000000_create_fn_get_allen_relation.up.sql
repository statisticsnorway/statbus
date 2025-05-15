BEGIN;

CREATE OR REPLACE FUNCTION public.get_allen_relation(
    va1 DATE, -- valid_after for interval 1
    vt1 DATE, -- valid_to for interval 1
    va2 DATE, -- valid_after for interval 2
    vt2 DATE  -- valid_to for interval 2
)
RETURNS public.allen_interval_relation
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
AS $$
BEGIN
    -- Ensure intervals are valid (end is not before or at start)
    IF vt1 <= va1 THEN
        RAISE EXCEPTION 'Interval 1 is invalid: (%, %]', va1, vt1;
    END IF;
    IF vt2 <= va2 THEN
        RAISE EXCEPTION 'Interval 2 is invalid: (%, %]', va2, vt2;
    END IF;

    -- Check for 'equals'
    IF va1 = va2 AND vt1 = vt2 THEN
        RETURN 'equals';
    -- Check for 'starts'
    ELSIF va1 = va2 AND vt1 < vt2 THEN
        RETURN 'starts';
    -- Check for 'started_by' (inverse of starts)
    ELSIF va1 = va2 AND vt1 > vt2 THEN
        RETURN 'started_by';
    -- Check for 'finishes'
    ELSIF va1 > va2 AND vt1 = vt2 THEN
        RETURN 'finishes';
    -- Check for 'finished_by' (inverse of finishes)
    ELSIF va1 < va2 AND vt1 = vt2 THEN
        RETURN 'finished_by';
    -- Check for 'during' (interval1 is during interval2)
    ELSIF va1 > va2 AND vt1 < vt2 THEN
        RETURN 'during';
    -- Check for 'contains' (interval1 contains interval2 - inverse of during)
    ELSIF va1 < va2 AND vt1 > vt2 THEN
        RETURN 'contains';
    -- Check for 'overlaps'
    ELSIF va1 < va2 AND vt1 > va2 AND vt1 < vt2 THEN
        RETURN 'overlaps';
    -- Check for 'overlapped_by' (inverse of overlaps)
    ELSIF va2 < va1 AND vt2 > va1 AND vt2 < vt1 THEN
        RETURN 'overlapped_by';
    -- Check for 'meets'
    ELSIF vt1 = va2 THEN
        RETURN 'meets';
    -- Check for 'met_by' (inverse of meets)
    ELSIF vt2 = va1 THEN
        RETURN 'met_by';
    -- Check for 'precedes'
    ELSIF vt1 < va2 THEN
        RETURN 'precedes';
    -- Check for 'preceded_by' (inverse of precedes)
    ELSIF vt2 < va1 THEN
        RETURN 'preceded_by';
    ELSE
        -- This case should ideally not be reached if all relations are covered
        RAISE EXCEPTION 'Unhandled Allen interval case for (%, %] and (%, %]', va1, vt1, va2, vt2;
    END IF;
END;
$$;

COMMENT ON FUNCTION public.get_allen_relation(DATE, DATE, DATE, DATE) IS 
'Determines Allen''s interval algebra relationship between two intervals X=(va1, vt1] and Y=(va2, vt2], using (exclusive_start, inclusive_end] semantics.
Returns one of the 13 Allen interval relation ENUM values.';

END;
