BEGIN;

UPDATE worker.queue_registry
SET default_concurrency = 4,
    description = 'Import jobs use one serial coordinator and four concurrent dependency-batch workers by default. Analysis, job ordering and holistic processing remain serial.'
WHERE queue = 'import';

COMMENT ON TABLE worker.queue_registry IS
'Defines task queues discovered by the worker. Each queue has one serial coordinator and its configured concurrent child executors. Queues run independently, while child_mode and the structured-concurrency barrier determine task ordering.';
COMMENT ON COLUMN worker.queue_registry.default_concurrency IS
'Default number of concurrent child executors for this queue, in addition to its serial coordinator. Existing per-queue worker overrides take precedence. A value of one processes concurrent children one at a time.';

COMMIT;
