-- Migration 20261119180643: unit photo comment describes the whole scaled photo (svx99s).
-- The app keeps the whole photo, scaled to at most 800 px on its longest side, instead
-- of the centred square 20261119154414 described.
BEGIN;

COMMENT ON COLUMN public.image.data IS
  'Binary image data with EXTERNAL storage (no compression). At most 256 KB (image_size_limit): photos are few and small; the app keeps the whole picture, scaled so its longest side is at most 800 px, as JPEG. Validated on insert: only PNG, JPEG, GIF, WebP allowed.';

END;
