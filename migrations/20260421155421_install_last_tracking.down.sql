-- Down for 20260421155421_install_last_tracking: remove the install-invocation
-- tracking keys. public.system_info schema is unchanged.
BEGIN;

DELETE FROM public.system_info
 WHERE key IN ('install_last_log_relative_file_path', 'install_last_at');

END;
