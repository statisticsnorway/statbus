BEGIN;

\echo lifecycle_callbacks.add_table('public.stat_definition');
CALL lifecycle_callbacks.add_table('public.stat_definition');

END;