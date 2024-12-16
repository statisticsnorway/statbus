BEGIN;

-- The restricted users can only update the tables designated by their assigned region or activity_category
CREATE POLICY restricted_user_activity_access ON public.activity FOR ALL TO authenticated
USING (auth.has_statbus_role(auth.uid(), 'restricted_user'::public.statbus_role_type)
       AND auth.has_activity_category_access(auth.uid(), category_id)
      )
WITH CHECK (auth.has_statbus_role(auth.uid(), 'restricted_user'::public.statbus_role_type)
       AND auth.has_activity_category_access(auth.uid(), category_id)
      );

CREATE POLICY "regular_and_super_user_activity_access" ON public.activity FOR ALL TO authenticated
USING (auth.has_one_of_statbus_roles(auth.uid(), array['super_user', 'regular_user']::public.statbus_role_type[]))
WITH CHECK (auth.has_one_of_statbus_roles(auth.uid(), array['super_user', 'regular_user']::public.statbus_role_type[]));

END;
