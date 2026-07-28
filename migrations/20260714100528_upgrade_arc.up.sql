-- Upgrade-arc OOM fixture (STATBUS-096): a real migration the arc kills
-- mid-sleep (docker compose kill -s SIGKILL db) to reproduce the effect
-- of an OS OOM-kill of Postgres. Bare statement, no BEGIN/END — must
-- appear as pg_stat_activity's own active query for the arc's midpoint poll.
-- ORDERING IS LOAD-BEARING: sleep BEFORE the DDL — no BEGIN/END means psql
-- autocommits per statement, so a committed-early table would turn the
-- revival's re-run into a relation-exists failure → rolled_back, the exact
-- opposite terminal. Sleep-first commits nothing on a mid-sleep kill.
SELECT pg_sleep(60);
CREATE TABLE public.upgrade_arc_oom_fixture (
    id integer PRIMARY KEY,
    note text NOT NULL
);
INSERT INTO public.upgrade_arc_oom_fixture (id, note) VALUES (1, 'oom');
