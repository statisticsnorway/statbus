-- Grant SELECT on tables required by the db-listener
GRANT SELECT ON TABLE public.import_job TO notify_reader;
GRANT SELECT ON TABLE public.import_definition TO notify_reader;

-- RLS policies are enforced on top of standard GRANT permissions.
-- The db-listener runs as the 'notify_reader' role, which needs to be able to
-- SELECT from import_job to enrich notifications. This policy allows it.
CREATE POLICY import_job_notify_reader_select_all ON public.import_job
  FOR SELECT
  TO notify_reader
  USING (true);
