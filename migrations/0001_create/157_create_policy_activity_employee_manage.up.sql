BEGIN;

-- The employees can only update the tables designated by their assigned region or activity_category
CREATE POLICY activity_employee_manage ON public.activity FOR ALL TO authenticated
USING (auth.has_statbus_role(auth.uid(), 'restricted_user'::public.statbus_role_type)
       AND auth.has_activity_category_access(auth.uid(), category_id)
      )
WITH CHECK (auth.has_statbus_role(auth.uid(), 'restricted_user'::public.statbus_role_type)
       AND auth.has_activity_category_access(auth.uid(), category_id)
      );

--CREATE POLICY "premium and admin view access" ON premium_records FOR ALL TO authenticated USING (has_one_of_statbus_roles(auth.uid(), array['super_user', 'restricted_user']::public.statbus_role_type[]));

END;