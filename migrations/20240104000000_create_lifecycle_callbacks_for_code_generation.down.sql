BEGIN;

DROP TABLE lifecycle_callbacks.registered_callback;
DROP TABLE lifecycle_callbacks.supported_table;
DROP PROCEDURE lifecycle_callbacks.add_table(regclass);
DROP PROCEDURE lifecycle_callbacks.del_table(regclass);
DROP PROCEDURE lifecycle_callbacks.add(text,regclass[],regproc,regproc);
DROP PROCEDURE lifecycle_callbacks.del(text);
DROP FUNCTION lifecycle_callbacks.cleanup_and_generate();
DROP PROCEDURE lifecycle_callbacks.generate(regclass);
DROP PROCEDURE lifecycle_callbacks.cleanup(regclass);
DROP SCHEMA lifecycle_callbacks CASCADE;

END;
