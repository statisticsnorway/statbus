BEGIN;

CALL lifecycle_callbacks.del_table('public.stat_definition');

END;
