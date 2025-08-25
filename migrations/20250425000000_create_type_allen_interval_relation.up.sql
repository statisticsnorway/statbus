BEGIN;

-- Use Allen's Interval Relation for covering all possible cases of overlap. Ref. https://ics.uci.edu/~alspaugh/cls/shr/allen.html

CREATE TYPE public.allen_interval_relation AS ENUM (
    'precedes',     -- X before Y: X.vt < Y.va
                    -- X: ( XXXX ]
                    -- Y:           ( YYYY ]
    'meets',        -- X meets Y: X.vt = Y.va
                    -- X: ( XXXX ]
                    -- Y:         ( YYYY ]  (Touching: X.vt is Y.va)
    'overlaps',     -- X overlaps Y: X.va < Y.va AND X.vt > Y.va AND X.vt < Y.vt
                    -- X: ( XXXX----]
                    -- Y:      (----YYYY ]
    'starts',       -- X starts Y: X.va = Y.va AND X.vt < Y.vt
                    -- X: ( XXXX ]
                    -- Y: ( YYYYYYYY ]
    'during',       -- X during Y: X.va > Y.va AND X.vt < Y.vt (X is contained in Y)
                    -- X:   ( XXXX ]
                    -- Y: ( YYYYYYYY ]
    'finishes',     -- X finishes Y: X.va > Y.va AND X.vt = Y.vt
                    -- X:      ( XXXX ]
                    -- Y: ( YYYYYYYY ]
    'equals',       -- X equals Y: X.va = Y.va AND X.vt = Y.vt
                    -- X: ( XXXX ]
                    -- Y: ( YYYY ]
    -- Inverse relations (describing X's relation to Y)
    'overlapped_by',-- X is overlapped by Y (Y overlaps X): Y.va < X.va AND Y.vt > X.va AND Y.vt < X.vt
                    -- X:      (----XXXX ]
                    -- Y: ( YYYY----]
    'started_by',   -- X is started by Y (Y starts X): Y.va = X.va AND Y.vt < X.vt
                    -- X: ( XXXXXXX ]
                    -- Y: ( YYYY ]
    'contains',     -- X contains Y (Y is during X): Y.va > X.va AND Y.vt < X.vt
                    -- X: ( XXXXXXX ]
                    -- Y:   ( YYYY ]
    'finished_by',  -- X is finished by Y (Y finishes X): Y.va > X.va AND Y.vt = X.vt
                    -- X: ( XXXXXXX ]
                    -- Y:      ( YYYY ]
    'met_by',       -- X is met by Y (Y meets X): Y.vt = X.va
                    -- X:         ( XXXX ]
                    -- Y: ( YYYY ]
    'preceded_by'   -- X is preceded by Y (Y precedes X): Y.vt < X.va
                    -- X:           ( XXXX ]
                    -- Y: ( YYYY ]
);

COMMENT ON TYPE public.allen_interval_relation IS 
'Allen''s interval algebra relations for two intervals X=(X.va, X.vt] and Y=(Y.va, Y.vt], using (exclusive_start, inclusive_end] semantics.
The ASCII art illustrates interval X relative to interval Y.';

CREATE OR REPLACE FUNCTION public.allen_get_relation(
    x_va DATE, x_vt DATE,
    y_va DATE, y_vt DATE
) RETURNS public.allen_interval_relation
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS
$BODY$
    SELECT CASE
        -- Cases where start points are the same
        WHEN x_va = y_va AND x_vt = y_vt THEN 'equals'::public.allen_interval_relation
        WHEN x_va = y_va AND x_vt < y_vt THEN 'starts'::public.allen_interval_relation
        WHEN x_va = y_va AND x_vt > y_vt THEN 'started_by'::public.allen_interval_relation
        -- Cases where end points are the same
        WHEN x_va > y_va AND x_vt = y_vt THEN 'finishes'::public.allen_interval_relation
        WHEN x_va < y_va AND x_vt = y_vt THEN 'finished_by'::public.allen_interval_relation
        -- Case where one interval is during another
        WHEN x_va > y_va AND x_vt < y_vt THEN 'during'::public.allen_interval_relation
        WHEN x_va < y_va AND x_vt > y_vt THEN 'contains'::public.allen_interval_relation
        -- Cases where intervals are adjacent
        WHEN x_vt = y_va THEN 'meets'::public.allen_interval_relation
        WHEN y_vt = x_va THEN 'met_by'::public.allen_interval_relation
        -- Cases where intervals overlap
        WHEN x_va < y_va AND x_vt > y_va AND x_vt < y_vt THEN 'overlaps'::public.allen_interval_relation
        WHEN y_va < x_va AND y_vt > x_va AND y_vt < x_vt THEN 'overlapped_by'::public.allen_interval_relation
        -- Cases where intervals are disjoint
        WHEN x_vt < y_va THEN 'precedes'::public.allen_interval_relation
        WHEN y_vt < x_va THEN 'preceded_by'::public.allen_interval_relation
    END;
$BODY$;

COMMENT ON FUNCTION public.allen_get_relation IS
'Calculates the Allen Interval Algebra relation between two intervals X and Y,
assuming (exclusive_start, inclusive_end] semantics. The exclusive start (va) means
a record is valid from the day AFTER va.';

END;
