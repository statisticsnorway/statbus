\set ON_ERROR_STOP 0
BEGIN;
SET LOCAL ROLE "rabbit-review@statbus.org";
SELECT current_user, session_user, auth.uid();
INSERT INTO public.enterprise (short_name) VALUES ('5vxfjm-probe')
RETURNING id, edit_by_user_id, (SELECT email FROM auth.user WHERE id=edit_by_user_id) AS stamped;
RESET ROLE;
SELECT current_user AS after_reset, auth.uid() AS uid_after_reset;
INSERT INTO worker.tasks(command, payload) VALUES ('import_job_process', '{"command":"import_job_process","job_id":-1}') RETURNING id, current_user AS bookkeeping_as;
SET LOCAL ROLE "rabbit-review@statbus.org";
SELECT current_user AS again;
-- escape attempts by code running as the user role:
SAVEPOINT s1; RESET ROLE; SELECT current_user AS after_user_reset; ROLLBACK TO s1;
SELECT current_user AS after_rollback_to_s1;
SAVEPOINT s2; SET ROLE postgres; ROLLBACK TO s2;
SAVEPOINT s3; SET SESSION AUTHORIZATION postgres; ROLLBACK TO s3;
SAVEPOINT s4; INSERT INTO worker.tasks(command, payload) VALUES ('import_job_process','{}'); ROLLBACK TO s4;
COMMIT;
SELECT id, short_name, (SELECT email FROM auth.user WHERE id=edit_by_user_id) FROM public.enterprise WHERE short_name='5vxfjm-probe';
SELECT id, command, payload FROM worker.tasks WHERE payload->>'job_id'='-1';
DELETE FROM worker.tasks WHERE payload->>'job_id'='-1';
