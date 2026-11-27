-- Migration 20261127225018: region upload looks regions up by index, however full the table is
BEGIN;

-- 7dw69p: see the function's comment. On Uganda (region empty for a month, so vacuumed and analysed
-- as empty) a 58,000-region file met authenticated's 120 s statement_timeout; with this it stores in
-- about 20 s.
ALTER FUNCTION admin.region_upload_upsert() SET enable_seqscan = off;

COMMENT ON FUNCTION admin.region_upload_upsert() IS
  'Adds or changes a region from one row of a region file (public.region_upload), connecting its parent by path. A row changes only what it gives: a new region needs a name; an existing one keeps its name when the row has none, keeps its centre when the row has no latitude and longitude, and keeps its altitude unless the row gives one or moves the centre. A row that matches what is stored writes nothing (5yxn4w). It runs once per row and looks up the parent and the stored region in public.region, which the same upload is filling, while the planner''s statistics still describe the table as it was before the upload, often empty. It therefore runs with enable_seqscan = off (7dw69p): each lookup is one probe of region_version_path_key (version_id, path) instead of a scan of every region stored so far, which made a large file take minutes.';

END;
