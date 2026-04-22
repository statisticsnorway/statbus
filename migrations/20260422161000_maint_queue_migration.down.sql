-- No-op. This migration only re-enqueues stuck maintenance rows where a
-- failed row exists with no pending successor. Reversing that recovery
-- (removing the pending rows we just added) would re-introduce the stuck
-- state — never what an operator wants on a rollback.
SELECT 'maint-queue-migration down: intentional no-op' AS note;
