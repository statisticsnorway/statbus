-- Create non-temporal table for storing unit images
-- This table is referenced by legal_unit and establishment (temporal tables)
-- to avoid duplicating large binary data across temporal versions

BEGIN;

-- Function to detect image type from magic bytes
-- Returns MIME type if recognized, NULL otherwise
-- Supported formats: PNG, JPEG, GIF, WebP (binary formats only)
-- SVG is explicitly NOT supported due to XSS risks (can contain JavaScript)
CREATE FUNCTION public.detect_image_type(data bytea)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
STRICT
SET search_path = public
AS $detect_image_type$
DECLARE
  _len integer;
BEGIN
  _len := octet_length(data);
  
  -- Check each format with minimum length requirements
  -- JPEG: FF D8 FF (3 bytes minimum)
  IF _len >= 3 AND substring(data FROM 1 FOR 3) = '\xffd8ff'::bytea THEN
    RETURN 'image/jpeg';
  END IF;
  
  -- GIF: GIF87a or GIF89a (6 bytes)
  IF _len >= 6 AND (
       substring(data FROM 1 FOR 6) = '\x474946383761'::bytea 
    OR substring(data FROM 1 FOR 6) = '\x474946383961'::bytea
  ) THEN
    RETURN 'image/gif';
  END IF;
  
  -- PNG: 89 50 4E 47 0D 0A 1A 0A (8 bytes)
  IF _len >= 8 AND substring(data FROM 1 FOR 8) = '\x89504e470d0a1a0a'::bytea THEN
    RETURN 'image/png';
  END IF;
  
  -- WebP: RIFF????WEBP (bytes 1-4 = "RIFF", bytes 9-12 = "WEBP", need 12 bytes)
  IF _len >= 12 
     AND substring(data FROM 1 FOR 4) = '\x52494646'::bytea 
     AND substring(data FROM 9 FOR 4) = '\x57454250'::bytea THEN
    RETURN 'image/webp';
  END IF;
  
  RETURN NULL; -- Unknown format
END;
$detect_image_type$;

COMMENT ON FUNCTION public.detect_image_type(bytea) IS
  'Detects image MIME type from magic bytes. Returns NULL for unrecognized formats. '
  'Supported: PNG, JPEG, GIF, WebP. SVG is NOT supported due to XSS risks.';

-- Trigger function to validate image data on insert
-- This is a security measure to prevent XSS attacks via malicious file uploads
-- See: CodeQL js/xss-through-dom vulnerability
CREATE FUNCTION public.validate_image_on_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
AS $validate_image_on_insert$
DECLARE
  _detected_type text;
BEGIN
  _detected_type := public.detect_image_type(NEW.data);
  
  IF _detected_type IS NULL THEN
    RAISE EXCEPTION 'Invalid image data: unrecognized file format'
      USING HINT = 'Supported formats: PNG, JPEG, GIF, WebP. SVG is not allowed due to security restrictions.',
            ERRCODE = 'check_violation';
  END IF;
  
  -- Auto-correct the MIME type to match actual content
  -- This prevents attackers from uploading valid images with malicious Content-Type
  NEW.type := _detected_type;
  
  RETURN NEW;
END;
$validate_image_on_insert$;

COMMENT ON FUNCTION public.validate_image_on_insert() IS
  'Validates uploaded image data by checking magic bytes. '
  'Auto-corrects MIME type to prevent Content-Type spoofing attacks.';

CREATE TABLE public.image (
  id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  data bytea NOT NULL,
  type text NOT NULL DEFAULT 'image/png',
  uploaded_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  uploaded_by_user_id integer REFERENCES auth.user(id),
  
  -- Enforce 4MB limit (reasonable for photos/logos)
  CONSTRAINT image_size_limit CHECK (length(data) <= 4194304)
);

-- Use EXTERNAL storage for pre-compressed images
-- This prevents PostgreSQL from attempting compression and allows
-- efficient substring operations for streaming
ALTER TABLE public.image 
  ALTER COLUMN data SET STORAGE EXTERNAL;

-- Index for faster lookups
CREATE INDEX image_id_idx ON public.image(id);

-- Validation trigger - fires BEFORE INSERT to validate and auto-correct type
CREATE TRIGGER validate_image_before_insert
BEFORE INSERT ON public.image
FOR EACH ROW EXECUTE FUNCTION public.validate_image_on_insert();

COMMENT ON COLUMN public.image.uploaded_by_user_id IS 
  'User who uploaded the image';

COMMENT ON TABLE public.image IS 
  'Non-temporal storage for unit images (logos, photos). Referenced by legal_unit and establishment. '
  'Validates magic bytes on insert to prevent XSS attacks via malicious file uploads.';

COMMENT ON COLUMN public.image.data IS 
  'Binary image data with EXTERNAL storage (no compression). Max 4MB. '
  'Validated on insert: only PNG, JPEG, GIF, WebP allowed.';

COMMENT ON COLUMN public.image.type IS 
  'MIME type for proper Content-Type header. Auto-detected from magic bytes on insert '
  'to prevent Content-Type spoofing attacks.';

COMMIT;
