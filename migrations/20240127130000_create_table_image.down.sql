BEGIN;

DROP TABLE IF EXISTS public.image CASCADE;
DROP FUNCTION IF EXISTS public.validate_image_on_insert();
DROP FUNCTION IF EXISTS public.detect_image_type(bytea);

COMMIT;
