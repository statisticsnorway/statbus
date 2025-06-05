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
    -- Inverse relations (Y relative to X, but ENUM value describes X's relation to Y)
    'overlapped_by',-- X overlapped_by Y (i.e., Y overlaps X): Y.va < X.va AND Y.vt > X.va AND Y.vt < X.vt
                    -- X:      (----XXXX ]
                    -- Y: ( YYYY----]
    'started_by',   -- X started_by Y (i.e., Y starts X): Y.va = X.va AND Y.vt < X.vt
                    -- X: ( XXXXXXX ]
                    -- Y: ( YYYY ]
    'contains',     -- X contains Y (i.e., Y during X): Y.va > X.va AND Y.vt < X.vt
                    -- X: ( XXXXXXX ]
                    -- Y:   ( YYYY ]
    'finished_by',  -- X finished_by Y (i.e., Y finishes X): Y.va < X.va AND Y.vt = X.vt
                    -- X: ( XXXXXXX ]
                    -- Y:      ( YYYY ]
    'met_by',       -- X met_by Y (i.e., Y meets X): Y.vt = X.va
                    -- X:         ( XXXX ]
                    -- Y: ( YYYY ]  (Touching: Y.vt is X.va)
    'preceded_by'   -- X preceded_by Y (i.e., Y precedes X): Y.vt < X.va
                    -- X:           ( XXXX ]
                    -- Y: ( YYYY ]
);

COMMENT ON TYPE public.allen_interval_relation IS 
'Allen''s interval algebra relations for two intervals X=(X.va, X.vt] and Y=(Y.va, Y.vt], using (exclusive_start, inclusive_end] semantics.
The ASCII art illustrates interval X relative to interval Y.';

END;
