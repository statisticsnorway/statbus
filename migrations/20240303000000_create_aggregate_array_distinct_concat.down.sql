BEGIN;

DROP AGGREGATE public.array_distinct_concat(anycompatiblearray);
DROP FUNCTION public.array_distinct_concat_final(anycompatiblearray);

END;
