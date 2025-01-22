BEGIN;

-- Aggregate: jsonb_concat_agg
-- Purpose: Aggregate function to concatenate JSONB objects from multiple rows into a single JSONB object.
-- Example:
--   SELECT jsonb_concat_agg(column_name) FROM table_name;
--   Output: A single JSONB object resulting from the concatenation of JSONB objects from all rows.
-- Notice:
--   The function `jsonb_concat` is not documented, but named equivalent of `||`.
CREATE AGGREGATE public.jsonb_concat_agg(jsonb) (
    sfunc = jsonb_concat,
    stype = jsonb,
    initcond = '{}'
);

END;