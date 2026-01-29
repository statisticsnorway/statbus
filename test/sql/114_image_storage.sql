--
-- Test image storage functionality
-- Tests bytea storage with EXTERNAL TOAST strategy, image_data() RPC,
-- and magic byte validation for XSS prevention
--

-- Start transaction for clean test
BEGIN;

-- Reset sequence and clear table for deterministic ids
DELETE FROM public.image;
ALTER SEQUENCE public.image_id_seq RESTART WITH 1;

-- ============================================================================
-- Test 1: Valid PNG image insertion
-- ============================================================================
-- This is a valid minimal PNG file (89 50 4E 47... = PNG signature)
-- Use fixed timestamp for reproducible output
INSERT INTO public.image (data, type, uploaded_at) 
VALUES (
  decode('89504e470d0a1a0a0000000d494844520000000100000001080600000001f15c48940000000a49444154789c6300010000050001', 'hex'),
  'image/png',
  '2024-01-01 00:00:00+00'::timestamptz
);

-- Verify the insert worked
SELECT type, length(data) as data_length, uploaded_at IS NOT NULL as has_timestamp
FROM public.image
ORDER BY id DESC LIMIT 1;

-- ============================================================================
-- Test 2: Valid JPEG image insertion  
-- ============================================================================
-- Minimal JPEG: FF D8 FF E0 (JFIF marker) + minimal structure
INSERT INTO public.image (data, type, uploaded_at)
VALUES (
  decode('ffd8ffe000104a46494600010100000100010000ffdb004300080606070605080707070909080a0c140d0c0b0b0c1912130f141d1a1f1e1d1a1c1c20242e2720222c231c1c2837292c30313434341f27393d38323c2e333432ffc0000b080001000101011100ffc40014000101000000000000000000000000000000ffc40014100100000000000000000000000000000000ffda00080101000000013f10', 'hex'),
  'wrong/type',  -- Intentionally wrong - should be auto-corrected to image/jpeg
  '2024-01-01 00:00:00+00'::timestamptz
);

-- Verify JPEG was inserted AND type was auto-corrected
SELECT type, length(data) as data_length
FROM public.image
WHERE id = 2;

-- ============================================================================
-- Test 3: Valid GIF image insertion (GIF89a)
-- ============================================================================
-- Minimal GIF89a: 47 49 46 38 39 61 (GIF89a)
INSERT INTO public.image (data, type, uploaded_at)
VALUES (
  decode('474946383961010001000000002c00000000010001000002024401003b', 'hex'),
  'image/gif',
  '2024-01-01 00:00:00+00'::timestamptz
);

-- Verify GIF was inserted
SELECT type, length(data) as data_length
FROM public.image
WHERE id = 3;

-- ============================================================================
-- Test 4: Valid WebP image insertion
-- ============================================================================
-- Minimal WebP: RIFF....WEBP structure
INSERT INTO public.image (data, type, uploaded_at)
VALUES (
  decode('52494646240000005745425056503820180000003001009d012a0100010002003425a00274ba01f80003b000feef94', 'hex'),
  'image/webp',
  '2024-01-01 00:00:00+00'::timestamptz
);

-- Verify WebP was inserted
SELECT type, length(data) as data_length
FROM public.image
WHERE id = 4;

-- ============================================================================
-- Test 5: Verify detect_image_type function works correctly
-- ============================================================================
SELECT 
  public.detect_image_type(decode('89504e470d0a1a0a', 'hex')) as png_detection,
  public.detect_image_type(decode('ffd8ffe0', 'hex')) as jpeg_detection,
  public.detect_image_type(decode('474946383961', 'hex')) as gif89a_detection,
  public.detect_image_type(decode('474946383761', 'hex')) as gif87a_detection,
  public.detect_image_type(decode('52494646ffffffff57454250', 'hex')) as webp_detection,
  public.detect_image_type(decode('3c7376673e', 'hex')) as svg_detection,  -- <svg> - should be NULL
  public.detect_image_type(decode('3c68746d6c3e', 'hex')) as html_detection;  -- <html> - should be NULL

-- ============================================================================
-- Test 6: REJECT invalid image data (HTML disguised as image) - XSS prevention
-- ============================================================================
SAVEPOINT before_html_test;
\set ON_ERROR_STOP off
-- This should FAIL - HTML content is NOT a valid image
INSERT INTO public.image (data, type, uploaded_at)
VALUES (
  decode('3c68746d6c3e3c7363726970743e616c657274282758535327293c2f7363726970743e3c2f68746d6c3e', 'hex'),  -- <html><script>alert('XSS')</script></html>
  'text/html',
  '2024-01-01 00:00:00+00'::timestamptz
);
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT before_html_test;

