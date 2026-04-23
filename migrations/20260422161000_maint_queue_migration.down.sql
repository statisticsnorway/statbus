-- No-op: this migration only reboots maintenance-queue scheduling via
-- canonical enqueue functions. Removing the resulting pending rows would
-- re-introduce the stuck state we just fixed. If you need to roll this
-- back for any reason, the worker's self-rescheduling cycle will continue
-- running normally.
SELECT 1;
