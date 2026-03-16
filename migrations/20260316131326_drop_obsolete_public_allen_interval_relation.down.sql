BEGIN;

-- Recreate the obsolete public.allen_interval_relation enum (identical values to sql_saga version).
CREATE TYPE public.allen_interval_relation AS ENUM (
    'precedes',
    'meets',
    'overlaps',
    'starts',
    'during',
    'finishes',
    'equals',
    'overlapped_by',
    'started_by',
    'contains',
    'finished_by',
    'met_by',
    'preceded_by'
);

COMMENT ON TYPE public.allen_interval_relation IS
'Allen''s interval algebra relations for two intervals X=(X.va, X.vt] and Y=(Y.va, Y.vt], using (exclusive_start, inclusive_end] semantics.
The ASCII art illustrates interval X relative to interval Y.';

END;
