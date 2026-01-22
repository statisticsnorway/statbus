-- Create non-temporal table for storing unit images
-- This table is referenced by legal_unit and establishment (temporal tables)
-- to avoid duplicating large binary data across temporal versions

BEGIN;

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

COMMENT ON COLUMN public.image.uploaded_by_user_id IS 
  'User who uploaded the image';

COMMENT ON TABLE public.image IS 
  'Non-temporal storage for unit images (logos, photos). Referenced by legal_unit and establishment.';

COMMENT ON COLUMN public.image.data IS 
  'Binary image data with EXTERNAL storage (no compression). Max 4MB.';

COMMENT ON COLUMN public.image.type IS 
  'MIME type for proper Content-Type header (e.g., image/png, image/jpeg, image/webp)';

COMMIT;
