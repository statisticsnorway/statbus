-- Down Migration 20261119154414: unit photos are small and removed when nothing shows them
BEGIN;

DROP TRIGGER establishment_image_released ON public.establishment;
DROP TRIGGER legal_unit_image_released ON public.legal_unit;
DROP TABLE admin.image_released;
DROP FUNCTION public.image_drop_released();
DROP FUNCTION public.image_note_released();

ALTER TABLE public.image DROP CONSTRAINT image_size_limit;
ALTER TABLE public.image ADD CONSTRAINT image_size_limit CHECK (length(data) <= 4194304);

COMMENT ON TABLE public.image IS
  'Non-temporal storage for unit images (logos, photos). Referenced by legal_unit and establishment. Validates magic bytes on insert to prevent XSS attacks via malicious file uploads.';
COMMENT ON COLUMN public.image.data IS
  'Binary image data with EXTERNAL storage (no compression). Max 4MB. Validated on insert: only PNG, JPEG, GIF, WebP allowed.';

END;
