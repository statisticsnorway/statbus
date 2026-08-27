BEGIN;

-- Reverses STATBUS-267. Order matters: the pending task row and the registry
-- row go before the objects they name, so nothing is left referencing a
-- procedure that no longer exists.

-- Any pending/failed occurrence of the command must go before the registry row
-- it references (worker.tasks.command → command_registry.command).
DELETE FROM worker.tasks WHERE command = 'detect_stuck_tasks';

DELETE FROM worker.command_registry WHERE command = 'detect_stuck_tasks';

DROP INDEX IF EXISTS worker.idx_tasks_detect_stuck_tasks_dedup;

DROP PROCEDURE IF EXISTS worker.command_detect_stuck_tasks(jsonb, jsonb);

DROP FUNCTION IF EXISTS worker.abandoned_processing_tasks();

END;
