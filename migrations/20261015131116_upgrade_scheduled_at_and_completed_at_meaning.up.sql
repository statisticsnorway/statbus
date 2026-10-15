-- Migration 20261015131116: upgrade scheduled_at and completed_at meaning
BEGIN;

COMMENT ON COLUMN public.upgrade.scheduled_at IS
'When this version was asked for. An operator (./sb upgrade schedule) or the release channel sets it to request an upgrade; upgrade_notify_daemon_trigger turns a newly set value into NOTIFY upgrade_apply, and the upgrade daemon runs the request. A row that ./sb install inserts already completed carries its install time here (no trigger fires on INSERT). ./sb install leaves it as it was on a row that already exists.';

COMMENT ON COLUMN public.upgrade.completed_at IS
'When this version was confirmed running on the box: an upgrade finished, or ./sb install installed it. It records an outcome.';

END;
