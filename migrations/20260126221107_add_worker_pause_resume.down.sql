-- Down Migration: Remove worker pause/resume functions

DROP FUNCTION IF EXISTS worker.resume();
DROP FUNCTION IF EXISTS worker.pause(INTERVAL);
DROP FUNCTION IF EXISTS worker.pause(BIGINT);
