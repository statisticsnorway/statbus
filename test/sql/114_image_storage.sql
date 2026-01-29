--
-- Test image storage functionality
-- Tests bytea storage with EXTERNAL TOAST strategy and image_data() RPC
--

-- Start transaction for clean test
BEGIN;

-- Reset sequence and clear table for deterministic ids
DELETE FROM public.image;
ALTER SEQUENCE public.image_id_seq RESTART WITH 1;

-- Test 1: Insert a small PNG image (1x1 pixel transparent PNG)
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

-- Test 2: Verify EXTERNAL storage strategy
SELECT 
  attname, 
  CASE attstorage
    WHEN 'e' THEN 'EXTERNAL'
    ELSE 'NOT_EXTERNAL'
  END as storage
FROM pg_attribute
WHERE attrelid = 'public.image'::regclass
AND attname = 'data';

-- Test 3: Test image_data() function (id=1 from sequence reset)
SELECT length(public.image_data(1)) as retrieved_length;

-- Test 4: Verify size constraint (4MB limit)
-- This INSERT should fail with check_violation (data > 4MB)
-- Use fixed timestamp so DETAIL line is deterministic
SAVEPOINT before_size_test;
\set ON_ERROR_STOP off
INSERT INTO public.image (data, type, uploaded_at) 
VALUES (
  repeat('x', 4194305)::bytea,  -- 4MB + 1 byte
  'image/png',
  '2024-01-01 00:00:00+00'::timestamptz
);
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT before_size_test;
-- Verify the oversized image was NOT inserted (should be 0)
SELECT COUNT(*) AS oversized_images_inserted FROM public.image WHERE length(data) > 4194304;

-- Test 5: Verify FK relationships
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

-- Test 6: Verify FK constraint works
-- Show the row we're targeting (with deterministic id=1 from sequence reset)
SELECT id, uploaded_by_user_id FROM public.image;
-- This UPDATE should fail with FK violation (user_id 99999 doesn't exist)
SAVEPOINT before_fk_test;
\set ON_ERROR_STOP off
UPDATE public.image 
SET uploaded_by_user_id = 99999
WHERE id = 1;
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT before_fk_test;
-- Verify the invalid user_id was NOT persisted (should be 0)
SELECT COUNT(*) AS rows_with_invalid_user FROM public.image WHERE uploaded_by_user_id = 99999;

-- Test 7: Verify RLS is enabled
SELECT 
  relname, 
  CASE relrowsecurity 
    WHEN true THEN 'ENABLED' 
    ELSE 'DISABLED' 
  END as rls_status
FROM pg_class
WHERE relname = 'image' 
  AND relnamespace = 'public'::regnamespace;

-- Cleanup
ROLLBACK;