-- Verify HTML was NOT inserted
SELECT COUNT(*) AS html_files_inserted FROM public.image WHERE type = 'text/html';

-- ============================================================================
-- Test 7: REJECT SVG files (can contain JavaScript) - XSS prevention
-- ============================================================================
SAVEPOINT before_svg_test;
\set ON_ERROR_STOP off
-- This should FAIL - SVG is not allowed due to XSS risks
INSERT INTO public.image (data, type, uploaded_at)
VALUES (
  decode('3c7376672078', 'hex'),  -- <svg x (start of SVG)
  'image/svg+xml',
  '2024-01-01 00:00:00+00'::timestamptz
);
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT before_svg_test;

-- Verify SVG was NOT inserted
SELECT COUNT(*) AS svg_files_inserted FROM public.image WHERE type = 'image/svg+xml';

-- ============================================================================
-- Test 8: REJECT random binary data
-- ============================================================================
SAVEPOINT before_random_test;
\set ON_ERROR_STOP off
-- This should FAIL - random bytes don't match any image signature
INSERT INTO public.image (data, type, uploaded_at)
VALUES (
  decode('deadbeefcafebabe0123456789abcdef', 'hex'),
  'application/octet-stream',
  '2024-01-01 00:00:00+00'::timestamptz
);
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT before_random_test;

-- Verify random data was NOT inserted
SELECT COUNT(*) AS random_files_inserted FROM public.image WHERE type = 'application/octet-stream';

-- ============================================================================
-- Test 9: Verify EXTERNAL storage strategy
-- ============================================================================
SELECT 
  attname, 
  CASE attstorage
    WHEN 'e' THEN 'EXTERNAL'
    ELSE 'NOT_EXTERNAL'
  END as storage
FROM pg_attribute
WHERE attrelid = 'public.image'::regclass
AND attname = 'data';

-- ============================================================================
-- Test 10: Test image_data() function (id=1 from sequence reset)
-- ============================================================================
SELECT length(public.image_data(1)) as retrieved_length;

-- ============================================================================
-- Test 11: Verify size constraint (4MB limit)
-- ============================================================================
-- Create a valid PNG header followed by padding to exceed 4MB
-- PNG header: 89 50 4E 47 0D 0A 1A 0A (8 bytes)
SAVEPOINT before_size_test;
\set ON_ERROR_STOP off
INSERT INTO public.image (data, type, uploaded_at) 
VALUES (
  -- Valid PNG header + padding to exceed 4MB (4194305 bytes total)
  decode('89504e470d0a1a0a', 'hex') || decode(repeat('00', 4194297), 'hex'),
  'image/png',
  '2024-01-01 00:00:00+00'::timestamptz
);
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT before_size_test;

-- Verify the oversized image was NOT inserted
SELECT COUNT(*) AS oversized_images_inserted FROM public.image WHERE length(data) > 4194304;

-- ============================================================================
-- Test 12: Verify FK relationships
-- ============================================================================
SELECT 
  COUNT(*) as legal_unit_has_image_id_column
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name = 'legal_unit' 
  AND column_name = 'image_id';

SELECT 
  COUNT(*) as establishment_has_image_id_column
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name = 'establishment' 
  AND column_name = 'image_id';

-- ============================================================================
-- Test 13: Verify FK constraint works
-- ============================================================================
-- Show the row we're targeting (with deterministic id=1 from sequence reset)
SELECT id, uploaded_by_user_id FROM public.image WHERE id = 1;

-- This UPDATE should fail with FK violation (user_id 99999 doesn't exist)
SAVEPOINT before_fk_test;
\set ON_ERROR_STOP off
UPDATE public.image 
SET uploaded_by_user_id = 99999
WHERE id = 1;
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT before_fk_test;

-- Verify the invalid user_id was NOT persisted
SELECT COUNT(*) AS rows_with_invalid_user FROM public.image WHERE uploaded_by_user_id = 99999;

-- ============================================================================
-- Test 14: Verify RLS is enabled
-- ============================================================================
SELECT 
  relname, 
  CASE relrowsecurity 
    WHEN true THEN 'ENABLED' 
    ELSE 'DISABLED' 
  END as rls_status
FROM pg_class
WHERE relname = 'image' 
  AND relnamespace = 'public'::regnamespace;

-- ============================================================================
-- Test 15: Verify validation trigger exists
-- ============================================================================
SELECT 
  trigger_name,
  event_manipulation,
  action_timing
FROM information_schema.triggers
WHERE event_object_table = 'image'
  AND event_object_schema = 'public'
  AND trigger_name = 'validate_image_before_insert';

-- Cleanup
ROLLBACK;
