-- Migration 20260421155421: install_last_tracking
--
-- Declare the public.system_info keys that the `./sb install`
-- post-completion path upserts on every successful run:
--
--   install_last_log_relative_file_path — basename under tmp/install-logs/
--       of the log produced by the most recent install invocation
--   install_last_at                     — TIMESTAMPTZ of that run
--
-- This completes the A20 capability separation: install no longer authors a
-- public.upgrade row on StateNothingScheduled, so the admin UI needs a
-- separate surface to show "last install invocation time + log" alongside
-- the existing install_last_error* trio.
--
-- Seeded with empty sentinels so the UI can read the keys without a
-- runtime-insert race on first load. stampInstallInvocationTracking
-- overwrites them on every subsequent successful install.
BEGIN;

INSERT INTO public.system_info (key, value) VALUES
    ('install_last_log_relative_file_path', ''),
    ('install_last_at', '')
ON CONFLICT (key) DO NOTHING;

END;
