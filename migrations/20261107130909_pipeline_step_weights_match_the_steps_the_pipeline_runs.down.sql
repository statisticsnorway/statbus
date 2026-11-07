BEGIN;

COMMENT ON TABLE worker.pipeline_step_weight IS
    'Relative wall-clock weights for pipeline steps, used by frontend progress bars. Keyed by command name (no phase enum dependency).';

DELETE FROM worker.pipeline_step_weight;
INSERT INTO worker.pipeline_step_weight (step, weight, seq, phase) VALUES
    ('collect_changes', 1, 0, 'is_deriving_statistical_units'),
    ('derive_statistical_unit', 87, 1, 'is_deriving_statistical_units'),
    ('derive_statistical_history_facet_delta', 10, 2, 'is_deriving_statistical_units'),
    ('derive_reports', 1, 3, 'is_deriving_reports'),
    ('statistical_unit_flush_staging', 14, 3, 'is_deriving_statistical_units'),
    ('derive_statistical_unit_facet', 2, 6, 'is_deriving_reports'),
    ('statistical_unit_facet_reduce', 3, 7, 'is_deriving_reports'),
    ('statistical_history_facet_delta_reduce', 2, 9, 'is_deriving_reports');

END;
