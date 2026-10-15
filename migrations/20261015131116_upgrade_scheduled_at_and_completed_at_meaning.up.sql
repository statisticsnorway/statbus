-- Migration 20261015131116: upgrade scheduled_at and completed_at meaning
BEGIN;

COMMENT ON COLUMN public.upgrade.scheduled_at IS
'When someone asked for this version to be installed: an operator via ./sb upgrade schedule, or the release channel. Setting it is the request itself: upgrade_notify_daemon_trigger turns it into NOTIFY upgrade_apply, and the upgrade daemon runs the request. It records intent, so it is NULL on a row nobody asked to run, such as a version ./sb install put on the box directly.';

COMMENT ON COLUMN public.upgrade.completed_at IS
'When this version was confirmed running on the box: an upgrade finished, or ./sb install installed it. It records an outcome.';

END;
