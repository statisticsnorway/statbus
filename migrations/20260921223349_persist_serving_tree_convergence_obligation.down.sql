-- Down Migration 20260921223349: persist serving tree convergence obligation
BEGIN;

ALTER TABLE public.upgrade
DROP COLUMN tree_convergence_required;

END;
