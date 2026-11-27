-- Down for sz7rvn: the ltree comparison functions as the extension defines them, not LEAKPROOF.
BEGIN;

ALTER FUNCTION public.ltree_risparent(public.ltree, public.ltree) NOT LEAKPROOF;
ALTER FUNCTION public.ltree_isparent(public.ltree, public.ltree) NOT LEAKPROOF;
ALTER FUNCTION public.ltree_eq(public.ltree, public.ltree) NOT LEAKPROOF;

END;
