-- TODO Later: Move to sql_saga
CREATE TYPE admin.existing_upsert_case AS ENUM
    -- n is NEW
    -- e is existing
    -- e_t is new tail to existing
    -- Used to merge to avoid multiple rows
    ( 'existing_adjacent_valid_from'
    -- [--e--]
    --        [--n--]
    -- IF equivalent THEN delete(e) AND n.valid_from = e.valid.from
    -- [---------n--]
    , 'existing_adjacent_valid_to'
    --        [--e--]
    -- [--n--]
    -- IFF equivalent THEN delete(e) AND n.valid_to = e.valid_to
    -- [--n---------]
    -- Used to adjust the valid_from/valid_to to carve out room for new data.
    , 'existing_overlaps_valid_from'
    --    [---e---]
    --         [----n----]
    -- IFF equivalent THEN delete(e) AND n.valid_from = e.valid_from
    --    [---------n----]
    -- ELSE e.valid_to = n.valid_from - '1 day'
    --    [-e-]
    --         [----n----]
    , 'inside_existing'
    -- [---------e--------]
    --        [--n--]
    -- IFF equivalent THEN delete(e) AND n.valid_from = e.valid_from AND n.valid_to = e.valid_to
    -- [---------n--------]
    -- ELSE IF NOT n.active THEN e.valid_to = n.valid_from - '1 day'
    -- [--e--]
    --        [--n--]
    -- ELSE e.valid_to = n.valid_from - '1 day', e_t.valid_from = n.valid_to + '1 day', e_t.valid_to = e.valid_to
    -- [--e--]       [-e_t-]
    --        [--n--]
    , 'contains_existing'
    --          [-e-]
    --       [----n----]
    -- THEN delete(e)
    --       [----n----]
    , 'existing_overlaps_valid_to'
    --        [----e----]
    --    [----n----]
    -- IFF equivalent THEN delete(e) AND n.valid_to = e.valid_to
    --    [----n--------]
    -- ELSE IF NOT n.active
    --    [----n----]
    -- ELSE e.valid_from = n.valid_to + '1 day'
    --               [-e-]
    --    [----n----]
    );
-- The n.active dependent logic is not implemented, because It's not clear to me
-- that that you insert should modify things outside the specified timeline.

-- TODO Later: CREATE FUNCTION sql_saga.api_upsert(NEW record, ...)