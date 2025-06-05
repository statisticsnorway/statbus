BEGIN;

CREATE TABLE public.activity_category_access (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id integer NOT NULL REFERENCES auth.user(id) ON DELETE CASCADE,
    activity_category_id integer NOT NULL REFERENCES public.activity_category(id) ON DELETE CASCADE,
    UNIQUE(user_id, activity_category_id)
);
CREATE INDEX ix_activity_category_access_activity_category_id ON public.activity_category_access USING btree (activity_category_id);
CREATE INDEX ix_activity_category_access_user_id ON public.activity_category_access USING btree (user_id);

-- Enable RLS on the activity_category_access table
ALTER TABLE public.activity_category_access ENABLE ROW LEVEL SECURITY;

-- Create policy for admin_user to have full access
CREATE POLICY activity_category_access_admin_policy ON public.activity_category_access 
    FOR ALL TO admin_user USING (true) WITH CHECK (true);

-- Create policy for read-only access for authenticated users
CREATE POLICY activity_category_access_read_policy ON public.activity_category_access 
    FOR SELECT TO authenticated USING (true);

END;
