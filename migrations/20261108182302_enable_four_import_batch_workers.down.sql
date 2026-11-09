BEGIN;

UPDATE worker.queue_registry
SET default_concurrency = 1,
    description = 'Serial queue for processing import jobs'
WHERE queue = 'import';

COMMENT ON TABLE worker.queue_registry IS
'Defines available task queues. The system runs as a single worker process, which processes each queue serially to ensure task order. However, it uses concurrent fibers to process different queues (e.g., ''analytics'' and ''import'') at the same time.';
COMMENT ON COLUMN worker.queue_registry.default_concurrency IS
'Number of parallel workers for this queue. 1=serial (default). Higher values used for child task processing in structured concurrency mode.';

COMMIT;
