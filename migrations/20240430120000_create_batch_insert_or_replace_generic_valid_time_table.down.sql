BEGIN;

DROP FUNCTION IF EXISTS admin.batch_insert_or_replace_generic_valid_time_table(
    TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, TEXT[], TEXT[], TEXT[], TEXT
);

COMMIT;
