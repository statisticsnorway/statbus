BEGIN;

-- Restore the original (buggy) location policy
DROP POLICY restricted_user_location_access ON public.location;
CREATE POLICY restricted_user_location_access ON public.location FOR ALL TO restricted_user
USING (
  EXISTS (
    SELECT 1
    FROM public.region_access ra
    WHERE ra.user_id = auth.uid()
      AND ra.region_id = region_id
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.region_access ra
    WHERE ra.user_id = auth.uid()
      AND ra.region_id = region_id
  )
);

-- Recreate the 2 dropped duplicate policies
CREATE POLICY regular_user_activity_access ON public.activity FOR ALL TO regular_user
USING (true)
WITH CHECK (true);

CREATE POLICY admin_user_activity_access ON public.activity FOR ALL TO admin_user
USING (true)
WITH CHECK (true);

END;
