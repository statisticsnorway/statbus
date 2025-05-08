BEGIN;

DROP FUNCTION IF EXISTS admin.batch_upsert_generic_valid_time_table(
    TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, TEXT[], TEXT[], TEXT[], TEXT
);

COMMIT;
