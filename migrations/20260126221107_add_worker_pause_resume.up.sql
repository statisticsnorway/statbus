-- Add worker pause/resume mechanism via pg_notify
--
-- This allows tests to pause the background worker while they run,
-- ensuring manual CALL worker.process_tasks() has full control over
-- task processing order.
--
-- Usage:
--   SELECT worker.pause('1 hour'::interval);  -- Pause for 1 hour
--   SELECT worker.pause(3600);                -- Pause for 3600 seconds
--   SELECT worker.resume();                   -- Resume immediately
--
-- The background worker listens on the 'worker_control' channel and
-- respects the pause state. Manual worker.process_tasks() calls are
-- NOT affected - they always work regardless of pause state.

-- Pause worker for specified number of seconds
-- The worker will auto-resume after the timeout expires
CREATE FUNCTION worker.pause(p_seconds BIGINT) 
RETURNS void 
LANGUAGE sql AS $pause$
  SELECT pg_notify('worker_control', 'pause:' || p_seconds::text);
$pause$;

COMMENT ON FUNCTION worker.pause(BIGINT) IS 
'Pause the background worker for the specified number of seconds. 
The worker will auto-resume after timeout. Use worker.resume() to resume early.
Manual CALL worker.process_tasks() is NOT affected by pause state.';

-- Convenience overload accepting interval
CREATE FUNCTION worker.pause(p_duration INTERVAL) 
RETURNS void 
LANGUAGE sql AS $pause_interval$
  SELECT worker.pause(EXTRACT(EPOCH FROM p_duration)::bigint);
$pause_interval$;

COMMENT ON FUNCTION worker.pause(INTERVAL) IS 
'Pause the background worker for the specified duration. 
The worker will auto-resume after timeout. Use worker.resume() to resume early.
Manual CALL worker.process_tasks() is NOT affected by pause state.';

-- Resume worker immediately
CREATE FUNCTION worker.resume() 
RETURNS void 
LANGUAGE sql AS $resume$
  SELECT pg_notify('worker_control', 'resume');
$resume$;

COMMENT ON FUNCTION worker.resume() IS 
'Resume the background worker immediately. 
Call this at the end of tests that used worker.pause().';

-- Grant execute to authenticated users (needed for tests)
GRANT EXECUTE ON FUNCTION worker.pause(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION worker.pause(INTERVAL) TO authenticated;
GRANT EXECUTE ON FUNCTION worker.resume() TO authenticated;
