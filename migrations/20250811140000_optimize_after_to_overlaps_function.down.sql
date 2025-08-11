BEGIN;

-- Restore the original B-Tree-based implementation of the function.
CREATE OR REPLACE FUNCTION public.after_to_overlaps(
    a_after date, a_to date,
    b_after date, b_to date
) RETURNS boolean LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $after_to_overlaps$
    SELECT a_after < b_to AND b_after < a_to;
$after_to_overlaps$;

END;
