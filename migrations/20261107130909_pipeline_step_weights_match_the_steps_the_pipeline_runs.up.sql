-- The navbar progress bar (app/src/components/navbar.tsx computeWeightedPhaseProgress) weighs
-- each depth-2 pipeline step by this table. The rows per phase, in seq order, are exactly the
-- steps worker.command_collect_changes spawns, in spawn order (test 371). Before this migration
-- derive_used_tables ran without a row, so the units bar fell to 0% at the end of phase 1, and
-- derive_reports had a row although the pipeline no longer spawns it.
--
-- Weights are the seconds each step took in a full Norway recalculation (statbus_local,
-- 2026-11-06, 3.1 M statistical units, tmp/rp558-tree.out), divided by 10 and rounded, at least 1:
--   phase 1: derive_statistical_unit 1,695 s, derive_statistical_history_facet_delta 772 s,
--            statistical_unit_flush_staging 109 s, derive_used_tables 5 s
--   phase 2: derive_statistical_unit_facet 201 s, statistical_history_facet_delta_reduce 72 s,
--            statistical_unit_facet_reduce 23 s
BEGIN;

COMMENT ON TABLE worker.pipeline_step_weight IS
    'Relative wall-clock weights of the pipeline steps, for the frontend progress bars. Per phase, the rows in seq order are exactly the steps worker.command_collect_changes spawns, in spawn order: collect_changes and the children of derive_units_phase for is_deriving_statistical_units, the children of derive_reports_phase for is_deriving_reports. A step without a row shows as 0% while it runs.';

DELETE FROM worker.pipeline_step_weight;
INSERT INTO worker.pipeline_step_weight (phase, step, weight, seq) VALUES
    ('is_deriving_statistical_units', 'collect_changes', 1, 0),
    ('is_deriving_statistical_units', 'derive_statistical_unit', 170, 1),
    ('is_deriving_statistical_units', 'derive_statistical_history_facet_delta', 77, 2),
    ('is_deriving_statistical_units', 'statistical_unit_flush_staging', 11, 3),
    ('is_deriving_statistical_units', 'derive_used_tables', 1, 4),
    ('is_deriving_reports', 'derive_statistical_unit_facet', 20, 5),
    ('is_deriving_reports', 'statistical_unit_facet_reduce', 2, 6),
    ('is_deriving_reports', 'statistical_history_facet_delta_reduce', 7, 7);

END;
