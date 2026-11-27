-- sz7rvn: a search on a region, sector or activity path is fast for a signed-in user, however few
-- units match. public.statistical_unit has row-level security, and the planner lets a
-- non-superuser's WHERE condition use its column statistics and index ahead of the policy only
-- when the condition's operator function is LEAKPROOF. The ltree comparison functions are not
-- marked so by the extension, so a path with fewer than ten units read the whole register in
-- name order (on the Norway register a 5-unit region took over 20 s; with the mark 0.2 ms).
--
-- The functions compare two ltree values and report nothing but the result, so they reveal no
-- row data an error or side effect could leak: marking them LEAKPROOF is sound. The owner chose
-- this over removing the row-level security (2026-11-27): the security model stays the same for
-- every table, and a later per-unit restriction keeps its hook.
--
-- The mark lives on extension member functions, which pg_restore --clean recreates; post_restore.sql
-- sets it again after every migrate up, so a restored database keeps it.
BEGIN;

ALTER FUNCTION public.ltree_risparent(public.ltree, public.ltree) LEAKPROOF;  -- <@  contained in
ALTER FUNCTION public.ltree_isparent(public.ltree, public.ltree) LEAKPROOF;   -- @>  contains
ALTER FUNCTION public.ltree_eq(public.ltree, public.ltree) LEAKPROOF;         -- =

END;
