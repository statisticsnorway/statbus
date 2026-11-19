-- Down Migration 20261119180643: unit photo comment describes the whole scaled photo
BEGIN;

COMMENT ON COLUMN public.image.data IS
  'Binary image data with EXTERNAL storage (no compression). At most 256 KB (image_size_limit): photos are few and small, cropped to a square and scaled by the app. Validated on insert: only PNG, JPEG, GIF, WebP allowed.';

END;
