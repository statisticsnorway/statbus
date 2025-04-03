BEGIN;

-- The restricted users can only update the tables designated by their assigned region or activity_category
CREATE POLICY restricted_user_activity_access ON public.activity FOR ALL TO restricted_user
USING (
  EXISTS (
    SELECT 1
    FROM public.activity_category_access aca
    WHERE aca.user_id = auth.uid()
      AND aca.activity_category_id = category_id
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.activity_category_access aca
    WHERE aca.user_id = auth.uid()
      AND aca.activity_category_id = category_id
  )
);

-- Regular users have full access to all activities
CREATE POLICY regular_user_activity_access ON public.activity FOR ALL TO regular_user
USING (true)
WITH CHECK (true);

-- Admin users have full access to all activities
CREATE POLICY admin_user_activity_access ON public.activity FOR ALL TO admin_user
USING (true)
WITH CHECK (true);

-- The restricted users can only update locations in their assigned regions
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

END;
