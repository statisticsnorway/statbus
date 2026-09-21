-- Migration 20260921223349: persist serving tree convergence obligation
BEGIN;

ALTER TABLE public.upgrade
ADD COLUMN tree_convergence_required boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.upgrade.tree_convergence_required IS
'Crash-safe box-level obligation created when a successor claim displaces a parked upgrade whose serving containers may lag the checked-out tree. Every later candidate inherits any true carrier row across retries and supersession; only a successful serving-tree convergence may clear all carriers.';

END;
