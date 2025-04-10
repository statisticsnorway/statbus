BEGIN;

-- Drop policies first
DROP POLICY IF EXISTS activity_category_access_admin_policy ON public.activity_category_access;
DROP POLICY IF EXISTS activity_category_access_read_policy ON public.activity_category_access;

-- Then drop the table
DROP TABLE IF EXISTS public.activity_category_access;

END;
