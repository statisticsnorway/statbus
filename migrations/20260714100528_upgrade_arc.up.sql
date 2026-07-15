-- Upgrade-arc CEILING fixture (STATBUS-095 piece 2): a real migration our
-- own STATBUS_MIGRATE_UP_TIMEOUT ceiling kills mid-sleep (SIGKILL at the
-- ctx deadline, service.go's applyPostSwap migrate call). Bare statement,
-- no BEGIN/END — must appear as pg_stat_activity's own active query.
SELECT pg_sleep(3600);
