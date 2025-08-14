-- Revoke permissions in reverse order of granting.
DROP POLICY IF EXISTS import_job_notify_reader_select_all ON public.import_job;

-- Revoke SELECT on tables from the db-listener role
REVOKE SELECT ON TABLE public.import_job FROM notify_reader;
REVOKE SELECT ON TABLE public.import_definition FROM notify_reader;
