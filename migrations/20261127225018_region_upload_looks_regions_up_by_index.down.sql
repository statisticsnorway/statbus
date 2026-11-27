-- Down Migration 20261127225018: region upload looks regions up by index, however full the table is
BEGIN;

ALTER FUNCTION admin.region_upload_upsert() RESET enable_seqscan;

COMMENT ON FUNCTION admin.region_upload_upsert() IS
  'Adds or changes a region from one row of a region file (public.region_upload), connecting its parent by path. A row changes only what it gives: a new region needs a name; an existing one keeps its name when the row has none, keeps its centre when the row has no latitude and longitude, and keeps its altitude unless the row gives one or moves the centre. A row that matches what is stored writes nothing (5yxn4w).';

END;
