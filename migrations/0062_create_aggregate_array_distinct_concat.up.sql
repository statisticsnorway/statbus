-- Final function to remove duplicates from concatenated arrays
CREATE FUNCTION public.array_distinct_concat_final(anycompatiblearray)
RETURNS anycompatiblearray LANGUAGE sql AS $$
SELECT array_agg(DISTINCT elem)
  FROM unnest($1) as elem;
$$;

-- Aggregate function using array_cat for concatenation and public.array_distinct_concat_final to remove duplicates
CREATE AGGREGATE public.array_distinct_concat(anycompatiblearray) (
  SFUNC = pg_catalog.array_cat,
  STYPE = anycompatiblearray,
  FINALFUNC = public.array_distinct_concat_final,
  INITCOND = '{}'
);